# MC Node Dashboard - zero-dependency HttpListener dashboard for the MCServer laptop.
#   GET  /          -> single-page dashboard (dark, Kubernetes-style, Japanese, no CDN)
#   GET  /api/stats -> JSON snapshot (node + minecraft + log tail)
# Listens on http://+:8787/ (LAN only - inbound is scoped by the
# "MCServer Dashboard" firewall rule to 192.168.1.0/24).
# Designed for scheduled task MCServer-Dashboard (SYSTEM / onstart / HIGHEST).
# The outer loop never exits: every failure is caught, the listener is rebuilt.
$ErrorActionPreference = 'Continue'
$mcDir = 'C:\Users\motch\MCServer'
$hwFile = Join-Path $mcDir 'hw_stats_hw.txt'
$statsFile = Join-Path $mcDir 'hw_stats.txt'
$logFile = Join-Path $mcDir 'logs\latest.log'
$staleSec = 30
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

$script:html = @'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MC Node Dashboard</title>
<style>
:root{--bg:#0f141a;--card:#171e28;--card2:#131a23;--line:#232d3f;--tx:#dbe2ea;--mut:#8b98a9;--ok:#2ecc71;--warn:#f1c40f;--crit:#e74c3c;--acc:#4f8cff}
*{box-sizing:border-box;margin:0;padding:0}
body{background:radial-gradient(1200px 600px at 20% -10%,#16202c 0%,var(--bg) 55%);color:var(--tx);font-family:"Segoe UI","Hiragino Sans","Yu Gothic UI",system-ui,sans-serif;padding:22px;min-height:100vh}
header{display:flex;justify-content:space-between;align-items:center;max-width:1180px;margin:0 auto 18px}
h1{font-size:21px;font-weight:650;letter-spacing:.4px}
.sub{color:var(--mut);font-size:12px;margin-top:3px}
.pill{border:1px solid var(--line);border-radius:999px;padding:5px 14px;font-size:12.5px;font-weight:600;background:var(--card);color:var(--mut)}
.pill.ok{color:var(--ok);border-color:rgba(46,204,113,.45)}
.pill.warn{color:var(--warn);border-color:rgba(241,196,15,.45)}
.pill.crit{color:var(--crit);border-color:rgba(231,76,60,.5)}
.grid{max-width:1180px;margin:0 auto;display:grid;grid-template-columns:1fr 1fr;gap:16px}
.card{background:linear-gradient(180deg,var(--card),var(--card2));border:1px solid var(--line);border-radius:12px;padding:16px 18px;box-shadow:0 6px 24px rgba(0,0,0,.25)}
.card.node{grid-column:1}
.card.mc{grid-column:2}
.card.wide{grid-column:1 / span 2}
h2{display:flex;justify-content:space-between;align-items:center;font-size:12.5px;text-transform:uppercase;letter-spacing:1.4px;color:var(--mut);margin-bottom:14px;font-weight:600}
.badge{font-size:11.5px;letter-spacing:.6px;padding:3px 10px;border-radius:6px;background:#1d2836;color:var(--mut);font-weight:700}
.badge.ok{background:rgba(46,204,113,.14);color:var(--ok)}
.badge.crit{background:rgba(231,76,60,.14);color:var(--crit)}
.row{display:flex;justify-content:space-between;font-size:13.5px;margin:11px 0 5px}
.label{color:var(--mut)}
.value{font-weight:600;font-variant-numeric:tabular-nums}
.bar{height:7px;background:#0d1218;border-radius:5px;overflow:hidden;border:1px solid #1a2331}
.bar>span{display:block;height:100%;width:0%;background:var(--acc);border-radius:5px;transition:width .6s ease}
.bar>span.ok{background:var(--ok)}
.bar>span.warn{background:var(--warn)}
.bar>span.crit{background:var(--crit)}
pre#log{font-family:Consolas,"Courier New",monospace;font-size:11.5px;line-height:1.55;color:#aebccb;background:#0b0f14;border:1px solid var(--line);border-radius:8px;padding:12px 14px;height:230px;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:0}
.hint{font-size:10.5px;letter-spacing:.4px;text-transform:none;color:#5d6b7d}
footer{max-width:1180px;margin:14px auto 0;color:#5d6b7d;font-size:11px;text-align:center}
@media (max-width:820px){.grid{grid-template-columns:1fr}.card.node,.card.mc,.card.wide{grid-column:1}}
</style>
</head>
<body>
<header>
  <div>
    <h1>MC Node Dashboard</h1>
    <div class="sub">ST-LAPTOP · Minecraft 1.21.1 / NeoForge · 3秒間隔で自動更新</div>
  </div>
  <span id="overall" class="pill">取得中…</span>
</header>
<main class="grid">
  <section class="card node">
    <h2><span>Node Health</span><span id="nodeState" class="badge">--</span></h2>
    <div class="row"><span class="label">CPU使用率</span><span class="value" id="cpu">--</span></div>
    <div class="bar"><span id="cpuBar"></span></div>
    <div class="row"><span class="label">メモリ使用量</span><span class="value" id="ram">--</span></div>
    <div class="bar"><span id="ramBar"></span></div>
    <div class="row"><span class="label">CPU温度</span><span class="value" id="temp">--</span></div>
    <div class="bar"><span id="tempBar"></span></div>
    <div class="row"><span class="label">ディスク C: 空き</span><span class="value" id="disk">--</span></div>
    <div class="row"><span class="label">システム稼働時間</span><span class="value" id="uptime">--</span></div>
  </section>
  <section class="card mc">
    <h2><span>Workload: minecraft-server</span><span id="mcState" class="badge">--</span></h2>
    <div class="row"><span class="label">TPS (20.0が正常)</span><span class="value" id="tps">--</span></div>
    <div class="row"><span class="label">MSPT</span><span class="value" id="mspt">--</span></div>
    <div class="row"><span class="label">プレイヤー数</span><span class="value" id="players">--</span></div>
    <div class="row"><span class="label">JVMヒープ</span><span class="value" id="heap">--</span></div>
    <div class="bar"><span id="heapBar"></span></div>
    <div class="row"><span class="label">サーバー稼働時間</span><span class="value" id="mcUptime">--</span></div>
  </section>
  <section class="card wide">
    <h2><span>Log Tail</span><span class="hint">logs/latest.log 末尾15行 · 自動スクロールなし</span></h2>
    <pre id="log">読み込み中…</pre>
  </section>
</main>
<footer>HwTab dashboard · HTTP :8787 (LAN 192.168.1.0/24 のみ) · 外部CDN不使用</footer>
<script>
const $ = id => document.getElementById(id);
const fmt = (v, d) => (v === null || v === undefined || isNaN(v)) ? 'n/a' : Number(v).toFixed(d === undefined ? 1 : d);
function bar(el, pct, cls) { el.style.width = Math.max(0, Math.min(100, pct || 0)) + '%'; el.className = cls || ''; }
function statusOf(t, warn, crit) { if (t === null || t === undefined || isNaN(t)) return null; return t >= crit ? 'crit' : (t >= warn ? 'warn' : 'ok'); }
async function tick() {
  try {
    const r = await fetch('/api/stats', { cache: 'no-store' });
    if (!r.ok) throw new Error('http ' + r.status);
    const s = await r.json();
    const n = s.node || {}, mc = s.mc || {};
    $('cpu').textContent = fmt(n.cpu, 0) + '%';
    bar($('cpuBar'), n.cpu, statusOf(n.cpu, 85, 95) || '');
    if (n.ramUsed !== null && n.ramUsed !== undefined && n.ramTotal) {
      const p = n.ramUsed / n.ramTotal * 100;
      $('ram').textContent = fmt(n.ramUsed) + ' / ' + fmt(n.ramTotal, 0) + ' GB (' + Math.round(p) + '%)';
      bar($('ramBar'), p, statusOf(p, 90, 97) || '');
    } else { $('ram').textContent = 'n/a'; bar($('ramBar'), 0, ''); }
    const t = n.tempC;
    if (t === null || t === undefined) { $('temp').textContent = 'n/a (センサーなし)'; $('temp').style.color = 'var(--mut)'; bar($('tempBar'), 0, ''); }
    else {
      $('temp').textContent = fmt(t, 0) + ' °C';
      $('temp').style.color = t > 85 ? 'var(--crit)' : (t > 70 ? 'var(--warn)' : 'var(--ok)');
      bar($('tempBar'), Math.min(100, Math.max(0, (t - 40) * 2.5)), t > 85 ? 'crit' : (t > 70 ? 'warn' : ''));
    }
    $('disk').textContent = (n.diskFreeGB === null || n.diskFreeGB === undefined) ? 'n/a' : fmt(n.diskFreeGB) + ' GB';
    $('uptime').textContent = n.uptimeText || 'n/a';
    const up = mc.state === 'Running';
    $('mcState').textContent = up ? 'Running' : 'Down';
    $('mcState').className = 'badge ' + (up ? 'ok' : 'crit');
    const tps = mc.tps;
    $('tps').textContent = fmt(tps);
    $('tps').style.color = (tps === null || tps === undefined) ? 'var(--mut)' : (tps < 10 ? 'var(--crit)' : (tps < 15 ? 'var(--warn)' : 'var(--ok)'));
    const ms = mc.mspt;
    $('mspt').textContent = (ms === null || ms === undefined) ? 'n/a' : fmt(ms) + ' ms';
    $('mspt').style.color = (ms === null || ms === undefined) ? 'var(--mut)' : (ms > 50 ? 'var(--crit)' : (ms > 30 ? 'var(--warn)' : 'var(--ok)'));
    $('players').textContent = (mc.players === null || mc.players === undefined) ? 'n/a' : mc.players + ' 人';
    if (mc.heapUsed !== null && mc.heapUsed !== undefined && mc.heapMax) {
      const p = mc.heapUsed / mc.heapMax * 100;
      $('heap').textContent = fmt(mc.heapUsed) + ' / ' + fmt(mc.heapMax) + ' GB (' + Math.round(p) + '%)';
      bar($('heapBar'), p, statusOf(p, 85, 95) || '');
    } else { $('heap').textContent = 'n/a'; bar($('heapBar'), 0, ''); }
    $('mcUptime').textContent = mc.uptimeText || 'n/a';
    $('log').textContent = (s.logTail && s.logTail.length) ? s.logTail.join('\n') : 'n/a';
    let worst = 'ok';
    if (!up) worst = 'crit';
    if (statusOf(t, 70, 85) === 'warn' && worst !== 'crit') worst = 'warn';
    if (statusOf(t, 70, 85) === 'crit') worst = 'crit';
    if (tps !== null && tps !== undefined && tps < 15 && worst === 'ok') worst = 'warn';
    if (tps !== null && tps !== undefined && tps < 10) worst = 'crit';
    const labels = { ok: '正常 (Healthy)', warn: '警告 (Warning)', crit: '異常 (Critical)' };
    $('overall').textContent = labels[worst];
    $('overall').className = 'pill ' + worst;
    $('nodeState').textContent = 'NODE';
    $('nodeState').className = 'badge ' + (statusOf(t, 70, 85) === 'crit' ? 'crit' : 'ok');
  } catch (e) {
    $('overall').textContent = 'API接続エラー';
    $('overall').className = 'pill crit';
  }
}
tick();
setInterval(tick, 3000);
</script>
</body>
</html>
'@

function Read-KeyValueFile([string]$path) {
    $map = @{}
    try {
        if (-not (Test-Path $path)) { return $map }
        $age = ((Get-Date) - (Get-Item $path).LastWriteTime).TotalSeconds
        if ($age -gt $staleSec -or $age -lt -5) { return $map }
        $content = [System.IO.File]::ReadAllText($path)
        foreach ($tok in ($content -split '\s+')) {
            $i = $tok.IndexOf('=')
            if ($i -gt 0 -and $i -lt ($tok.Length - 1)) {
                $map[$tok.Substring(0, $i).ToLower()] = $tok.Substring($i + 1)
            }
        }
    } catch { }
    return $map
}

function Format-Duration($ts) {
    try {
        if ($null -eq $ts -or $ts.TotalMinutes -lt 0) { return $null }
        $d = [int][math]::Floor($ts.TotalDays)
        $h = $ts.Hours
        $m = $ts.Minutes
        if ($d -gt 0) { return ('{0}日{1}時間{2}分' -f $d, $h, $m) }
        if ($h -gt 0) { return ('{0}時間{1}分' -f $h, $m) }
        return ('{0}分' -f $m)
    } catch { return $null }
}

function InvNum($v) {
    if ($null -eq $v) { return 'null' }
    try { return ([double]$v).ToString($invariant) } catch { return 'null' }
}

function Esc-Json([string]$s) {
    if ($null -eq $s) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq [char]34) { [void]$sb.Append('\"') }
        elseif ($ch -eq [char]92) { [void]$sb.Append('\\') }
        elseif ($c -eq 10) { [void]$sb.Append('\n') }
        elseif ($c -eq 13) { [void]$sb.Append('\r') }
        elseif ($c -eq 9) { [void]$sb.Append('\t') }
        elseif ($c -lt 32) { [void]$sb.Append('\u' + $c.ToString('x4')) }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Get-Snapshot {
    $hw = Read-KeyValueFile $hwFile
    $sv = Read-KeyValueFile $statsFile

    $cpu = $null; $ramU = $null; $ramT = $null; $tempC = $null
    if ($hw.ContainsKey('cpu')) { try { $cpu = [double]$hw['cpu'] } catch { } }
    if ($hw.ContainsKey('ram')) {
        $parts = $hw['ram'] -split '/'
        if ($parts.Count -eq 2) { try { $ramU = [double]$parts[0]; $ramT = [double]$parts[1] } catch { } }
    }
    if ($hw.ContainsKey('temp')) { try { $tempC = [double]$hw['temp'] } catch { } }
    if ($null -eq $cpu) {
        try {
            $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
            if ($null -ne $cpu) { $cpu = [double]$cpu }
        } catch { }
    }
    if ($null -eq $ramT) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $ramT = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $ramU = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        } catch { }
    }
    $upText = $null
    try {
        $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $upText = Format-Duration ((Get-Date) - $os2.LastBootUpTime)
    } catch { }
    $disk = $null
    try {
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $disk = [math]::Round($d.FreeSpace / 1GB, 1)
    } catch { }

    $state = 'Down'
    $mcUpText = $null
    try {
        $javas = Get-Process java -ErrorAction SilentlyContinue
        $listen = Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue
        if ($javas -and $listen) {
            $state = 'Running'
            $first = $javas | Sort-Object StartTime -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($first) { $mcUpText = Format-Duration ((Get-Date) - $first.StartTime) }
        }
    } catch { }

    $tps = $null; $mspt = $null; $players = $null; $hU = $null; $hM = $null
    if ($sv.ContainsKey('tps')) { try { $tps = [double]$sv['tps'] } catch { } }
    if ($sv.ContainsKey('mspt')) { try { $mspt = [double]$sv['mspt'] } catch { } }
    if ($sv.ContainsKey('players')) { try { $players = [int]$sv['players'] } catch { } }
    if ($sv.ContainsKey('jvm')) {
        $parts2 = $sv['jvm'] -split '/'
        try { $hU = [double]$parts2[0]; if ($parts2.Count -gt 1) { $hM = [double]$parts2[1] } } catch { }
    }

    $logLines = @()
    try { $logLines = @(Get-Content $logFile -Tail 15 -Encoding UTF8 -ErrorAction Stop) } catch { }
    $logJson = ($logLines | ForEach-Object { '"' + (Esc-Json $_) + '"' }) -join ','

    $json = '{'
    $json += '"node":{"cpu":' + (InvNum $cpu) + ',"ramUsed":' + (InvNum $ramU) + ',"ramTotal":' + (InvNum $ramT) + ',"tempC":' + (InvNum $tempC) + ',"uptimeText":"' + (Esc-Json $upText) + '","diskFreeGB":' + (InvNum $disk) + '},'
    $json += '"mc":{"state":"' + $state + '","tps":' + (InvNum $tps) + ',"mspt":' + (InvNum $mspt) + ',"players":' + (InvNum $players) + ',"heapUsed":' + (InvNum $hU) + ',"heapMax":' + (InvNum $hM) + ',"uptimeText":"' + (Esc-Json $mcUpText) + '"},'
    $json += '"logTail":[' + $logJson + ']}'
    return $json
}

$listener = $null
$failCount = 0
while ($true) {
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add('http://+:8787/')
        $listener.Start()
        $failCount = 0
        while ($listener.IsListening) {
            $ctx = $null
            try { $ctx = $listener.GetContext() } catch { break }
            $res = $ctx.Response
            try {
                $res.Headers.Add('Cache-Control', 'no-store')
                $path = $ctx.Request.Url.AbsolutePath
                if ($path -eq '/api/stats') {
                    $body = [System.Text.Encoding]::UTF8.GetBytes((Get-Snapshot))
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.ContentLength64 = $body.Length
                    $res.OutputStream.Write($body, 0, $body.Length)
                } elseif ($path -eq '/' -or $path -eq '/index.html') {
                    $body = [System.Text.Encoding]::UTF8.GetBytes($script:html)
                    $res.ContentType = 'text/html; charset=utf-8'
                    $res.ContentLength64 = $body.Length
                    $res.OutputStream.Write($body, 0, $body.Length)
                } else {
                    $res.StatusCode = 404
                    $body = [System.Text.Encoding]::UTF8.GetBytes('not found')
                    $res.ContentType = 'text/plain; charset=utf-8'
                    $res.ContentLength64 = $body.Length
                    $res.OutputStream.Write($body, 0, $body.Length)
                }
            } catch { }
            try { $res.Close() } catch { }
        }
    } catch {
        $failCount++
        if ($failCount -gt 5) { Start-Sleep -Seconds 30 } else { Start-Sleep -Seconds 2 }
    }
    try { if ($listener -ne $null) { $listener.Stop() } } catch { }
    Start-Sleep -Seconds 1
}
