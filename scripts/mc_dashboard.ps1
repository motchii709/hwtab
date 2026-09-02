# MC Node Dashboard - zero-dependency HttpListener dashboard + ops console.
#   GET  /                -> single-page tactical console (no CDN)
#   GET  /api/stats       -> JSON snapshot (node + mc + action + mods + log tail)
#   GET  /api/mods        -> mod inventory
#   POST /api/action/*    -> restart / stop / start (spawns mc_action.ps1 detached)
#   POST /api/mods/toggle -> enable/disable mod (.jar <-> .jar.disabled)
#   POST /api/mods/delete -> move mod to mods\_trash
#   POST /api/mods/upload -> raw octet-stream jar upload (?name=)
# Listens on http://*:8787/ (LAN only - scoped by firewall rule "MCServer Dashboard").
# Designed for scheduled task MCServer-Dashboard (SYSTEM / onstart / HIGHEST).
$ErrorActionPreference = 'Continue'
$mcDir = 'C:\Users\motch\MCServer'
$hwFile = Join-Path $mcDir 'hw_stats_hw.txt'
$statsFile = Join-Path $mcDir 'hw_stats.txt'
$logFile = Join-Path $mcDir 'logs\latest.log'
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
<title>ST-LAPTOP /// NODE TELEMETRY</title>
<style>
:root{
  --bg:#0a0a0a; --panel:#101010; --panel2:#0d0d0d; --line:#262626; --line2:#3a3a3a;
  --fg:#eaeaea; --mut:#8a8a8a; --dim:#4a4a4a;
  --red:#ff2a2a; --grn:#4af626;
  --mono:"Cascadia Code","Cascadia Mono",Consolas,"Courier New",monospace;
  --heavy:"Arial Black","Segoe UI Black","Helvetica Neue",Arial,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--fg);font-family:var(--mono);min-height:100vh;overflow-x:hidden}
body::after{content:"";position:fixed;inset:0;pointer-events:none;z-index:90;
  background:repeating-linear-gradient(0deg,rgba(255,255,255,.022) 0 1px,transparent 1px 3px)}
::selection{background:var(--red);color:#fff}
.wrap{max-width:1420px;margin:0 auto;min-height:100vh;display:flex;flex-direction:column}
.wrap>*{flex:0 0 auto}
.wrap>.lsec{flex:1 1 auto}

/* ---------- top bar ---------- */
.bar{display:flex;justify-content:space-between;align-items:center;gap:14px;flex-wrap:wrap;
  padding:7px 18px;border-bottom:2px solid var(--line);font-size:10px;letter-spacing:.14em;
  text-transform:uppercase;color:var(--mut)}
.bar b{color:var(--fg);font-weight:700}
.bar .r{display:flex;gap:22px}
.bar .r span::before{content:"+ ";color:var(--dim)}

/* ---------- hero ---------- */
.hero{display:grid;grid-template-columns:1fr auto;gap:10px 30px;align-items:end;
  padding:26px 18px 20px;border-bottom:2px solid var(--line);position:relative}
.micro{font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--mut)}
.micro b{color:var(--fg)}
h1{font-family:var(--heavy);font-weight:900;font-size:clamp(2.3rem,5.6vw,4.4rem);
  letter-spacing:-.035em;line-height:.92;text-transform:uppercase;margin:10px 0 8px;color:var(--fg)}
h1.warn{color:var(--fg)}
h1.crit{color:var(--red)}
.herosub{font-size:10.5px;letter-spacing:.12em;text-transform:uppercase;color:var(--mut)}
.herosub .ok{color:var(--grn)}
.herosub .bad{color:var(--red)}
.hright{text-align:right}
.hright .lbl{font-size:10px;letter-spacing:.18em;color:var(--mut);text-transform:uppercase;margin-bottom:2px}
.tpsnum{font-family:var(--mono);font-weight:700;font-size:clamp(3rem,7vw,5rem);line-height:.9;
  letter-spacing:-.04em;font-variant-numeric:tabular-nums}
