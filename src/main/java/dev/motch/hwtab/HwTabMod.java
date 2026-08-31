package dev.motch.hwtab;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.FileTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import com.mojang.logging.LogUtils;

import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.fml.common.Mod;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

import org.slf4j.Logger;

/**
 * HwTab - shows host hardware stats in the TAB list header of a NeoForge
 * dedicated server, and publishes them for external consumers.
 *
 * <p>Once per second the mod reads {@code hw_stats_hw.txt} from the server
 * directory. That file is produced by an external helper script
 * ({@code scripts/hw_stats_loop.ps1} in the repository, running
 * LibreHardwareMonitor) and contains a whitespace-separated list of
 * {@code key=value} pairs:</p>
 *
 * <pre>
 * ram=8.2/15.7 cpu=22 temp=62
 * </pre>
 *
 * <p>The mod is the <em>authoritative</em> writer of {@code hw_stats.txt}:
 * every second it merges the hardware values with server-side values measured
 * in-process and rewrites the file atomically:</p>
 *
 * <pre>
 * ram=8.2/15.7 cpu=22 temp=62 tps=19.8 mspt=2.4 players=1 jvm=2.1/6.0
 * </pre>
 *
 * <ul>
 *   <li>{@code tps} / {@code mspt} - same calculation as BetterTab's TpsTab
 *       (rolling average of {@code getAverageTickTimeNanos()}); TPS is 0 while
 *       the tick rate manager reports the server as frozen</li>
 *   <li>{@code players} - online player count</li>
 *   <li>{@code jvm} - heap "used/max" in GB (the dashboard reads this)</li>
 * </ul>
 *
 * <p>The TAB header itself shows
 * {@code RAM 8.2/15.7GB | JVM 2.1/6.0GB | CPU 22% | 62C} - labels gray, values
 * aqua, temperature yellow above 70C and red above 85C. The JVM value always
 * comes from the server process itself, so the header still shows something
 * useful when the hardware file is missing, stale (older than 30 seconds) or
 * unreadable; unavailable items are simply left out. Degrees are rendered as
 * plain ASCII {@code C} on purpose.</p>
 *
 * <p>This mod never takes the server down: every read, write, parse and send
 * is wrapped in a catch-all.</p>
 */
@Mod(HwTabMod.MOD_ID)
public final class HwTabMod {

    public static final String MOD_ID = "hwtab";
    private static final Logger LOGGER = LogUtils.getLogger();

    /** Update header + stats file once per second (every 20 server ticks). */
    private static final int PERIOD_TICKS = 20;
    /** The hardware file must be younger than this; otherwise its values count as unavailable. */
    private static final long MAX_HW_FILE_AGE_MS = 30_000L;

    /** Written by scripts/hw_stats_loop.ps1 (ram/cpu/temp). Read-only for the mod. */
    private static final String HW_FILE_NAME = "hw_stats_hw.txt";
    /** Written by the mod itself; consumed by the TAB header and the dashboard. */
    private static final String OUT_FILE_NAME = "hw_stats.txt";

    private int tickCounter;

    public HwTabMod() {
        NeoForge.EVENT_BUS.addListener(this::onServerTick);
        LOGGER.info("[HwTab] Loaded - publishing {} to the TAB list header every second", OUT_FILE_NAME);
    }

