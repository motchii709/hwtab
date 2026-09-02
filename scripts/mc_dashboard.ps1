# MC Node Console - zero-dependency HttpListener dashboard (M3 Expressive v3.1) + ops console.
#   GET  /                  -> single-page M3 Expressive console (no CDN)
#   GET  /api/stats         -> JSON snapshot (node + mc + action + mods + log tail)
#   GET  /api/mods          -> mod inventory
#   GET  /api/logs          -> available log files
#   GET  /api/log           -> tail (?lines=) or delta (?offset=) of a log file
#   GET  /api/log/download  -> raw log file attachment
#   POST /api/action/*      -> restart / stop / start (spawns mc_action.ps1 detached)
#   POST /api/mods/toggle   -> enable/disable mod (.jar <-> .jar.disabled)
#   POST /api/mods/delete   -> move mod to mods\_trash
#   POST /api/mods/upload   -> raw octet-stream jar upload (?name=)
# Listens on http://*:8787/ (LAN only - scoped by firewall rule "MCServer Dashboard").
# Designed for scheduled task MCServer-Dashboard (SYSTEM / onstart / HIGHEST).
$ErrorActionPreference = 'Continue'
$mcDir = 'C:\Users\motch\MCServer'
$hwFile = Join-Path $mcDir 'hw_stats_hw.txt'
$statsFile = Join-Path $mcDir 'hw_stats.txt'
$logDir = Join-Path $mcDir 'logs'
$logFile = Join-Path $logDir 'latest.log'
$modsDir = Join-Path $mcDir 'mods'
$trashDir = Join-Path $modsDir '_trash'
$actionScript = 'C:\Users\motch\MCServer\hwtools\mc_action.ps1'
$actionStateFile = 'C:\Users\motch\MCServer\hwtools\mc_action_state.txt'
$staleSec = 30
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

$script:html = @'
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MC Node Console — ST-LAPTOP</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='9' fill='%234A5AD8'/%3E%3Cpath d='M8 21V11l5 5 3-6 3 6 5-5v10' stroke='%23fff' stroke-width='2.4' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E">
<style>
:root{
  --primary:#4a5ad8; --on-primary:#fff; --primary-container:#dfe0ff; --on-primary-container:#000f5a;
  --secondary-container:#e1e2f9; --on-secondary-container:#1a1c2e;
  --tertiary-container:#b8f1b6; --on-tertiary-container:#00210a;
  --error:#b3261e; --on-error:#fff; --error-container:#f9dedc; --on-error-container:#410e0b;
  --warn:#9a6300; --warn-container:#ffddb3;
  --surface:#fbf8ff; --on-surface:#1b1b21; --on-surface-var:#46464f;
  --outline:#767680; --outline-var:#c7c5d2;
  --sc-low:#f5f2fc; --sc:#efedf7; --sc-high:#e9e7f1; --sc-highest:#e3e1eb;
  --term-bg:#15151c; --term-fg:#e5e1e9; --term-dim:#8e8a96; --term-warn:#ffb868; --term-err:#ffb4ab; --term-ok:#7adb8f;
  --emph:cubic-bezier(.2,0,0,1);
  --spring:cubic-bezier(.34,1.56,.64,1);
  --spring-soft:cubic-bezier(.3,1.3,.5,1);
  --shadow:0 1px 2px rgba(35,32,84,.18),0 6px 20px rgba(35,32,84,.10);
}
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{background:var(--surface);color:var(--on-surface);min-height:100dvh;
  font-family:"Segoe UI Variable Text","Segoe UI",Roboto,"Noto Sans JP","Yu Gothic UI",sans-serif}
::selection{background:var(--primary-container);color:var(--on-primary-container)}
button,input,select{font-family:inherit}
:focus-visible{outline:3px solid var(--primary);outline-offset:2px;border-radius:8px}
.wrap{max-width:1280px;margin:0 auto;padding:0 20px 64px}

/* ---------- app bar ---------- */
.appbar{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;
  padding:20px 0 14px;position:sticky;top:0;background:color-mix(in srgb,var(--surface) 88%,transparent);
  backdrop-filter:blur(12px);z-index:50}
.brand{display:flex;align-items:center;gap:14px}
.logo{width:44px;height:44px;border-radius:14px;background:var(--primary);display:grid;place-items:center;flex:0 0 auto}
.brand h1{font-size:26px;font-weight:650;letter-spacing:-.02em;line-height:1.1}
.brand .sub{font-size:12.5px;color:var(--on-surface-var);letter-spacing:.02em}
.abar-right{display:flex;align-items:center;gap:10px;flex-wrap:wrap}

/* ---------- chips ---------- */
.chip{display:inline-flex;align-items:center;gap:7px;border-radius:999px;padding:7px 15px;
  font-size:13px;font-weight:600;background:var(--sc-high);color:var(--on-surface-var);border:none;
  transition:transform .3s var(--spring-soft),background-color .25s var(--emph);white-space:nowrap}