.tpsnum small{font-size:.32em;color:var(--mut);font-weight:400;letter-spacing:.06em}
.tpsnum.crit{color:var(--red)}
.hazard{display:none;height:8px;background:repeating-linear-gradient(-45deg,var(--red) 0 12px,#0a0a0a 12px 24px)}
.hazard.on{display:block}
.hazard.stripes-only{display:block;background:repeating-linear-gradient(-45deg,#1c1c1c 0 12px,#0a0a0a 12px 24px)}

/* ---------- metric grid ---------- */
.gridlabel{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;padding:8px 18px 6px;font-size:10px;
  letter-spacing:.16em;text-transform:uppercase;color:var(--dim)}
.gridlabel b{color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(6,1fr);gap:1px;background:var(--line);
  border-top:1px solid var(--line);border-bottom:1px solid var(--line)}
.cell{background:var(--panel);padding:12px 14px 11px;min-height:118px;display:flex;flex-direction:column}
.cell .lbl{font-size:9.5px;letter-spacing:.16em;text-transform:uppercase;color:var(--mut)}
.cell .lbl i{font-style:normal;color:var(--dim)}
.cell .num{font-family:var(--mono);font-size:31px;font-weight:700;line-height:1;
  font-variant-numeric:tabular-nums;margin-top:auto;color:var(--fg);transition:color .3s}
.cell .num small{font-size:.36em;font-weight:400;color:var(--mut);letter-spacing:.04em}
.cell[data-state="warn"] .num{color:var(--red);opacity:.62}
.cell[data-state="crit"] .num{color:var(--red)}
.cell.na .num{color:var(--dim);font-size:20px;letter-spacing:.06em}
.meter{height:4px;background:#1b1b1b;margin-top:9px;position:relative}
.meter>span{position:absolute;inset:0 auto 0 0;width:0%;background:#5e5e5e;transition:width .6s ease,background-color .3s}
.meter>span.warn{background:var(--red);opacity:.55}
.meter>span.crit{background:var(--red)}
.cell .foot{font-size:9.5px;letter-spacing:.1em;text-transform:uppercase;color:var(--dim);margin-top:7px;min-height:12px;font-variant-numeric:tabular-nums}

/* ---------- strip ---------- */
.strip{display:grid;grid-template-columns:repeat(5,1fr);gap:1px;background:var(--line);
  border-bottom:1px solid var(--line)}
.si{background:var(--panel);padding:9px 14px}
.si .lbl{font-size:9px;letter-spacing:.16em;color:var(--dim);text-transform:uppercase;margin-bottom:3px}
.si .lbl::before{content:"+ ";color:var(--line2)}
.si .val{font-size:13.5px;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:.02em}
.si .val.na{color:var(--dim);font-weight:400}

/* ---------- ops console ---------- */
.opsgrid{display:grid;grid-template-columns:1.1fr 1.1fr 1fr;gap:1px;background:var(--line);
  border-top:1px solid var(--line);border-bottom:1px solid var(--line)}
.ocell{background:var(--panel);padding:12px 14px;min-height:96px;display:flex;flex-direction:column}
.ocell .lbl{font-size:9.5px;letter-spacing:.16em;text-transform:uppercase;color:var(--mut)}
.ocell .lbl i{font-style:normal;color:var(--dim)}
.obtns{display:flex;gap:10px;flex-wrap:wrap;margin-top:auto;padding-top:10px}
.obtn{font-family:var(--mono);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;
  background:transparent;color:var(--fg);border:1px solid var(--line2);padding:8px 16px;cursor:pointer}
.obtn:hover:not(:disabled){border-color:var(--fg);background:#161616}
.obtn.danger{color:var(--red);border-color:rgba(255,42,42,.45)}
.obtn.danger:hover:not(:disabled){border-color:var(--red);background:rgba(255,42,42,.08)}
.obtn.armed{background:var(--red);color:#000;border-color:var(--red)}
.obtn:disabled{opacity:.3;cursor:not-allowed}
.ophase{font-family:var(--mono);font-size:19px;font-weight:700;letter-spacing:.04em;margin-top:auto;padding-top:8px}
.ophase.live{color:var(--fg)}
.ophase.live::after{content:"█";margin-left:8px;animation:blink 1s steps(2) infinite}
.ophase.ok{color:var(--grn)}
.ophase.bad{color:var(--red)}
.omsg{font-size:10px;letter-spacing:.08em;text-transform:uppercase;color:var(--mut);margin-top:6px;min-height:14px;word-break:break-all}
.omsg.err{color:var(--red)}
.omsg.ok{color:var(--grn)}
@keyframes blink{50%{opacity:0}}
.finp{font-family:var(--mono);font-size:11px;background:var(--panel2);color:var(--fg);
  border:1px solid var(--line2);padding:6px 10px;letter-spacing:.06em;width:170px}
.finp:focus{outline:none;border-color:var(--fg)}

/* ---------- mods ---------- */
.dbanner{display:none;align-items:center;gap:14px;flex-wrap:wrap;margin:10px 18px 0;
  border:1px solid rgba(255,42,42,.5);background:rgba(255,42,42,.06);color:var(--red);
  font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;padding:8px 12px}
.dbanner.show{display:flex}
.mwrap{border-top:1px solid var(--line);border-bottom:1px solid var(--line);background:var(--line);
  display:flex;flex-direction:column;max-height:340px;overflow-y:auto}
.mrow{display:grid;grid-template-columns:minmax(0,1fr) 90px 120px 90px 170px;gap:1px;
  background:var(--panel);align-items:center;padding:7px 14px;font-size:11.5px}
.mrow.mhead{position:sticky;top:0;background:var(--panel2);font-size:9px;letter-spacing:.16em;
  text-transform:uppercase;color:var(--dim);z-index:2}
.mrow .mname{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--fg)}
.mrow.off .mname{color:var(--dim);text-decoration:line-through}
.mrow span{color:var(--mut);font-variant-numeric:tabular-nums;letter-spacing:.04em}
.mrow .mst{font-weight:700}
.mrow .mst.on{color:var(--grn)}
.mrow .mst.off{color:var(--dim)}
.mbtns{display:flex;gap:8px;justify-content:flex-end}
.mbtn{font-family:var(--mono);font-size:9.5px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;
  background:transparent;color:var(--mut);border:1px solid var(--line2);padding:3px 9px;cursor:pointer}
.mbtn:hover{color:var(--fg);border-color:var(--fg)}
.mbtn.del:hover{color:var(--red);border-color:var(--red)}
.mbtn.armed{background:var(--red);color:#000;border-color:var(--red)}
.mempty{background:var(--panel);padding:16px 14px;font-size:10.5px;letter-spacing:.12em;color:var(--dim);text-transform:uppercase}

/* ---------- log ---------- */
.lsec{border-bottom:1px solid var(--line);display:flex;flex-direction:column}
.lhead{display:flex;justify-content:space-between;padding:8px 18px;font-size:10px;
  letter-spacing:.16em;text-transform:uppercase;color:var(--mut)}
.lhead .l b{color:var(--fg)}
.lhead .l::before{content:">>> ";color:var(--red)}
pre#log{font-size:11px;line-height:1.62;color:#9c9c9c;background:var(--panel2);
  padding:10px 16px;min-height:180px;max-height:320px;flex:1 1 auto;overflow:auto;white-space:pre-wrap;word-break:break-all;margin:0}
pre#log .ts{color:var(--dim)}
pre#log .er{color:var(--red)}
pre#log .wn{color:var(--red);opacity:.55}

/* ---------- footer ---------- */
footer{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:9px 18px;
  font-size:9.5px;letter-spacing:.14em;text-transform:uppercase;color:var(--dim)}
footer b{color:var(--mut)}
footer .c::before{content:"© ";color:var(--line2)}
footer .r::before{content:"® ";color:var(--line2)}

@media (max-width:1150px){.grid{grid-template-columns:repeat(3,1fr)}.opsgrid{grid-template-columns:1fr}.strip{grid-template-columns:repeat(2,1fr)}}
@media (max-width:900px){.mrow{grid-template-columns:minmax(0,1fr) 90px 150px}.mrow span:nth-child(2),.mrow span:nth-child(3){display:none}}
@media (max-width:680px){.grid{grid-template-columns:repeat(2,1fr)}.hero{grid-template-columns:1fr}.hright{text-align:left}}
</style>
</head>
<body>
<div class="wrap">
  <div class="bar">
    <span><b>HWTAB</b> /// NODE TELEMETRY</span>
    <span class="r">
      <span>UNIT / D-01</span>
      <span>REV 2.7.0</span>
      <span>LAN / 192.168.1.0/24</span>
      <span id="clock">--:--:--</span>
    </span>
  </div>

  <section class="hero">
    <div>
      <div class="micro">[ NODE: <b>ST-LAPTOP</b> ] MINECRAFT 1.21.1 /// NEOFORGE 21.1.234 /// SUPERFLAT</div>
      <h1 id="heroState">LINKING</h1>
      <div class="herosub" id="heroSub">ACQUIRING TELEMETRY FEED /// POLL 3S</div>
    </div>
    <div class="hright">
      <div class="lbl">[ TICK RATE ]</div>
      <div class="tpsnum" id="tpsHero">--<small>/20 TPS</small></div>
      <div class="micro" id="tpsFoot" style="margin-top:6px;color:var(--dim)">HWTAB MOD NOT LOADED</div>
    </div>
  </section>
  <div class="hazard stripes-only" id="hazard"></div>

  <div class="gridlabel"><span>[ GRID A / CORE METRICS ]</span><b>POLL 3000MS /// CACHE 2000MS</b></div>
  <div class="grid">
    <div class="cell na" id="t-mspt">
      <div class="lbl">MSPT <i>/ TICK</i></div>
      <div class="num" id="mspt">n/a</div>
      <div class="meter"><span id="msptBar"></span></div>
      <div class="foot">LIMIT 50MS</div>
    </div>
    <div class="cell na" id="t-players">
      <div class="lbl">SESSIONS <i>/ LIVE</i></div>
      <div class="num" id="players">n/a</div>
      <div class="meter" style="visibility:hidden"><span></span></div>
      <div class="foot" id="playersFoot">NO DATA</div>
    </div>
    <div class="cell na" id="t-heap">
      <div class="lbl">JVM HEAP</div>
      <div class="num" id="heap">n/a</div>
      <div class="meter"><span id="heapBar"></span></div>
      <div class="foot" id="heapFoot">HWTAB NOT LOADED</div>
    </div>
    <div class="cell" id="t-cpu">
      <div class="lbl">CPU <i>/ ALL CORES</i></div>
      <div class="num" id="cpu">--<small>%</small></div>
      <div class="meter"><span id="cpuBar"></span></div>
      <div class="foot" id="cpuFoot">THRESHOLD 85%</div>
    </div>
    <div class="cell" id="t-ram">
      <div class="lbl">SYSTEM MEM</div>
      <div class="num" id="ram">--<small>GB</small></div>
      <div class="meter"><span id="ramBar"></span></div>
      <div class="foot" id="ramFoot">USED / TOTAL</div>
    </div>
    <div class="cell na" id="t-temp">
      <div class="lbl">PKG TEMP</div>
      <div class="num" id="temp">n/a</div>
      <div class="meter" style="visibility:hidden"><span></span></div>
      <div class="foot">SENSOR MASKED / VBS</div>
    </div>
  </div>

  <div class="strip">
    <div class="si"><div class="lbl">SERVER STATE</div><div class="val" id="mcState">--</div></div>
    <div class="si"><div class="lbl">SERVER UPTIME</div><div class="val" id="mcUptime">--</div></div>
    <div class="si"><div class="lbl">SYSTEM UPTIME</div><div class="val" id="uptime">--</div></div>
    <div class="si"><div class="lbl">DISK C: FREE</div><div class="val" id="disk">--</div></div>
    <div class="si"><div class="lbl">MODS LOADED</div><div class="val" id="stripMods">--</div></div>
  </div>

  <div class="gridlabel"><span>[ OPS CONSOLE / POWER ]</span><b>ACTIONS RUN AS SYSTEM /// LAN ONLY</b></div>
  <div class="opsgrid">
    <div class="ocell">
      <div class="lbl">POWER <i>/ TASK MCServer-7m</i></div>
      <div class="obtns">
        <button class="obtn danger" id="btnRestart">RESTART</button>
        <button class="obtn danger" id="btnStop">STOP</button>
        <button class="obtn" id="btnStart">START</button>
      </div>
    </div>
    <div class="ocell">
      <div class="lbl">ACTION STATUS</div>
      <div class="ophase" id="opsPhase">IDLE</div>
      <div class="omsg" id="opsMsg">NO ACTIVE OPERATION</div>
    </div>
    <div class="ocell">
      <div class="lbl">BRIEFING</div>
      <div class="omsg">RESTART CYCLE ~2MIN /// STOP IS CLEAN (TASK /END) /// MOD CHANGES APPLY ON NEXT BOOT</div>
    </div>
  </div>

  <div class="gridlabel">
    <span>[ MOD ROSTER /// <b id="modCount">--</b> ]</span>
    <span class="rmod" style="display:flex;gap:8px;align-items:center">
      <input class="finp" id="modFilter" placeholder="FILTER" autocomplete="off">
      <button class="obtn" id="btnRescan">RESCAN</button>
      <button class="obtn" id="btnUpload">UPLOAD .JAR</button>
      <input type="file" id="modFile" accept=".jar" multiple style="display:none">
    </span>
  </div>
  <div class="dbanner" id="dirtyBanner">MODS CHANGED /// RESTART REQUIRED TO APPLY
    <button class="obtn danger" id="btnDirtyRestart">RESTART NOW</button>
  </div>
  <div class="mwrap" id="mwrap">
    <div class="mrow mhead"><span>NAME</span><span>SIZE</span><span>MODIFIED</span><span>STATE</span><span style="text-align:right">OPS</span></div>
    <div id="modsBody"><div class="mempty">SCANNING…</div></div>
  </div>

  <div class="lsec">
    <div class="lhead">
      <span class="l">LOG STREAM /// <b>logs/latest.log</b></span>
      <span>TAIL 15 /// NO AUTOSCROLL /// POLL 3S</span>
    </div>
    <pre id="log">ACQUIRING…</pre>
  </div>

  <footer>
    <span class="c">HWTAB CONSOLE UNIT/D-01</span>
    <span>HTTP :8787 /// NO CDN /// ZERO DEPENDENCY</span>
    <span class="r">BUILT FOR ST-LAPTOP /// 192.168.1.14</span>
  </footer>
</div>

<script>
const $ = id => document.getElementById(id);
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
const escAttr = s => esc(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const fmt = (v,d) => (v===null||v===undefined||isNaN(v)) ? null : Number(v).toFixed(d===undefined?1:d);
const setMeter = (el,pct,cls) => { el.style.width = Math.max(0,Math.min(100,pct||0))+'%'; el.className = cls||''; };
const okTile = id => { $(id).classList.remove('na'); };
const naTile = id => { $(id).classList.add('na'); $(id).dataset.state=''; };
const stTile = (id,st) => { $(id).dataset.state = (st&&st!=='ok')?st:''; };
const stateOf = (v,warn,crit) => { if(v===null||v===undefined||isNaN(v))return null; return v>=crit?'crit':(v>=warn?'warn':'ok'); };
setInterval(()=>{ $('clock').textContent = new Date().toLocaleTimeString('ja-JP',{hour12:false}); },1000);

const BUSY = ['initiating','stopping','starting','waiting'];
let actionBusy = false;
let serverRunning = false;

function renderLog(lines){
  if(!lines||!lines.length){ $('log').textContent = 'NO DATA'; return; }
  $('log').innerHTML = lines.map(l=>{
    const e = esc(l);
    const m = e.match(/^(\[[^\]]*\]\s*)/);
    const ts = m?('<span class="ts">'+m[1]+'</span>'):'';
    const body = m?e.slice(m[1].length):e;
    let cl='';
    if(/ERROR|FATAL|Exception/.test(body)) cl=' class="er"';
    else if(/WARN/.test(body)) cl=' class="wn"';
    return ts+'<span'+cl+'>'+body+'</span>';
  }).join('\n');
}

function opsNote(text, cls){
  const el = $('opsMsg');
  el.textContent = text;
  el.className = 'omsg' + (cls?(' '+cls):'');
}

/* ---------- ops actions ---------- */
const armTimers = {};
function armButton(btn, fn){
  const id = btn.id;
  if(btn.classList.contains('armed')){ btn.classList.remove('armed'); btn.textContent = btn.dataset.label; clearTimeout(armTimers[id]); fn(); return; }
  btn.dataset.label = btn.textContent;
  btn.classList.add('armed'); btn.textContent = 'CONFIRM?';
  armTimers[id] = setTimeout(()=>{ btn.classList.remove('armed'); btn.textContent = btn.dataset.label; }, 3500);
}
async function doAction(mode, silent){
  try{
    const r = await fetch('/api/action/'+mode, {method:'POST'});
    const d = await r.json();
    if(d.ok){ opsNote(mode.toUpperCase()+' DISPATCHED /// MONITORING…','ok'); }
    else { opsNote('REJECTED: '+(d.err||'BUSY'),'err'); if(silent) alert('REJECTED: '+(d.err||'BUSY')); }
  }catch(e){ opsNote('ACTION REQUEST FAILED','err'); }
}
$('btnRestart').addEventListener('click', function(){ armButton(this, ()=>doAction('restart')); });
$('btnStop').addEventListener('click', function(){ armButton(this, ()=>doAction('stop')); });
$('btnStart').addEventListener('click', ()=>doAction('start'));
$('btnDirtyRestart').addEventListener('click', ()=>doAction('restart'));

/* ---------- mods ---------- */
let MODS = [];
async function loadMods(){
  try{
    const r = await fetch('/api/mods',{cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    const d = await r.json();
    MODS = d.mods||[];
    $('modCount').textContent = (d.active||0)+' ON / '+(d.disabled||0)+' OFF'+(d.dirty?' /// DIRTY':'');
    renderMods();
  }catch(e){ $('modsBody').innerHTML = '<div class="mempty">MOD INVENTORY UNREACHABLE</div>'; }
}
function renderMods(){
  const q = ($('modFilter').value||'').toLowerCase();
  const rows = MODS.filter(m=>m.name.toLowerCase().includes(q));
  if(!rows.length){ $('modsBody').innerHTML = '<div class="mempty">NO MATCH</div>'; return; }
  $('modsBody').innerHTML = rows.map(m=>{
    const dt = new Date(m.mtime*1000);
    const p2 = n => String(n).padStart(2,'0');
    const mm = p2(dt.getMonth()+1)+'-'+p2(dt.getDate())+' '+p2(dt.getHours())+':'+p2(dt.getMinutes());
    return '<div class="mrow'+(m.enabled?'':' off')+'">'
      +'<span class="mname" title="'+escAttr(m.name)+'">'+esc(m.name)+'</span>'
      +'<span>'+m.sizeKB+'KB</span>'
      +'<span>'+mm+'</span>'
      +'<span class="mst '+(m.enabled?'on':'off')+'">'+(m.enabled?'ON':'OFF')+'</span>'
      +'<span class="mbtns">'
      +'<button class="mbtn" data-a="toggle" data-n="'+escAttr(m.name)+'">'+(m.enabled?'DISABLE':'ENABLE')+'</button>'
      +'<button class="mbtn del" data-a="delete" data-n="'+escAttr(m.name)+'">DEL</button>'
      +'</span></div>';
  }).join('');
}
$('modFilter').addEventListener('input', renderMods);
$('btnRescan').addEventListener('click', loadMods);
$('modsBody').addEventListener('click', async ev=>{
  const b = ev.target.closest('button.mbtn');
  if(!b) return;
  const name = b.getAttribute('data-n'), act = b.getAttribute('data-a');
  if(act==='delete'){
    if(!b.classList.contains('armed')){ b.dataset.label=b.textContent; b.classList.add('armed'); b.textContent='SURE?';
      setTimeout(()=>{ b.classList.remove('armed'); b.textContent=b.dataset.label; },3000); return; }
  }
  b.disabled = true;
  try{
    const r = await fetch('/api/mods/'+act, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:name})});
    const d = await r.json().catch(()=>({ok:false,err:'HTTP '+r.status}));
    if(!d.ok) opsNote('MOD OP FAILED: '+(d.err||'?'),'err'); else opsNote('MOD '+(act==='toggle'?'TOGGLED':'DELETED')+': '+name,'ok');
  }catch(e){ opsNote('REQUEST FAILED: '+e,'err'); }
  loadMods();
});
$('btnUpload').addEventListener('click', ()=>$('modFile').click());
$('modFile').addEventListener('change', ()=>uploadFiles([...$('modFile').files]));
const mwrap = $('mwrap');
mwrap.addEventListener('dragover', e=>{ e.preventDefault(); });
mwrap.addEventListener('drop', e=>{ e.preventDefault(); uploadFiles([...e.dataTransfer.files]); });
async function uploadFiles(files){
  const jars = files.filter(f=>/\.jar$/i.test(f.name));
  if(!jars.length){ opsNote('UPLOAD SKIPPED /// .JAR ONLY','err'); return; }
  let okN = 0, failN = 0;
  for(const f of jars){
    opsNote('UPLOADING '+f.name+' ('+Math.round(f.size/1024)+'KB)…');
    try{
      const r = await fetch('/api/mods/upload?name='+encodeURIComponent(f.name), {method:'POST',body:f});
      const d = await r.json();
      if(d.ok) okN++; else { failN++; opsNote('UPLOAD FAILED: '+f.name+' /// '+(d.err||'?'),'err'); }
    }catch(e){ failN++; opsNote('UPLOAD FAILED: '+f.name,'err'); }
  }
  if(okN) opsNote('UPLOAD COMPLETE /// '+okN+' OK'+(failN?(' / '+failN+' FAIL'):''),'ok');
  loadMods();
}

/* ---------- tick ---------- */
async function tick(){
  let s;
  try{
    const r = await fetch('/api/stats',{cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    s = await r.json();
  }catch(e){
    $('heroState').textContent='NO LINK'; $('heroState').className='crit';
    $('heroSub').innerHTML='TELEMETRY FEED LOST /// <span class="bad">RETRYING</span>';
    $('hazard').className='hazard on';
    return;
  }
  const n=s.node||{}, mc=s.mc||{};
  serverRunning = mc.state==='Running';
  let worst = serverRunning ? 'ok' : 'crit';

  const cpu=n.cpu;
  if(cpu===null||cpu===undefined){ $('cpu').innerHTML='n/a'; $('cpuFoot').textContent='NO DATA'; naTile('t-cpu'); setMeter($('cpuBar'),0,''); }
  else{
    okTile('t-cpu');
    const st=stateOf(cpu,85,95)||'ok';
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('cpu').innerHTML=fmt(cpu,0)+'<small>%</small>';
    $('cpuFoot').textContent='LOAD '+fmt(cpu,0)+'% / TH 85%';
    stTile('t-cpu',st); setMeter($('cpuBar'),cpu,st);
  }

  if(n.ramUsed===null||n.ramUsed===undefined||!n.ramTotal){ $('ram').innerHTML='n/a'; $('ramFoot').textContent='NO DATA'; naTile('t-ram'); setMeter($('ramBar'),0,''); }
  else{
    okTile('t-ram');
    const p=n.ramUsed/n.ramTotal*100, st=stateOf(p,90,97)||'ok';
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('ram').innerHTML=fmt(n.ramUsed)+'<small>GB</small>';
    $('ramFoot').textContent=fmt(n.ramUsed)+' / '+fmt(n.ramTotal,0)+' GB · '+Math.round(p)+'%';
    stTile('t-ram',st); setMeter($('ramBar'),p,st);
  }

  if(mc.heapUsed===null||mc.heapUsed===undefined||!mc.heapMax){ $('heap').innerHTML='n/a'; $('heapFoot').textContent='HWTAB NOT LOADED'; naTile('t-heap'); setMeter($('heapBar'),0,''); }
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

  if(mc.players===null||mc.players===undefined){ $('players').innerHTML='n/a'; $('playersFoot').textContent='NO DATA'; naTile('t-players'); }
  else{ okTile('t-players'); $('players').innerHTML=mc.players+'<small>USR</small>'; $('playersFoot').textContent=mc.players>0?'SESSIONS ACTIVE':'IDLE'; }

  if(n.tempC===null||n.tempC===undefined){ $('temp').innerHTML='n/a'; naTile('t-temp'); }
  else{ okTile('t-temp'); $('temp').innerHTML=fmt(n.tempC,0)+'<small>°C</small>'; }

  const tps=mc.tps;
  if(tps===null||tps===undefined){ $('tpsHero').innerHTML='--<small>/20 TPS</small>'; $('tpsFoot').textContent='HWTAB MOD NOT LOADED'; }
  else{
    const st=tps<10?'crit':(tps<15?'warn':'ok');
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('tpsHero').innerHTML=fmt(tps)+'<small>/20 TPS</small>';
    $('tpsHero').className='tpsnum'+(st==='crit'?' crit':'');
    $('tpsFoot').textContent=tps>=19.9?'FULL RATE':'DEGRADED TICK';
  }

  const up = serverRunning;
  $('mcState').textContent = up?'RUNNING':'DOWN';
  $('mcState').className = 'val'+(up?'':' na');
  if(!up) worst='crit';
  $('mcUptime').textContent = mc.uptimeText||'n/a';
  $('uptime').textContent = n.uptimeText||'n/a';
  $('disk').textContent = (n.diskFreeGB===null||n.diskFreeGB===undefined)?'n/a':fmt(n.diskFreeGB)+' GB';
  $('stripMods').textContent = (s.modsActive===undefined)?'--':(s.modsActive+' / '+(s.modsDisabled||0)+' OFF');

  renderLog(s.logTail);

  /* action state */
  const a = s.action;
  actionBusy = !!(a && BUSY.indexOf(a.phase)>=0);
  const ph = $('opsPhase');
  if(a){
    ph.textContent = a.phase.toUpperCase();
    ph.className = 'ophase ' + (actionBusy?'live':(a.phase==='done'?'ok':'bad'));
    if(!actionBusy && $('opsMsg').textContent.indexOf('DISPATCHED')>=0) opsNote(a.msg||('PHASE: '+a.phase), a.phase==='failed'?'err':'ok');
  } else {
    ph.textContent = 'IDLE'; ph.className = 'ophase';
    if($('opsMsg').textContent.indexOf('DISPATCHED')>=0) opsNote('NO ACTIVE OPERATION');
  }
  $('btnRestart').disabled = actionBusy;
  $('btnStop').disabled = actionBusy || !up;
  $('btnStart').disabled = actionBusy || up;

  /* hero */
  const hero=$('heroState');
  const stTxt = up ? 'RUNNING' : 'DOWN';
  const stCls = up ? 'ok' : 'bad';
  if(actionBusy){
    const map = {initiating:'ACTION QUEUED',stopping:'STOPPING',starting:'BOOTING',waiting:'BOOTING'};
    hero.textContent = map[a.phase]||'RESTARTING'; hero.className='warn';
    $('hazard').className='hazard on';
    $('heroSub').innerHTML = 'MANAGED OPERATION /// '+esc(a.msg||a.phase);
  } else if(worst==='crit'){
    hero.textContent='CRITICAL'; hero.className='crit'; $('hazard').className='hazard on';
    $('heroSub').innerHTML = 'SERVER THREAD /// PORT 25565 /// <span class="'+stCls+'">STATE: '+stTxt+'</span> /// THRESHOLD EVENT';
  } else if(worst==='warn'){
    hero.textContent='DEGRADED'; hero.className='warn'; $('hazard').className='hazard on';
    $('heroSub').innerHTML = 'SERVER THREAD /// PORT 25565 /// <span class="'+stCls+'">STATE: '+stTxt+'</span> /// THRESHOLD EVENT';
  } else {
    hero.textContent='OPERATIONAL'; hero.className=''; $('hazard').className='hazard stripes-only';
    $('heroSub').innerHTML = 'SERVER THREAD /// PORT 25565 /// <span class="ok">STATE: RUNNING</span> /// POLL 3S';
  }

  /* dirty banner */
  $('dirtyBanner').className = 'dbanner' + (s.modsDirty?' show':'');
}
tick();
setInterval(tick,3000);
loadMods();
setInterval(loadMods,20000);
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
    # uptime from the System process start time - pure native, no WMI
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