    private void onServerTick(final ServerTickEvent.Post event) {
        if (++this.tickCounter < PERIOD_TICKS) {
            return;
        }
        this.tickCounter = 0;
        try {
            final MinecraftServer server = event.getServer();
            final Map<String, String> stats = collectStats(server);
            writeStatsFile(server, stats);

            final Component header = buildHeader(stats);
            final List<ServerPlayer> players = server.getPlayerList().getPlayers();
            for (final ServerPlayer player : players) {
                try {
                    player.setTabListHeader(header);
                } catch (final Throwable t) {
                    LOGGER.debug("[HwTab] failed to send header to one player", t);
                }
            }
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] tick update failed", t);
        }
    }

    /** Merges the external hardware file with in-process server measurements. */
    private static Map<String, String> collectStats(final MinecraftServer server) {
        final Map<String, String> stats = new HashMap<>();
        try {
            stats.putAll(readStats(server.getServerDirectory().resolve(HW_FILE_NAME)));
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not read {}", HW_FILE_NAME, t);
        }

        try {
            final double mspt = server.getAverageTickTimeNanos() / 1_000_000.0;
            double tps = 20.0;
            if (mspt > 0.0) {
                tps = Math.min(20.0, 1000.0 / mspt);
            }
            boolean frozen = false;
            try {
                frozen = !server.tickRateManager().runsNormally();
            } catch (final Throwable ignored) {
                // tick rate manager unavailable - assume normal ticking
            }
            if (frozen) {
                tps = 0.0;
            }
            stats.put("tps", String.format(Locale.ROOT, "%.1f", tps));
            stats.put("mspt", String.format(Locale.ROOT, "%.1f", mspt));
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not compute tick stats", t);
        }

        try {
            stats.put("players", String.valueOf(server.getPlayerCount()));
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not count players", t);
        }

        try {
            final MemoryUsage heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
            final long max = heap.getMax();
            if (max > 0) {
                stats.put("jvm", gb(heap.getUsed()) + "/" + gb(max));
            } else {
                stats.put("jvm", gb(heap.getUsed()));
            }
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not read heap usage", t);
        }

        return stats;
    }

    /** Atomically rewrites hw_stats.txt; never throws. */
    private static void writeStatsFile(final MinecraftServer server, final Map<String, String> stats) {
        try {
            final Path out = server.getServerDirectory().resolve(OUT_FILE_NAME);
            final Path tmp = server.getServerDirectory().resolve(OUT_FILE_NAME + ".tmp");
            final StringBuilder sb = new StringBuilder(128);
            append(sb, stats, "ram");
            append(sb, stats, "cpu");
            append(sb, stats, "temp");
            append(sb, stats, "tps");
            append(sb, stats, "mspt");
            append(sb, stats, "players");
            append(sb, stats, "jvm");
            Files.writeString(tmp, sb.toString(), StandardCharsets.UTF_8);
            try {
                Files.move(tmp, out, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (final Throwable atomicFailed) {
                Files.move(tmp, out, StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not write {}", OUT_FILE_NAME, t);
        }
    }

    private static void append(final StringBuilder sb, final Map<String, String> stats, final String key) {
        final String value = stats.get(key);
        if (value != null && !value.isEmpty()) {
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(key).append('=').append(value);
        }
    }

    private static Component buildHeader(final Map<String, String> stats) {
        final List<Component> parts = new ArrayList<>(4);

        final String ram = stats.get("ram");
        if (ram != null && !ram.isEmpty()) {
            parts.add(stat("RAM", ram + "GB", ChatFormatting.AQUA));
        }

        final String jvm = stats.get("jvm");
        if (jvm != null && !jvm.isEmpty()) {
            parts.add(stat("JVM", jvm + "GB", ChatFormatting.AQUA));
        }

        final String cpu = stats.get("cpu");
        if (cpu != null && !cpu.isEmpty()) {
            parts.add(stat("CPU", cpu + "%", ChatFormatting.AQUA));
        }

        final String temp = stats.get("temp");
        if (temp != null && !temp.isEmpty()) {
            parts.add(Component.literal(temp + "C").withStyle(tempColor(temp)));
        }

        final MutableComponent header = Component.empty();
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) {
                header.append(Component.literal(" | ").withStyle(ChatFormatting.DARK_GRAY));
            }
            header.append(parts.get(i));
        }
        return header;
    }

    private static ChatFormatting tempColor(final String raw) {
        try {
            final double value = Double.parseDouble(raw.trim());
            if (value > 85.0) {
                return ChatFormatting.RED;
            }
            if (value > 70.0) {
                return ChatFormatting.YELLOW;
            }
        } catch (final NumberFormatException ignored) {
            // fall through to the default color
        }
        return ChatFormatting.AQUA;
    }

    private static String gb(final long bytes) {
        return String.format(Locale.ROOT, "%.1f", bytes / (1024.0 * 1024.0 * 1024.0));
    }

    private static Component stat(final String label, final String value, final ChatFormatting valueColor) {
        return Component.literal(label + " ")
                .withStyle(ChatFormatting.GRAY)
                .append(Component.literal(value).withStyle(valueColor));
    }

    /**
     * Reads and parses a whitespace-separated key=value file. Returns an empty
     * map whenever the file is missing, stale or malformed - never throws.
     */
    private static Map<String, String> readStats(final Path file) {
        final Map<String, String> stats = new HashMap<>();
        try {
            if (!Files.isRegularFile(file)) {
                return stats;
            }
            final FileTime modified = Files.getLastModifiedTime(file);
            final long age = System.currentTimeMillis() - modified.toMillis();
            if (age > MAX_HW_FILE_AGE_MS || age < -MAX_HW_FILE_AGE_MS) {
                return stats;
            }
            final String content = Files.readString(file, StandardCharsets.UTF_8);
            for (final String token : content.split("\\s+")) {
                final int eq = token.indexOf('=');
                if (eq > 0 && eq < token.length() - 1) {
                    stats.put(token.substring(0, eq).toLowerCase(Locale.ROOT), token.substring(eq + 1).trim());
                }
            }
        } catch (final Throwable t) {
            LOGGER.debug("[HwTab] could not read {}", file, t);
        }
        return stats;
    }
}