.chip .dot{width:8px;height:8px;border-radius:99px;background:var(--on-surface-var)}
.chip.ok{background:var(--tertiary-container);color:var(--on-tertiary-container)}
.chip.ok .dot{background:#1d7a2c}
.chip.bad{background:var(--error-container);color:var(--on-error-container)}
.chip.bad .dot{background:var(--error)}
.chip.warn{background:var(--warn-container);color:var(--warn)}
.chip.plain{background:var(--sc);font-variant-numeric:tabular-nums}
.chip.tog{cursor:pointer;border:1px solid var(--outline-var)}
.chip.tog.on{background:var(--secondary-container);color:var(--on-secondary-container);border-color:transparent}
.chip.tog:active{transform:scale(.86)}

/* ---------- buttons ---------- */
.btn{display:inline-flex;align-items:center;gap:8px;border:none;cursor:pointer;border-radius:999px;
  padding:11px 22px;font-size:14px;font-weight:600;letter-spacing:.01em;
  transition:transform .25s var(--emph),box-shadow .25s var(--emph),background-color .25s var(--emph),color .25s var(--emph)}
.btn:hover:not(:disabled){transform:translateY(-1px)}
.btn:active:not(:disabled){transform:scale(.92)}
.btn:disabled{opacity:.38;cursor:not-allowed}
.btn.filled{background:var(--primary);color:var(--on-primary);box-shadow:var(--shadow)}
.btn.filled:hover:not(:disabled){background:#3d4bc2}
.btn.tonal{background:var(--secondary-container);color:var(--on-secondary-container)}
.btn.tonal:hover:not(:disabled){background:#d5d7f4}
.btn.dangert{background:var(--error-container);color:var(--on-error-container)}
.btn.dangert:hover:not(:disabled){background:#f3cfcc}
.btn.armed{background:var(--error);color:var(--on-error)}
.btn.text{background:transparent;color:var(--primary);padding:9px 14px}
.btn.text:hover{background:var(--sc)}
.btn.text.danger{color:var(--error)}
.btn.text.danger:hover{background:var(--error-container)}
.fab{display:inline-flex;align-items:center;gap:8px;border:none;cursor:pointer;border-radius:18px;
  background:var(--primary-container);color:var(--on-primary-container);padding:9px 18px 9px 13px;
  font-size:14px;font-weight:600;box-shadow:var(--shadow);
  transition:transform .25s var(--emph),background-color .25s var(--emph)}
.fab:hover{background:#d3d5ff;border-radius:26px;transform:translateY(-1px)}
.fab:active{transform:scale(.92)}
.fab{transition:transform .35s var(--spring),background-color .25s var(--emph),border-radius .35s var(--spring)}
.fab svg{width:20px;height:20px}

/* ---------- cards ---------- */
.card{background:var(--sc-low);border-radius:28px;padding:22px;box-shadow:var(--shadow)}
.card.plain{background:var(--sc-low)}
.card h2{font-size:19px;font-weight:650;letter-spacing:-.01em}
.lbl{font-size:12.5px;font-weight:600;color:var(--on-surface-var);letter-spacing:.03em}
.display{font-size:44px;font-weight:700;letter-spacing:-.035em;line-height:1.02;margin-top:6px;
  font-variant-numeric:tabular-nums;display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}
.display small{font-size:16px;font-weight:600;color:var(--on-surface-var);letter-spacing:0}
.sub{font-size:12.5px;color:var(--on-surface-var);margin-top:8px;line-height:1.5}

/* ---------- hero ---------- */
.hero{display:grid;grid-template-columns:1.25fr .9fr 1fr;gap:14px;margin-top:6px}
.status-card .display{font-size:46px}
.status-card.ok{background:var(--tertiary-container)}
.status-card.ok .display,.status-card.ok .lbl{color:var(--on-tertiary-container)}
.status-card.ok .sub{color:color-mix(in srgb,var(--on-tertiary-container) 78%,transparent)}
.status-card.crit{background:var(--error-container)}
.status-card.crit .display,.status-card.crit .lbl{color:var(--on-error-container)}
.status-card.crit .sub{color:color-mix(in srgb,var(--on-error-container) 80%,transparent)}
.status-card.warn{background:var(--warn-container)}
.status-card.warn .display,.status-card.warn .lbl{color:var(--warn)}
.status-card.warn .sub{color:color-mix(in srgb,var(--warn) 85%,transparent)}
.status-card{position:relative;overflow:hidden}
.status-card>*:not(.blob){position:relative;z-index:1}
.status-card .blob{position:absolute;right:-48px;top:-48px;width:200px;height:200px;z-index:0;opacity:.13;filter:blur(1px);
  background:currentColor;pointer-events:none;
  border-radius:44% 56% 58% 42%/46% 42% 58% 54%;animation:blobm 9s var(--emph) infinite alternate}
.status-card.ok .blob{color:#1d7a2c}
.status-card.warn .blob{color:var(--warn)}
.status-card.crit .blob{color:var(--error)}
@keyframes blobm{0%{border-radius:44% 56% 58% 42%/46% 42% 58% 54%;transform:rotate(0deg) scale(1)}
  50%{border-radius:58% 42% 44% 56%/54% 58% 42% 46%;transform:rotate(15deg) scale(1.14)}
  100%{border-radius:38% 62% 52% 48%/58% 38% 62% 42%;transform:rotate(30deg) scale(1.26)}}
.tps-card{background:var(--primary-container)}
.tps-card .lbl{color:var(--on-primary-container)}
.tps-card .display{color:var(--on-primary-container);font-size:58px;font-weight:750;letter-spacing:-.04em}
.tps-card .display small{color:color-mix(in srgb,var(--on-primary-container) 70%,transparent)}
.tps-card .sub{color:color-mix(in srgb,var(--on-primary-container) 72%,transparent)}
.ring{position:absolute;right:28px;top:30px;width:56px;height:56px;border-radius:99px;border:3px solid var(--on-primary-container);
  opacity:0;pointer-events:none;z-index:0}
.ring.pulse{animation:ringp 1.2s var(--emph) forwards}
@keyframes ringp{0%{opacity:.35;transform:scale(.45)}100%{opacity:0;transform:scale(1.7)}}
.quick-card{display:flex;flex-direction:column;gap:9px;justify-content:center}
.qrow{display:flex;justify-content:space-between;align-items:baseline;gap:10px;font-size:13px;color:var(--on-surface-var)}
.qrow b{font-weight:650;color:var(--on-surface);font-variant-numeric:tabular-nums}

/* ---------- metrics ---------- */
.mgrid{display:grid;grid-template-columns:repeat(6,1fr);gap:14px;margin-top:14px}
.mcard{display:flex;flex-direction:column;min-height:128px}
.mval{font-size:30px;font-weight:700;letter-spacing:-.03em;margin-top:auto;padding-top:14px;
  font-variant-numeric:tabular-nums;line-height:1;display:flex;align-items:baseline;gap:5px}
.mval small{font-size:13px;font-weight:600;color:var(--on-surface-var)}
.mval.na{color:var(--outline);font-size:19px;font-weight:600;letter-spacing:0}
.mcard[data-state="warn"] .mval{color:var(--warn)}
.mcard[data-state="crit"] .mval{color:var(--error)}
.prog{height:10px;border-radius:99px;background:var(--sc-highest);margin-top:11px;overflow:hidden}
.prog>span{display:block;height:100%;border-radius:99px;width:0%;color:var(--primary);background-color:currentColor;
  -webkit-mask-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='26' height='10' viewBox='0 0 26 10'%3E%3Cpath d='M0 5 Q6.5 .4 13 5 T26 5' fill='none' stroke='%23fff' stroke-width='2.8' stroke-linecap='round'/%3E%3C/svg%3E");
  -webkit-mask-size:26px 10px;-webkit-mask-repeat:repeat-x;
  mask-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='26' height='10' viewBox='0 0 26 10'%3E%3Cpath d='M0 5 Q6.5 .4 13 5 T26 5' fill='none' stroke='%23fff' stroke-width='2.8' stroke-linecap='round'/%3E%3C/svg%3E");
  mask-size:26px 10px;mask-repeat:repeat-x;
  transform:scaleY(.5);transform-origin:50% 50%;animation:wavephase 1.15s linear infinite;
  transition:width .7s var(--spring-soft),transform .5s var(--spring-soft),color .3s}
.prog>span.warn{color:#e8a020;transform:scaleY(.78)}
.prog>span.crit{color:var(--error);transform:scaleY(1.05);animation-duration:.6s}
@keyframes wavephase{to{-webkit-mask-position:-26px 0;mask-position:-26px 0}}
.mfoot{font-size:11.5px;color:var(--on-surface-var);margin-top:7px;min-height:15px;font-variant-numeric:tabular-nums}
.mna .prog{visibility:hidden}

/* ---------- ops ---------- */
.opscard{margin-top:14px}
.ophead{display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap}
.opsbtns{display:flex;gap:10px;flex-wrap:wrap}
.opsrow{display:flex;align-items:center;gap:16px;margin-top:16px;flex-wrap:wrap}
.phasewrap{display:flex;align-items:center;gap:10px;min-width:0;flex:1}
.phase{font-size:15px;font-weight:650;letter-spacing:.01em;white-space:nowrap}
.phase.ok{color:#1d7a2c}
.phase.bad{color:var(--error)}
.dots{display:none;gap:4px;align-items:center}
.dots.on{display:inline-flex}
.dots i{width:7px;height:7px;border-radius:99px;background:var(--primary);animation:dotb 1.05s var(--spring) infinite}
.dots i:nth-child(2){animation-delay:.13s}
.dots i:nth-child(3){animation-delay:.26s}
@keyframes dotb{0%,100%{transform:translateY(0) scale(.72);opacity:.45}40%{transform:translateY(-8px) scale(1.22);opacity:1}}
.omsg{font-size:12.5px;color:var(--on-surface-var);word-break:break-all}
.omsg.err{color:var(--error)}
.opprog{flex:0 0 220px;height:10px;border-radius:99px;background:var(--sc-highest);overflow:hidden;display:none}
.opprog.live{display:block}
.opprog>span{display:block;height:100%;width:36%;border-radius:99px;background:var(--primary);color:var(--primary);
  -webkit-mask-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='26' height='10' viewBox='0 0 26 10'%3E%3Cpath d='M0 5 Q6.5 .4 13 5 T26 5' fill='none' stroke='%23fff' stroke-width='2.8' stroke-linecap='round'/%3E%3C/svg%3E");
  -webkit-mask-size:26px 10px;-webkit-mask-repeat:repeat-x;
  mask-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='26' height='10' viewBox='0 0 26 10'%3E%3Cpath d='M0 5 Q6.5 .4 13 5 T26 5' fill='none' stroke='%23fff' stroke-width='2.8' stroke-linecap='round'/%3E%3C/svg%3E");
  mask-size:26px 10px;mask-repeat:repeat-x;
  animation:slide 1.5s var(--emph) infinite}
@keyframes slide{0%{transform:translateX(-110%) scaleY(.6)}45%{transform:translateX(115%) scaleY(1)}100%{transform:translateX(340%) scaleY(.6)}}

/* ---------- mods ---------- */
.modscard{margin-top:14px}
.modhead{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.modtools{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.field{background:var(--sc);border:1px solid transparent;border-radius:14px;padding:9px 14px;font-size:13.5px;
  color:var(--on-surface);min-width:160px;transition:border-color .2s,background-color .2s}
.field:focus{outline:none;border-color:var(--primary);background:var(--surface)}
.field::placeholder{color:var(--outline)}
.dbanner{display:none;align-items:center;gap:12px;flex-wrap:wrap;margin-top:14px;border-radius:18px;
  background:var(--error-container);color:var(--on-error-container);padding:12px 16px;font-size:13.5px;font-weight:600}
.dbanner.show{display:flex}
.mlist{margin-top:14px;border-radius:20px;background:var(--surface);max-height:380px;overflow-y:auto}
.mitem{display:grid;grid-template-columns:26px minmax(0,1fr) auto auto;gap:12px;align-items:center;
  padding:11px 16px;border-bottom:1px solid var(--sc)}
.mitem:last-child{border-bottom:none}
.mitem .st{width:11px;height:11px;border-radius:99px;background:#1d7a2c}
.mitem .st{transition:transform .4s var(--spring)}
.mitem:hover .st{transform:scale(1.35)}
.mitem{transition:background-color .2s}
.mitem:hover{background:var(--sc)}
.mitem.off .st{background:var(--outline-var)}
.mname{font-size:14px;font-weight:550;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mitem.off .mname{color:var(--on-surface-var);text-decoration:line-through}
.mmeta{font-size:12px;color:var(--on-surface-var);font-variant-numeric:tabular-nums;white-space:nowrap}
.mops{display:flex;gap:4px}
.mempty{padding:22px 16px;font-size:13.5px;color:var(--on-surface-var)}

/* ---------- log console ---------- */
.logcard{margin-top:14px;background:var(--sc-low)}
.loghead{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.logtools{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
select.field{min-width:150px;padding-right:30px;appearance:none;cursor:pointer;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2346464f' stroke-width='2.4' stroke-linecap='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 10px center}
.sw{display:inline-flex;align-items:center;gap:9px;font-size:13.5px;font-weight:600;cursor:pointer;user-select:none}
.sw input{position:absolute;opacity:0;width:0;height:0}
.sw .track{width:44px;height:26px;border-radius:99px;background:var(--sc-highest);border:2px solid var(--outline-var);
  position:relative;transition:background-color .25s var(--emph),border-color .25s var(--emph)}
.sw .thumb{position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:99px;background:var(--outline);
  transition:all .25s var(--emph)}
.sw input:checked+.track{background:var(--primary);border-color:var(--primary)}
.sw input:checked+.track .thumb{left:21px;width:20px;height:20px;background:var(--on-primary);top:1px}
.sw input:focus-visible+.track{outline:3px solid var(--primary);outline-offset:2px}
.iconbtn{display:inline-grid;place-items:center;width:40px;height:40px;border-radius:14px;cursor:pointer;
  color:var(--on-surface-var);border:none;background:transparent;transition:background-color .2s,color .2s;text-decoration:none}
.iconbtn:hover{background:var(--sc-high);color:var(--on-surface)}
.iconbtn svg{width:20px;height:20px}
.term{margin-top:14px;background:var(--term-bg);color:var(--term-fg);border-radius:20px;
  padding:16px 18px;height:380px;overflow-y:auto;font-family:"Cascadia Code","Cascadia Mono",Consolas,monospace;
  font-size:12px;line-height:1.6;white-space:pre-wrap;word-break:break-all}
.term::-webkit-scrollbar{width:10px}
.term::-webkit-scrollbar-thumb{background:#33333e;border-radius:99px}
.term .ts{color:var(--term-dim)}
.term .w{color:var(--term-warn)}
.term .e{color:var(--term-err)}
.term .o{color:var(--term-ok)}
.term .empty{color:var(--term-dim)}
.logmeta{display:flex;align-items:center;gap:12px;margin-top:10px;font-size:12px;color:var(--on-surface-var);flex-wrap:wrap}
#jumpNew{display:none;cursor:pointer}
#jumpNew.show{display:inline-flex}

/* ---------- snackbar ---------- */
#snackbar{position:fixed;left:50%;bottom:26px;transform:translate(-50%,140%) scale(.9);z-index:200;
  background:var(--on-surface);color:var(--surface);border-radius:16px;padding:13px 20px;font-size:13.5px;
  box-shadow:var(--shadow);max-width:min(640px,90vw);
  transition:transform .45s var(--spring),opacity .3s;opacity:0}
#snackbar.show{transform:translate(-50%,0) scale(1);opacity:1}
#snackbar.err{background:var(--error);color:var(--on-error)}

/* ---------- expressive motion: staggered entrance + pop ---------- */
.pop{animation:pop .55s var(--spring)}
@keyframes pop{0%{transform:scale(1)}40%{transform:scale(1.07)}100%{transform:scale(1)}}
.hero>*{animation:enter .7s var(--spring) backwards}
.hero>*:nth-child(1){animation-delay:.02s}
.hero>*:nth-child(2){animation-delay:.1s}
.hero>*:nth-child(3){animation-delay:.18s}
.mgrid>*{animation:enter .7s var(--spring) backwards}
.mgrid>*:nth-child(1){animation-delay:.2s}
.mgrid>*:nth-child(2){animation-delay:.25s}
.mgrid>*:nth-child(3){animation-delay:.3s}
.mgrid>*:nth-child(4){animation-delay:.35s}
.mgrid>*:nth-child(5){animation-delay:.4s}
.mgrid>*:nth-child(6){animation-delay:.45s}
.opscard{animation:enter .7s var(--spring) .5s backwards}
.modscard{animation:enter .7s var(--spring) .56s backwards}
.logcard{animation:enter .7s var(--spring) .62s backwards}
@keyframes enter{from{opacity:0;transform:translateY(24px) scale(.97)}}

@media (prefers-reduced-motion: reduce){
  *,*::before,*::after{animation-duration:.001s !important;animation-iteration-count:1 !important;transition-duration:.001s !important}
}

footer{margin-top:26px;font-size:12px;color:var(--on-surface-var);display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap}

@media (max-width:1150px){.mgrid{grid-template-columns:repeat(3,1fr)}.hero{grid-template-columns:1fr 1fr}.quick-card{grid-column:1/-1}}
@media (max-width:700px){.mgrid{grid-template-columns:repeat(2,1fr)}.hero{grid-template-columns:1fr}.mitem{grid-template-columns:20px minmax(0,1fr) auto}.mmeta,.mitem .mops .mmeta{display:none}.mitem .mmeta{display:none}}
</style>
</head>
<body>
<header class="appbar wrap" style="padding-bottom:14px">
  <div class="brand">
    <span class="logo" aria-hidden="true"><svg width="24" height="24" viewBox="0 0 32 32" fill="none"><path d="M8 21V11l5 5 3-6 3 6 5-5v10" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
    <div>
      <h1>MC Node Console</h1>
      <div class="sub">ST-LAPTOP · NeoForge 1.21.1 · superflat · :25565</div>
    </div>
  </div>
  <div class="abar-right">
    <span class="chip" id="stateChip"><span class="dot"></span><span id="stateChipTxt">リンク中</span></span>
    <span class="chip plain" id="clock">--:--:--</span>
  </div>
</header>

<main class="wrap" id="main">
  <section class="hero">
    <article class="card status-card" id="statusCard">
      <div class="blob" aria-hidden="true"></div>
      <div class="lbl">サーバー状態</div>
      <div class="display" id="heroState">接続中</div>
      <div class="sub" id="heroSub">テレメトリ取得中…</div>
    </article>
    <article class="card tps-card" style="position:relative;overflow:hidden">
      <span class="ring" id="tpsRing" aria-hidden="true"></span>
      <div class="lbl">Tick rate</div>
      <div class="display" id="tpsHero">--<small>/20 TPS</small></div>
      <div class="sub" id="tpsFoot">HwTab mod なし</div>
    </article>
    <article class="card quick-card">
      <div class="qrow"><span>サーバー稼働</span><b id="mcUptime">--</b></div>
      <div class="qrow"><span>システム稼働</span><b id="uptime">--</b></div>
      <div class="qrow"><span>ディスク C: 空き</span><b id="disk">--</b></div>
      <div class="qrow"><span>Mods 読込済</span><b id="stripMods">--</b></div>
    </article>
  </section>

  <section class="mgrid" aria-label="metrics">
    <article class="card mcard mna" id="t-mspt"><div class="lbl">MSPT</div><div class="mval na" id="mspt">n/a</div><div class="prog"><span id="msptBar"></span></div><div class="mfoot">上限 50ms</div></article>
    <article class="card mcard mna" id="t-players"><div class="lbl">Sessions</div><div class="mval na" id="players">n/a</div><div class="prog"><span style="width:0%"></span></div><div class="mfoot" id="playersFoot">データなし</div></article>
    <article class="card mcard mna" id="t-heap"><div class="lbl">JVM Heap</div><div class="mval na" id="heap">n/a</div><div class="prog"><span id="heapBar"></span></div><div class="mfoot" id="heapFoot">HwTab なし</div></article>
    <article class="card mcard" id="t-cpu"><div class="lbl">CPU</div><div class="mval" id="cpu">--<small>%</small></div><div class="prog"><span id="cpuBar"></span></div><div class="mfoot" id="cpuFoot">閾値 85%</div></article>
    <article class="card mcard" id="t-ram"><div class="lbl">System memory</div><div class="mval" id="ram">--<small>GB</small></div><div class="prog"><span id="ramBar"></span></div><div class="mfoot" id="ramFoot">used / total</div></article>
    <article class="card mcard mna" id="t-temp"><div class="lbl">Package temp</div><div class="mval na" id="temp">n/a</div><div class="prog"><span style="width:0%"></span></div><div class="mfoot">センサー遮断中 (VBS)</div></article>
  </section>

  <section class="card opscard">
    <div class="ophead">
      <h2>電源操作</h2>
      <div class="opsbtns">
        <button class="btn dangert" id="btnRestart">再起動</button>
        <button class="btn dangert" id="btnStop">停止</button>
        <button class="btn filled" id="btnStart">起動</button>
      </div>
    </div>
      <div class="opsrow">
      <div class="opprog" id="opProg"><span></span></div>
      <div class="phasewrap">
        <span class="phase" id="opsPhase">アイドル</span>
        <span class="dots" id="opsDots" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="omsg" id="opsMsg">実行中の操作はありません</span>
      </div>
    </div>
  </section>

  <section class="card modscard">
    <div class="modhead">
      <h2>Mods <span class="chip plain" id="modCount">--</span></h2>
      <div class="modtools">
        <input class="field" id="modFilter" placeholder="フィルタ" autocomplete="off">
        <button class="btn text" id="btnRescan">再スキャン</button>
        <button class="fab" id="btnUpload"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5m-6 6 6-6 6 6"/></svg>UPLOAD .JAR</button>
        <input type="file" id="modFile" accept=".jar" multiple style="display:none">
      </div>
    </div>
    <div class="dbanner" id="dirtyBanner">mods フォルダに変更があります — 適用には再起動が必要です
      <button class="btn dangert" id="btnDirtyRestart" style="padding:8px 16px;font-size:13px">今すぐ再起動</button>
    </div>
    <div class="mlist" id="modsBody"><div class="mempty">スキャン中…</div></div>
  </section>

  <section class="card logcard">
    <div class="loghead">
      <h2>コンソールログ</h2>
      <div class="logtools">
        <select class="field" id="logSel" aria-label="ログファイル"></select>
        <input class="field" id="logSearch" placeholder="検索" autocomplete="off" style="min-width:130px">
        <button class="chip tog on" data-lv="INFO">INFO</button>
        <button class="chip tog on" data-lv="WARN">WARN</button>
        <button class="chip tog on" data-lv="ERROR">ERROR</button>
        <label class="sw"><input type="checkbox" id="logLive" checked><span class="track"><span class="thumb"></span></span>ライブ</label>
        <a class="iconbtn" id="logDl" title="ログをダウンロード" download><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m-5-5 5 5 5-5M4 21h16"/></svg></a>
      </div>
    </div>
    <pre class="term" id="term"><span class="empty">接続中…</span></pre>
    <div class="logmeta">
      <span id="logMeta">--</span>
      <button class="chip tog" id="jumpNew">新着行あり — 追従する</button>
    </div>
  </section>

  <footer>
    <span>MC Node Console · unit D-01 · rev 3.1.0</span>
    <span>HTTP :8787 · zero dependency · LAN only</span>
    <span>built for ST-LAPTOP · 192.168.1.14</span>
  </footer>
</main>
<div id="snackbar" role="status"></div>

<script>
const $ = id => document.getElementById(id);
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
const escAttr = s => esc(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const fmt = (v,d) => (v===null||v===undefined||isNaN(v)) ? null : Number(v).toFixed(d===undefined?1:d);
const setMeter = (el,pct,cls) => { el.style.width = Math.max(0,Math.min(100,pct||0))+'%'; el.className = cls||''; };
const pop = id => { const el=$(id); el.classList.remove('pop'); void el.offsetWidth; el.classList.add('pop'); };
const ringPulse = () => { const r=$('tpsRing'); r.classList.remove('pulse'); void r.offsetWidth; r.classList.add('pulse'); };
let lastTpsInt=null, lastChipTxt='';
const okTile = id => { const t=$(id); t.classList.remove('mna','na'); };
const naTile = id => { const t=$(id); t.classList.add('mna'); t.dataset.state=''; };
const stTile = (id,st) => { $(id).dataset.state = (st&&st!=='ok')?st:''; };
const stateOf = (v,warn,crit) => { if(v===null||v===undefined||isNaN(v))return null; return v>=crit?'crit':(v>=warn?'warn':'ok'); };
setInterval(()=>{ $('clock').textContent = new Date().toLocaleTimeString('ja-JP',{hour12:false}); },1000);

let snackTimer=null;
function toast(msg, err){
  const el=$('snackbar');
  el.textContent=msg;
  el.className=err?'err show':'show';
  clearTimeout(snackTimer);
  snackTimer=setTimeout(()=>{ el.className=''; },4200);
}

/* ---------- helpers ---------- */
const BUSY = ['initiating','stopping','starting','waiting'];
let actionBusy = false;
let serverRunning = false;

function renderLog(lines, el){
  if(!lines||!lines.length){ el.innerHTML='<span class="empty">ログなし</span>'; return; }
  el.innerHTML = lines.map(l=>{
    const e = esc(l);
    const m = e.match(/^(\[[^\]]*\/(INFO|WARN|ERROR|FATAL)\]\s*)/);
    const head = m?('<span class="ts">'+m[1]+'</span>'):'';
    const body = m?e.slice(m[1].length):e;
    if(/ERROR|FATAL|Exception/.test(body)) return head+'<span class="e">'+body+'</span>';
    if(/WARN/.test(body)) return head+'<span class="w">'+body+'</span>';
    return head+body;
  }).join('\n');
}

/* ---------- power ---------- */
const armTimers = {};
function armButton(btn, fn){
  if(btn.classList.contains('armed')){ btn.classList.remove('armed'); btn.textContent = btn.dataset.label; clearTimeout(armTimers[btn.id]); fn(); return; }
  btn.dataset.label = btn.textContent;
  btn.classList.add('armed'); btn.textContent = '本当に実行？';
  btn.classList.remove('pop'); void btn.offsetWidth; btn.classList.add('pop');
  armTimers[btn.id] = setTimeout(()=>{ btn.classList.remove('armed'); btn.textContent = btn.dataset.label; }, 3500);
}
async function doAction(mode){
  try{
    const r = await fetch('/api/action/'+mode, {method:'POST'});
    const d = await r.json();
    if(d.ok){ opsMsg(mode==='restart'?'再起動を指示しました — 監視中…':(mode==='stop'?'停止を指示しました — 監視中…':'起動を指示しました — 監視中…'), ''); }
    else toast('拒否されました: '+(d.err||'理由不明'), true);
  }catch(e){ toast('操作リクエストに失敗しました', true); }
}
$('btnRestart').addEventListener('click', function(){ armButton(this, ()=>doAction('restart')); });
$('btnStop').addEventListener('click', function(){ armButton(this, ()=>doAction('stop')); });
$('btnStart').addEventListener('click', ()=>doAction('start'));
$('btnDirtyRestart').addEventListener('click', ()=>doAction('restart'));
function opsMsg(text, cls){
  const el=$('opsMsg');
  el.textContent=text;
  el.className='omsg'+(cls?' '+cls:'');
}

/* ---------- mods ---------- */
let MODS = [];
async function loadMods(){
  try{
    const r = await fetch('/api/mods',{cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    const d = await r.json();
    MODS = d.mods||[];
    $('modCount').textContent = (d.active||0)+' ON / '+(d.disabled||0)+' OFF';
    $('dirtyBanner').className = 'dbanner' + (d.dirty?' show':'');
    renderMods();
  }catch(e){ $('modsBody').innerHTML = '<div class="mempty">mod 一覧を取得できませんでした</div>'; }
}
function renderMods(){
  const q = ($('modFilter').value||'').toLowerCase();
  const rows = MODS.filter(m=>m.name.toLowerCase().includes(q));
  if(!rows.length){ $('modsBody').innerHTML = '<div class="mempty">該当なし</div>'; return; }
  $('modsBody').innerHTML = rows.map(m=>{
    const dt = new Date(m.mtime*1000);
    const p2 = n => String(n).padStart(2,'0');
    const mm = dt.getFullYear()+'/'+p2(dt.getMonth()+1)+'/'+p2(dt.getDate())+' '+p2(dt.getHours())+':'+p2(dt.getMinutes());
    return '<div class="mitem'+(m.enabled?'':' off')+'">'
      +'<span class="st" aria-hidden="true"></span>'
      +'<span class="mname" title="'+escAttr(m.name)+'">'+esc(m.name)+'</span>'
      +'<span class="mmeta">'+m.sizeKB+'KB · '+mm+' · '+(m.enabled?'ON':'OFF')+'</span>'
      +'<span class="mops">'
      +'<button class="btn text" data-a="toggle" data-n="'+escAttr(m.name)+'" style="font-size:13px">'+(m.enabled?'無効化':'有効化')+'</button>'
      +'<button class="btn text danger" data-a="delete" data-n="'+escAttr(m.name)+'" style="font-size:13px">削除</button>'
      +'</span></div>';
  }).join('');
}
$('modFilter').addEventListener('input', renderMods);
$('btnRescan').addEventListener('click', loadMods);
$('modsBody').addEventListener('click', async ev=>{
  const b = ev.target.closest('button[data-a]');
  if(!b) return;
  const name = b.getAttribute('data-n'), act = b.getAttribute('data-a');
  if(act==='delete'){
    if(!b.classList.contains('armed')){ b.dataset.label=b.textContent; b.classList.add('armed'); b.textContent='本当に?';
      setTimeout(()=>{ b.classList.remove('armed'); b.textContent=b.dataset.label; },3000); return; }
  }
  b.disabled = true;
  try{
    const r = await fetch('/api/mods/'+act, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:name})});
    const d = await r.json().catch(()=>({ok:false,err:'HTTP '+r.status}));
    if(!d.ok) toast('mod 操作失敗: '+(d.err||'?'), true); else toast('mod '+(act==='toggle'?(MODS.find(x=>x.name===name)?.enabled?'無効化':'有効化'):'削除')+'しました: '+name, false);
  }catch(e){ toast('リクエスト失敗: '+e, true); }
  loadMods();
});
$('btnUpload').addEventListener('click', ()=>$('modFile').click());
$('modFile').addEventListener('change', ()=>uploadFiles([...$('modFile').files]));
const mlist = $('modsBody');
mlist.addEventListener('dragover', e=>{ e.preventDefault(); });
mlist.addEventListener('drop', e=>{ e.preventDefault(); uploadFiles([...e.dataTransfer.files]); });
async function uploadFiles(files){
  const jars = files.filter(f=>/\.jar$/i.test(f.name));
  if(!jars.length){ toast('アップロード中止 — .jar のみ対応', true); return; }
  let okN = 0, failN = 0;
  for(const f of jars){
    toast('アップロード中: '+f.name+' ('+Math.round(f.size/1024)+'KB)');
    try{
      const r = await fetch('/api/mods/upload?name='+encodeURIComponent(f.name), {method:'POST',body:f});
      const d = await r.json();
      if(d.ok) okN++; else { failN++; toast('アップロード失敗: '+f.name+' — '+(d.err||'?'), true); }
    }catch(e){ failN++; toast('アップロード失敗: '+f.name, true); }
  }
  if(okN) toast('アップロード完了: '+okN+'件'+(failN?(' / 失敗'+failN+'件'):''), false);
  loadMods();
}

/* ---------- log console ---------- */
let logFile='latest.log', logOffset=0, logAuto=true, logNew=0;
let logBuf=[];
const lvOn = {INFO:true, WARN:true, ERROR:true};
async function loadLogList(){
  try{
    const r = await fetch('/api/logs',{cache:'no-store'});
    const d = await r.json();
    const sel = $('logSel');
    const cur = logFile;
    sel.innerHTML = (d.logs||[]).map(f=>'<option value="'+escAttr(f.name)+'">'+esc(f.name)+' ('+f.sizeKB+'KB)</option>').join('');
    if((d.logs||[]).some(f=>f.name===cur)){ sel.value = cur; }
  }catch(e){}
}
$('logSel').addEventListener('change', ()=>{ logFile = $('logSel').value || 'latest.log'; logOffset = 0; logBuf=[]; $('logDl').href='/api/log/download?file='+encodeURIComponent(logFile); pullLog(true); });
$('logSearch').addEventListener('input', renderTerm);
document.querySelectorAll('.chip.tog[data-lv]').forEach(c=>{
  c.addEventListener('click', ()=>{
    const lv = c.getAttribute('data-lv');
    lvOn[lv] = !lvOn[lv];
    c.classList.toggle('on', lvOn[lv]);
    renderTerm();
  });
});
$('logLive').addEventListener('change', ()=>{
  logAuto = $('logLive').checked;
  if(logAuto){ logNew=0; $('jumpNew').classList.remove('show'); renderTerm(); scrollTerm(); }
});
$('jumpNew').addEventListener('click', ()=>{ $('logLive').checked = true; logAuto = true; logNew = 0; $('jumpNew').classList.remove('show'); renderTerm(); scrollTerm(); });
function levelOf(line){
  const m = line.match(/\/(INFO|WARN|ERROR|FATAL)\]/);
  if(!m) return 'INFO';
  return m[1]==='FATAL' ? 'ERROR' : m[1];
}
function visibleLines(){
  const q = ($('logSearch').value||'').toLowerCase();
  return logBuf.filter(l=>{
    const lv = levelOf(l);
    if(lv==='WARN' && !lvOn.WARN) return false;
    if(lv==='ERROR' && !lvOn.ERROR) return false;
    if(lv==='INFO' && !lvOn.INFO) return false;
    if(q && !l.toLowerCase().includes(q)) return false;
    return true;
  });
}
function renderTerm(){
  const el = $('term');
  const lines = visibleLines();
  if(!lines.length){ el.innerHTML='<span class="empty">(表示行なし — フィルタ/検索を確認)</span>'; return; }
  renderLog(lines, el);
}
function scrollTerm(){
  const el = $('term');
  el.scrollTop = el.scrollHeight;
}
async function pullLog(force){
  try{
    const url = '/api/log?file='+encodeURIComponent(logFile)+(logOffset>0 ? ('&offset='+logOffset) : '&lines=600');
    const r = await fetch(url, {cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    const d = await r.json();
    if(d.offset < logOffset){ logOffset = 0; return pullLog(true); }
    if(!logOffset || force || d.reset){
      logBuf = d.lines||[];
    } else if((d.lines||[]).length){
      logBuf = logBuf.concat(d.lines);
      if(logBuf.length > 2400){ logBuf = logBuf.slice(logBuf.length-2400); }
    }
    logOffset = d.offset;
    if(!logAuto && (d.lines||[]).length){
      logNew += d.lines.length;
      const jb = $('jumpNew');
      jb.textContent = '新着 '+logNew+' 行 — 追従する';
      jb.classList.add('show');
    }
    if(logAuto){ renderTerm(); scrollTerm(); }
    $('logMeta').textContent = logFile+' · '+(d.size===undefined?'--':Math.round(d.size/1024)+'KB')+(d.truncated?' · 末尾表示':'');
  }catch(e){
    $('logMeta').textContent = 'ログ取得失敗 — リトライ中…';
  }
}
$('logDl').href = '/api/log/download?file=latest.log';
loadLogList();

/* ---------- tick ---------- */
async function tick(){
  let s;
  try{
    const r = await fetch('/api/stats',{cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    s = await r.json();
  }catch(e){
    $('heroState').textContent='接続なし'; $('statusCard').className='card status-card crit';
    $('heroSub').innerHTML='テレメトリ喪失 — 再試行中…';
    $('stateChip').className='chip bad'; $('stateChipTxt').textContent='OFFLINE';
    return;
  }
  const n=s.node||{}, mc=s.mc||{};
  serverRunning = mc.state==='Running';
  let worst = serverRunning ? 'ok' : 'crit';

  const cpu=n.cpu;
  if(cpu===null||cpu===undefined){ $('cpu').innerHTML='n/a'; $('cpuFoot').textContent='データなし'; naTile('t-cpu'); setMeter($('cpuBar'),0,''); }
  else{
    okTile('t-cpu');
    const st=stateOf(cpu,85,95)||'ok';
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('cpu').innerHTML=fmt(cpu,0)+'<small>%</small>';
    $('cpuFoot').textContent='負荷 '+fmt(cpu,0)+'% / 閾値 85%';
    stTile('t-cpu',st); setMeter($('cpuBar'),cpu,st);
  }

  if(n.ramUsed===null||n.ramUsed===undefined||!n.ramTotal){ $('ram').innerHTML='n/a'; $('ramFoot').textContent='データなし'; naTile('t-ram'); setMeter($('ramBar'),0,''); }
  else{
    okTile('t-ram');
    const p=n.ramUsed/n.ramTotal*100, st=stateOf(p,90,97)||'ok';
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('ram').innerHTML=fmt(n.ramUsed)+'<small>GB</small>';
    $('ramFoot').textContent=fmt(n.ramUsed)+' / '+fmt(n.ramTotal,0)+' GB · '+Math.round(p)+'%';
    stTile('t-ram',st); setMeter($('ramBar'),p,st);
  }

  if(mc.heapUsed===null||mc.heapUsed===undefined||!mc.heapMax){ $('heap').innerHTML='n/a'; $('heapFoot').textContent='HwTab なし'; naTile('t-heap'); setMeter($('heapBar'),0,''); }
  else{
    okTile('t-heap');
    const p=mc.heapUsed/mc.heapMax*100, st=stateOf(p,85,95)||'ok';
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('heap').innerHTML=fmt(mc.heapUsed)+'<small>GB</small>';
    $('heapFoot').textContent=fmt(mc.heapUsed)+' / '+fmt(mc.heapMax,0)+' GB · '+Math.round(p)+'%';
    stTile('t-heap',st); setMeter($('heapBar'),p,st);
  }

  const ms=mc.mspt;
  if(ms===null||ms===undefined){ $('mspt').innerHTML='n/a'; naTile('t-mspt'); setMeter($('msptBar'),0,''); }
  else{
    okTile('t-mspt');
    const st=ms>50?'crit':(ms>30?'warn':'ok');
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('mspt').innerHTML=fmt(ms)+'<small>ms</small>';
    stTile('t-mspt',st); setMeter($('msptBar'),Math.min(100,ms/50*100),st);
  }

  if(mc.players===null||mc.players===undefined){ $('players').innerHTML='n/a'; $('playersFoot').textContent='データなし'; naTile('t-players'); }
  else{ okTile('t-players'); $('players').innerHTML=mc.players+'<small>人</small>'; $('playersFoot').textContent=mc.players>0?'プレイ中':'待機中'; }

  if(n.tempC===null||n.tempC===undefined){ $('temp').innerHTML='n/a'; naTile('t-temp'); }
  else{ okTile('t-temp'); $('temp').innerHTML=fmt(n.tempC,0)+'<small>°C</small>'; }

  const tps=mc.tps;
  if(tps===null||tps===undefined){ $('tpsHero').innerHTML='--<small>/20 TPS</small>'; $('tpsFoot').textContent='HwTab mod なし'; }
  else{
    const st=tps<10?'crit':(tps<15?'warn':'ok');
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('tpsHero').innerHTML=fmt(tps)+'<small>/20 TPS</small>';
    $('tpsFoot').textContent=tps>=19.9?'フルレート':'tick 低下';
    ringPulse();
    if(lastTpsInt!==null && Math.abs(Math.round(tps)-lastTpsInt)>=1){ pop('tpsHero'); }
    lastTpsInt=Math.round(tps);
  }

  const up = serverRunning;
  $('mcUptime').textContent = mc.uptimeText||'n/a';
  $('uptime').textContent = n.uptimeText||'n/a';
  $('disk').textContent = (n.diskFreeGB===null||n.diskFreeGB===undefined)?'n/a':fmt(n.diskFreeGB)+' GB';
  $('stripMods').textContent = (s.modsActive===undefined)?'--':(s.modsActive+' / '+(s.modsDisabled||0)+' OFF');

  /* action state */
  const a = s.action;
  actionBusy = !!(a && BUSY.indexOf(a.phase)>=0);
  const ph = $('opsPhase'), prog=$('opProg'), dots=$('opsDots');
  dots.className = 'dots' + (actionBusy?' on':'');
  if(a){
    const pmap = {initiating:'指示済み',stopping:'停止中…',starting:'起動中…',waiting:'起動待ち…',done:'完了',failed:'失敗'};
    ph.textContent = pmap[a.phase]||a.phase;
    ph.className = 'phase' + (actionBusy?' live':(a.phase==='done'?' ok':(a.phase==='failed'?' bad':'')));
    prog.className = 'opprog' + (actionBusy?' live':'');
    if(actionBusy){ opsMsg(a.msg||a.phase, ''); }
    else if($('opsMsg').textContent.indexOf('監視中')>=0 || $('opsMsg').textContent.indexOf('指示しました')>=0){
      opsMsg(a.msg||'', a.phase==='failed'?'err':'');
      if(a.phase==='done') toast('操作が完了しました', false);
      if(a.phase==='failed') toast('操作が失敗しました: '+(a.msg||''), true);
    }
  } else {
    ph.textContent='アイドル'; ph.className='phase'; prog.className='opprog';
    if($('opsMsg').textContent.indexOf('監視中')>=0 || $('opsMsg').textContent.indexOf('指示しました')>=0){ opsMsg('実行中の操作はありません',''); }
  }  $('btnRestart').disabled = actionBusy;
  $('btnStop').disabled = actionBusy || !up;
  $('btnStart').disabled = actionBusy || up;

  /* hero + chip */
  const hero=$('heroState'), sc=$('statusCard'), chip=$('stateChip'), chipT=$('stateChipTxt');
  const prevHero=hero.textContent;
  const stTxt = up ? 'RUNNING' : 'DOWN';
  if(actionBusy){
    const map = {initiating:'操作を予約',stopping:'停止中',starting:'起動中',waiting:'起動中'};
    hero.textContent = map[a.phase]||'操作中';
    sc.className='card status-card warn';
    $('heroSub').textContent = '管理操作を実行中 — '+(a.msg||a.phase);
    chip.className='chip warn'; chipT.textContent='OPERATING';
  } else if(worst==='crit'){
    hero.textContent='要対応'; sc.className='card status-card crit';
    $('heroSub').textContent = (up?'しきい値超過':'サーバー停止')+' — ポート 25565';
    chip.className='chip bad'; chipT.textContent=stTxt;
  } else if(worst==='warn'){
    hero.textContent='注意'; sc.className='card status-card warn';
    $('heroSub').textContent = 'しきい値イベント — 状態 '+stTxt;
    chip.className='chip warn'; chipT.textContent=stTxt;
  } else {
    hero.textContent='正常稼働'; sc.className='card status-card ok';
    $('heroSub').textContent = 'server thread · port 25565 · 3秒ごと更新';
    chip.className='chip ok'; chipT.textContent=stTxt;
  }

  if(hero.textContent!==prevHero){ pop('heroState'); }
  if(chipT.textContent!==lastChipTxt){ pop('stateChip'); lastChipTxt=chipT.textContent; }

  $('dirtyBanner').className = 'dbanner' + (s.modsDirty?' show':'');
}
tick();
setInterval(tick,3000);
loadMods();
setInterval(loadMods,20000);
setInterval(()=>pullLog(false),2000);
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

function Send-Json($ctx, [int]$status, [string]$json) {
    $res = $ctx.Response
    try {
        $res.StatusCode = $status
        $body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = 'application/json; charset=utf-8'
        $res.ContentLength64 = $body.Length
        $res.OutputStream.Write($body, 0, $body.Length)
    } catch { }
}

function Read-BodyText($ctx) {
    try {
        $len = $ctx.Request.ContentLength64
        if ($len -le 0 -or $len -gt 1MB) { return '' }
        $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } catch { return '' }
}

function Get-QParam($ctx, [string]$key) {
    try {
        $q = $ctx.Request.Url.Query
        if ($q.StartsWith('?')) { $q = $q.Substring(1) }
        foreach ($pair in ($q -split '&')) {
            $kv = $pair -split '=', 2
            if ($kv[0] -eq $key -and $kv.Count -gt 1) { return [System.Uri]::UnescapeDataString($kv[1]) }
        }
    } catch { }
    return $null
}

function Get-SafeModName([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $name = [System.IO.Path]::GetFileName($raw.Trim())
    if ($name -match '[\\/]') { return $null }
    if ($name -match '^[A-Za-z0-9._()\[\]+ -]+\.jar(\.disabled)?$') { return $name }
    return $null
}

function Get-SafeLogName([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'latest.log' }
    $name = [System.IO.Path]::GetFileName($raw.Trim())
    if ($name -match '^[A-Za-z0-9._\-]+\.log$') { return $name }
    return $null
}

function Get-ActionState {
    try {
        if (-not (Test-Path $actionStateFile)) { return $null }
        $raw = [System.IO.File]::ReadAllText($actionStateFile)
        if ($raw -notmatch '"epoch":(\d+)') { return $null }
        $e = [long]$Matches[1]
        $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($now - $e -gt 900) { return $null }
        if ($raw -match '"phase":"(initiating|stopping|starting|waiting)"') {
            if ($raw -match '"pid":(\d+)') {
                $apid = [int]$Matches[1]
                if ($apid -gt 0 -and -not (Get-Process -Id $apid -ErrorAction SilentlyContinue)) { return $null }
            }
        }
        return $raw.Trim()
    } catch { return $null }
}

function Get-ModsJson {
    $javaStart = $null
    try {
        $j0 = Get-Process java -ErrorAction Stop | Sort-Object StartTime -ErrorAction Stop | Select-Object -First 1
        $javaStart = $j0.StartTime
    } catch { }
    $arr = New-Object System.Collections.Generic.List[string]
    $active = 0; $disabled = 0; $dirty = $false
    try {
        $files = @(Get-ChildItem $modsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.jar' -or $_.Name -like '*.jar.disabled' } | Sort-Object Name)
        foreach ($f in $files) {
            $en = -not ($f.Name -like '*.disabled')
            if ($en) { $active++ } else { $disabled++ }
            if ($en -and $null -ne $javaStart -and $f.LastWriteTime -gt $javaStart) { $dirty = $true }
            $epoch = [int][DateTimeOffset]::new($f.LastWriteTime.Ticks, [TimeSpan]::Zero).ToUnixTimeSeconds()
            $arr.Add('{"name":"' + (Esc-Json $f.Name) + '","sizeKB":' + [math]::Round($f.Length / 1KB, 0) + ',"mtime":' + $epoch + ',"enabled":' + $(if ($en) { 'true' } else { 'false' }) + '}')
        }
    } catch { }
    return '{"active":' + $active + ',"disabled":' + $disabled + ',"dirty":' + $(if ($dirty) { 'true' } else { 'false' }) + ',"mods":[' + ($arr -join ',') + ']}'
}

function Get-LogListJson {
    $arr = New-Object System.Collections.Generic.List[string]
    try {
        $files = @(Get-ChildItem $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($f in $files) {
            $epoch = [int][DateTimeOffset]::new($f.LastWriteTime.Ticks, [TimeSpan]::Zero).ToUnixTimeSeconds()
            $arr.Add('{"name":"' + (Esc-Json $f.Name) + '","sizeKB":' + [math]::Round($f.Length / 1KB, 0) + ',"mtime":' + $epoch + '}')
        }
    } catch { }
    return '{"logs":[' + ($arr -join ',') + ']}'
}

function Get-LogBodyJson($ctx) {
    $file = Get-SafeLogName (Get-QParam $ctx 'file')
    if (-not $file) { return @{ status = 400; json = '{"ok":false,"err":"INVALID FILE NAME"}' } }
    $p = Join-Path $logDir $file
    if (-not (Test-Path -LiteralPath $p)) { return @{ status = 404; json = '{"ok":false,"err":"FILE NOT FOUND"}' } }
    $fi = Get-Item -LiteralPath $p
    $offStr = Get-QParam $ctx 'offset'
    $linesStr = Get-QParam $ctx 'lines'
    $wantLines = 600
    if ($linesStr -match '^\d+$') { $wantLines = [Math]::Min(2000, [Math]::Max(50, [int]$linesStr)) }

    $linesArr = @()
    $newOffset = $fi.Length
    $offStrGiven = (($null -ne $offStr) -and $offStr -match '^\d+$')
    $reset = -not $offStrGiven

    if ($offStrGiven) {
        $off = [long]$offStr
        if ($off -gt $fi.Length) { $off = 0; $reset = $true }
        if ($off -eq $fi.Length) {
            return @{ status = 200; json = '{"ok":true,"file":"' + (Esc-Json $file) + '","offset":' + $off + ',"size":' + $fi.Length + ',"reset":false,"truncated":false,"lines":[]}' }
        }
        if (($fi.Length - $off) -gt 8MB) {
            $reset = $true
        } else {
            $fs = New-Object System.IO.FileStream($p, 'Open', 'Read', 'ReadWrite')
            try {
                $fs.Seek($off, 'Begin') | Out-Null
                $len = [int]($fi.Length - $off)
                $buf = New-Object byte[] $len
                $read = 0
                while ($read -lt $len) {
                    $n = $fs.Read($buf, $read, $len - $read)
                    if ($n -le 0) { break }
                    $read += $n
                }
                $newOffset = $off
                if ($read -gt 0) {
                    $cutEnd = $read
                    if ($buf[$read - 1] -ne [byte]10) {
                        $lastNl = -1
                        for ($i = $read - 1; $i -ge 0; $i--) { if ($buf[$i] -eq [byte]10) { $lastNl = $i; break } }
                        if ($lastNl -lt 0) { $cutEnd = 0 } else { $cutEnd = $lastNl + 1 }
                    }
                    if ($cutEnd -gt 0) {
                        $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $cutEnd)
                        $linesArr = @($txt -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
                        if ($linesArr.Count -gt 0 -and $linesArr[$linesArr.Count - 1] -eq '') { $linesArr = $linesArr[0..($linesArr.Count - 2)] }
                        $newOffset = $off + $cutEnd
                    }
                }
            } finally { $fs.Dispose() }
        }
    }

    if ($reset) {
        $linesArr = @(Get-Content -LiteralPath $p -Tail $wantLines -Encoding UTF8 -ErrorAction SilentlyContinue)
        $newOffset = $fi.Length
    }

    $linesJson = ($linesArr | ForEach-Object { '"' + (Esc-Json $_) + '"' }) -join ','
    return @{ status = 200; json = '{"ok":true,"file":"' + (Esc-Json $file) + '","offset":' + $newOffset + ',"size":' + $fi.Length + ',"reset":' + $(if ($reset) { 'true' } else { 'false' }) + ',"truncated":' + $(if ($reset) { 'true' } else { 'false' }) + ',"lines":[' + $linesJson + ']}' }
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
    $upText = $null
    try {
        $sysProc = Get-Process -Id 4 -ErrorAction Stop
        $upText = Format-Duration ((Get-Date) - $sysProc.StartTime)
    } catch { }
    $disk = $null
    try {
        $drv = New-Object System.IO.DriveInfo('C:')
        $disk = [math]::Round($drv.AvailableFreeSpace / 1GB, 1)
    } catch { }

    $state = 'Down'
    $mcUpText = $null
    $javaPid = $null
    $modsActive = 0; $modsOff = 0; $modsDirty = $false
    try {
        $javas = @(Get-Process java -ErrorAction SilentlyContinue)
        $listen = Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue
        $first = $javas | Sort-Object StartTime -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($first) { $javaPid = $first.Id }
        if ($javas.Count -gt 0 -and $listen) {
            $state = 'Running'
            if ($first) { $mcUpText = Format-Duration ((Get-Date) - $first.StartTime) }
        }
        if ($first) {
            $files = @(Get-ChildItem $modsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.jar' })
            foreach ($f in $files) { if ($f.LastWriteTime -gt $first.StartTime) { $modsDirty = $true; break } }
        }
        foreach ($f in @(Get-ChildItem $modsDir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -like '*.jar.disabled') { $modsOff++ } elseif ($f.Name -like '*.jar') { $modsActive++ }
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

    $actJson = Get-ActionState
    if ($null -eq $actJson) { $actJson = 'null' }

    $json = '{'
    $json += '"node":{"cpu":' + (InvNum $cpu) + ',"ramUsed":' + (InvNum $ramU) + ',"ramTotal":' + (InvNum $ramT) + ',"tempC":' + (InvNum $tempC) + ',"uptimeText":"' + (Esc-Json $upText) + '","diskFreeGB":' + (InvNum $disk) + '},'
    $json += '"mc":{"state":"' + $state + '","tps":' + (InvNum $tps) + ',"mspt":' + (InvNum $mspt) + ',"players":' + (InvNum $players) + ',"heapUsed":' + (InvNum $hU) + ',"heapMax":' + (InvNum $hM) + ',"uptimeText":"' + (Esc-Json $mcUpText) + '","pid":' + (InvNum $javaPid) + '},'
    $json += '"action":' + $actJson + ','
    $json += '"modsActive":' + $modsActive + ',"modsDisabled":' + $modsOff + ',"modsDirty":' + $(if ($modsDirty) { 'true' } else { 'false' }) + ','
    $json += '"logTail":[' + $logJson + ']}'
    return $json
}

$script:cacheJson = $null
$script:cacheAt = [datetime]::MinValue
function Get-SnapshotCached {
    $ageMs = ((Get-Date) - $script:cacheAt).TotalMilliseconds
    if ($null -eq $script:cacheJson -or $ageMs -ge 2000) {
        $script:cacheJson = Get-Snapshot
        $script:cacheAt = Get-Date
    }
    return $script:cacheJson
}

function Start-McAction([string]$mode) {
    $pi = New-Object System.Diagnostics.ProcessStartInfo
    $pi.FileName = 'powershell.exe'
    $pi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $actionScript + '" -Mode ' + $mode
    $pi.CreateNoWindow = $true
    $pi.UseShellExecute = $false
    return [System.Diagnostics.Process]::Start($pi)
}

$listener = $null
$failCount = 0
while ($true) {
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add('http://*:8787/')
        $listener.Start()
        $failCount = 0
        while ($listener.IsListening) {
            $ctx = $null
            try { $ctx = $listener.GetContext() } catch { break }
            $res = $ctx.Response
            try {
                $res.Headers.Add('Cache-Control', 'no-store')
                $path = $ctx.Request.Url.AbsolutePath
                $method = $ctx.Request.HttpMethod
                if ($method -eq 'GET' -and $path -eq '/api/stats') {
                    Send-Json $ctx 200 (Get-SnapshotCached)
                } elseif ($method -eq 'GET' -and $path -eq '/api/mods') {
                    Send-Json $ctx 200 (Get-ModsJson)
                } elseif ($method -eq 'GET' -and $path -eq '/api/logs') {
                    Send-Json $ctx 200 (Get-LogListJson)
                } elseif ($method -eq 'GET' -and $path -eq '/api/log') {
                    $lr = Get-LogBodyJson $ctx
                    Send-Json $ctx $lr.status $lr.json
                } elseif ($method -eq 'GET' -and $path -eq '/api/log/download') {
                    $file = Get-SafeLogName (Get-QParam $ctx 'file')
                    if (-not $file) {
                        Send-Json $ctx 400 '{"ok":false,"err":"INVALID FILE NAME"}'
                    } else {
                        $p = Join-Path $logDir $file
                        if (-not (Test-Path -LiteralPath $p)) {
                            Send-Json $ctx 404 '{"ok":false,"err":"FILE NOT FOUND"}'
                        } elseif ((Get-Item -LiteralPath $p).Length -gt 128MB) {
                            Send-Json $ctx 413 '{"ok":false,"err":"TOO LARGE (128MB MAX)"}'
                        } else {
                            try {
                                $bytes = [System.IO.File]::ReadAllBytes($p)
                                $res.StatusCode = 200
                                $res.ContentType = 'application/octet-stream'
                                $res.Headers.Add('Content-Disposition', 'attachment; filename="' + $file + '"')
                                $res.ContentLength64 = $bytes.Length
                                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                            } catch {
                                Send-Json $ctx 500 '{"ok":false,"err":"READ FAILED"}'
                            }
                        }
                    }
                } elseif ($method -eq 'POST' -and $path -match '^/api/action/(restart|stop|start)$') {
                    $mode = $Matches[1]
                    $act = Get-ActionState
                    $busy = $false
                    if ($act -and $act -match '"phase":"(initiating|stopping|starting|waiting)"') { $busy = $true }
                    if ($busy) {
                        Send-Json $ctx 409 '{"ok":false,"err":"ANOTHER OPERATION IS IN FLIGHT"}'
                    } else {
                        if ($mode -ne 'start') {
                            $sv = Read-KeyValueFile $statsFile
                            if ($sv.ContainsKey('players')) {
                                try {
                                    if ([int]$sv['players'] -gt 0) {
                                        Send-Json $ctx 409 '{"ok":false,"err":"PLAYERS ONLINE - NO FORCE PATH IN UI, WAIT"}'
                                        try { $res.Close() } catch { }
                                        continue
                                    }
                                } catch { }
                            }
                        }
                        Start-McAction $mode | Out-Null
                        Send-Json $ctx 200 '{"ok":true,"mode":"' + $mode + '"}'
                    }
                } elseif ($method -eq 'POST' -and $path -eq '/api/mods/toggle') {
                    $body = Read-BodyText $ctx
                    $name = $null
                    if ($body -match '"name"\s*:\s*"((?:[^"\\]|\\.)*)"') { $name = $Matches[1] -replace '\\"', '"' -replace '\\\\', '\' }
                    $safe = Get-SafeModName $name
                    if (-not $safe) {
                        Send-Json $ctx 400 '{"ok":false,"err":"INVALID MOD NAME"}'
                    } else {
                        if (-not (Test-Path -LiteralPath (Join-Path $modsDir $safe))) {
                            Send-Json $ctx 400 '{"ok":false,"err":"MOD FILE NOT FOUND"}'
                        } else {
                            try {
                                if ($safe -like '*.disabled') { $newName = $safe.Substring(0, $safe.Length - 9) } else { $newName = $safe + '.disabled' }
                                Rename-Item -LiteralPath (Join-Path $modsDir $safe) -NewName $newName -ErrorAction Stop
                                Send-Json $ctx 200 '{"ok":true,"name":"' + (Esc-Json $newName) + '"}'
                            } catch {
                                Send-Json $ctx 423 '{"ok":false,"err":"FILE LOCKED - STOP SERVER FIRST"}'
                            }
                        }
                    }
                } elseif ($method -eq 'POST' -and $path -eq '/api/mods/delete') {
                    $body = Read-BodyText $ctx
                    $name = $null
                    if ($body -match '"name"\s*:\s*"((?:[^"\\]|\\.)*)"') { $name = $Matches[1] -replace '\\"', '"' -replace '\\\\', '\' }
                    $safe = Get-SafeModName $name
                    if (-not $safe) {
                        Send-Json $ctx 400 '{"ok":false,"err":"INVALID MOD NAME"}'
                    } else {
                        if (-not (Test-Path -LiteralPath (Join-Path $modsDir $safe))) {
                            Send-Json $ctx 400 '{"ok":false,"err":"MOD FILE NOT FOUND"}'
                        } else {
                            try {
                                if (-not (Test-Path $trashDir)) { New-Item -ItemType Directory -Path $trashDir -Force | Out-Null }
                                $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
                                Move-Item -LiteralPath (Join-Path $modsDir $safe) -Destination (Join-Path $trashDir ($stamp + '-' + $safe)) -ErrorAction Stop
                                Send-Json $ctx 200 '{"ok":true}'
                            } catch {
                                Send-Json $ctx 423 '{"ok":false,"err":"FILE LOCKED - STOP SERVER FIRST"}'
                            }
                        }
                    }
                } elseif ($method -eq 'POST' -and $path -eq '/api/mods/upload') {
                    $rawName = Get-QParam $ctx 'name'
                    $safe = Get-SafeModName $rawName
                    if (-not $safe -or $safe -like '*.disabled') {
                        Send-Json $ctx 400 '{"ok":false,"err":"INVALID JAR NAME"}'
                    } elseif ($ctx.Request.ContentLength64 -gt 256MB) {
                        Send-Json $ctx 413 '{"ok":false,"err":"TOO LARGE (256MB MAX)"}'
                    } else {
                        try {
                            $ms = New-Object System.IO.MemoryStream
                            $ctx.Request.InputStream.CopyTo($ms)
                            [System.IO.File]::WriteAllBytes((Join-Path $modsDir $safe), $ms.ToArray())
                            Send-Json $ctx 200 '{"ok":true,"name":"' + (Esc-Json $safe) + '","bytes":' + $ms.Length + '}'
                        } catch {
                            Send-Json $ctx 423 '{"ok":false,"err":"WRITE FAILED - FILE LOCKED BY RUNNING SERVER?"}'
                        }
                    }
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
