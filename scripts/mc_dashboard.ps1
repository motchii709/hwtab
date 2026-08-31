# MC Node Dashboard - zero-dependency HttpListener dashboard for the MCServer laptop.
#   GET  /          -> single-page dashboard (dark instrument console, Japanese, no CDN)
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
<title>ST-LAPTOP / MC Console</title>
<style>
:root{
  --bg:#0b0e13; --panel:#10141b; --panel2:#0d1117; --line:#1c2230; --line2:#242c3d;
  --tx:#e8ecf3; --mut:#7d8798; --dim:#545e6e;
  --ok:#34d399; --warn:#f5b23e; --crit:#ef5350;
  --mono:"Cascadia Code","Cascadia Mono",Consolas,"Courier New",monospace;
  --sans:"Segoe UI Variable Text","Segoe UI","Yu Gothic UI","Hiragino Sans",system-ui,sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%}
body{background:var(--bg);color:var(--tx);font-family:var(--sans);min-height:100vh;
  display:flex;flex-direction:column}
.wrap{width:100%;max-width:1240px;margin:0 auto;padding:0 26px}

/* ---------- header ---------- */
header{border-bottom:1px solid var(--line)}
.hrow{display:flex;align-items:center;justify-content:space-between;height:64px;gap:16px}
.brand .eyebrow{font-family:var(--mono);font-size:9.5px;letter-spacing:2.2px;color:var(--dim);text-transform:uppercase}
.brand h1{font-size:14.5px;font-weight:600;letter-spacing:.2px;margin-top:3px}
.brand h1 small{color:var(--mut);font-weight:400;font-size:12px;margin-left:8px}
.hstat{display:flex;align-items:center;gap:14px}
.state{display:inline-flex;align-items:center;gap:8px;font-family:var(--mono);font-size:11.5px;
  letter-spacing:.8px;color:var(--mut);border:1px solid var(--line);border-radius:999px;padding:6px 13px;background:var(--panel)}
.dot{width:8px;height:8px;border-radius:50%;background:var(--dim);flex:none}
.state.ok .dot{background:var(--ok);box-shadow:0 0 8px rgba(52,211,153,.45)}
.state.ok{color:var(--ok);border-color:rgba(52,211,153,.35)}
.state.warn .dot{background:var(--warn);box-shadow:0 0 8px rgba(245,178,62,.45)}
.state.warn{color:var(--warn);border-color:rgba(245,178,62,.4)}
.state.crit .dot{background:var(--crit);box-shadow:0 0 10px rgba(239,83,80,.5);animation:blink 1.6s ease-in-out infinite}
.state.crit{color:var(--crit);border-color:rgba(239,83,80,.45)}
@keyframes blink{50%{opacity:.35}}
.clock{font-family:var(--mono);font-size:12px;color:var(--mut);letter-spacing:.5px;font-variant-numeric:tabular-nums}

/* ---------- tiles ---------- */
.tiles{display:grid;grid-template-columns:repeat(6,1fr);gap:10px;margin:22px 0 10px}
.tile{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:13px 15px 12px;
  display:flex;flex-direction:column;gap:8px;min-height:108px;transition:border-color .3s}
.tile:hover{border-color:var(--line2)}
.tile .lbl{font-size:10.5px;font-weight:600;letter-spacing:1.1px;color:var(--mut)}
.tile .lbl .tgt{color:var(--dim);letter-spacing:.4px;font-weight:400}
.tile .num{font-family:var(--mono);font-size:33px;font-weight:700;line-height:1;
  letter-spacing:-.5px;font-variant-numeric:tabular-nums;margin-top:auto;color:var(--tx);
  transition:color .4s}
.tile .num .unit{font-size:13px;font-weight:400;color:var(--mut);letter-spacing:0;margin-left:4px}
.tile[data-state="warn"] .num{color:var(--warn)}
.tile[data-state="crit"] .num{color:var(--crit)}
.tile.na .num{color:var(--dim);font-size:24px}
.meter{height:3px;background:#171d29;border-radius:2px;overflow:hidden}
.meter>span{display:block;height:100%;width:0%;background:var(--ok);border-radius:2px;transition:width .6s ease,background-color .4s}
.meter>span.warn{background:var(--warn)}
.meter>span.crit{background:var(--crit)}
.tile .foot{font-family:var(--mono);font-size:10px;color:var(--dim);letter-spacing:.3px;font-variant-numeric:tabular-nums;min-height:13px}

/* ---------- strip ---------- */
.strip{display:grid;grid-template-columns:repeat(4,1fr);background:var(--panel);
  border:1px solid var(--line);border-radius:10px;margin-bottom:10px}
.si{padding:11px 16px;border-left:1px solid var(--line)}
.si:first-child{border-left:none}
.si .lbl{font-size:10px;font-weight:600;letter-spacing:1.1px;color:var(--mut);margin-bottom:5px}
.si .val{font-family:var(--mono);font-size:14px;font-weight:600;font-variant-numeric:tabular-nums;color:var(--tx)}
.si .val.na{color:var(--dim)}

/* ---------- log ---------- */
.console{background:var(--panel2);border:1px solid var(--line);border-radius:10px;overflow:hidden;margin-bottom:10px}
.chead{display:flex;justify-content:space-between;align-items:center;padding:9px 16px;border-bottom:1px solid var(--line)}
.chead .t{font-family:var(--mono);font-size:10.5px;letter-spacing:1.4px;color:var(--mut);text-transform:uppercase}
.chead .h{font-family:var(--mono);font-size:10px;color:var(--dim)}
pre#log{font-family:var(--mono);font-size:11.3px;line-height:1.62;color:#9aa5b5;height:264px;
  overflow:auto;padding:11px 16px;white-space:pre-wrap;word-break:break-all}
pre#log .er{color:var(--crit)}
pre#log .wn{color:var(--warn)}
pre#log .ts{color:var(--dim)}

/* ---------- footer ---------- */
footer{margin-top:auto;padding:14px 0 18px}
footer .fi{border-top:1px solid var(--line);padding-top:12px;font-family:var(--mono);
  font-size:10px;color:var(--dim);text-align:center;letter-spacing:.4px}

@media (max-width:1100px){.tiles{grid-template-columns:repeat(3,1fr)}}
@media (max-width:820px){.strip{grid-template-columns:repeat(2,1fr)}.si:nth-child(3){border-left:none;border-top:1px solid var(--line)}.si:nth-child(4){border-top:1px solid var(--line)}}
@media (max-width:620px){.tiles{grid-template-columns:repeat(2,1fr)}.hrow{height:auto;padding:12px 0;flex-wrap:wrap}.clock{display:none}}
</style>
</head>
<body>
<header>
  <div class="wrap hrow">
    <div class="brand">
      <div class="eyebrow">HwTab Console</div>
      <h1>ST-LAPTOP<small>Minecraft 1.21.1 / NeoForge</small></h1>
    </div>
    <div class="hstat">
      <span class="clock" id="clock">--:--:--</span>
      <span class="state" id="overall"><i class="dot"></i><span id="overallTx">接続中</span></span>
    </div>
  </div>
</header>

<main class="wrap">
  <div class="tiles">
    <div class="tile na" id="t-tps">
      <div class="lbl">TPS <span class="tgt">/ 20.0</span></div>
      <div class="num" id="tps">n/a</div>
      <div class="meter"><span id="tpsBar"></span></div>
      <div class="foot" id="tpsFoot">hwtab 再起動後に表示</div>
    </div>
    <div class="tile na" id="t-mspt">
      <div class="lbl">MSPT</div>
      <div class="num" id="mspt">n/a</div>
      <div class="meter"><span id="msptBar"></span></div>
      <div class="foot" id="msptFoot">tick 平均 / 目標 &lt;50ms</div>
    </div>
    <div class="tile na" id="t-players">
      <div class="lbl">プレイヤー</div>
      <div class="num" id="players">n/a</div>
      <div class="meter" style="visibility:hidden"><span></span></div>
      <div class="foot" id="playersFoot">オンライン</div>
    </div>
    <div class="tile" id="t-heap">
      <div class="lbl">JVMヒープ</div>
      <div class="num" id="heap">n/a</div>
      <div class="meter"><span id="heapBar"></span></div>
      <div class="foot" id="heapFoot">hwtab 再起動後に表示</div>
    </div>
    <div class="tile" id="t-cpu">
      <div class="lbl">CPU</div>
      <div class="num" id="cpu">–<span class="unit">%</span></div>
      <div class="meter"><span id="cpuBar"></span></div>
      <div class="foot" id="cpuFoot">全コア平均</div>
    </div>
    <div class="tile" id="t-ram">
      <div class="lbl">システムメモリ</div>
      <div class="num" id="ram">–<span class="unit">GB</span></div>
      <div class="meter"><span id="ramBar"></span></div>
      <div class="foot" id="ramFoot">使用 / 総容量</div>
    </div>
  </div>

  <div class="strip">
    <div class="si"><div class="lbl">サーバー状態</div><div class="val" id="mcState">確認中</div></div>
    <div class="si"><div class="lbl">サーバー稼働</div><div class="val" id="mcUptime">–</div></div>
    <div class="si"><div class="lbl">システム稼働</div><div class="val" id="uptime">–</div></div>
    <div class="si"><div class="lbl">ディスク C: 空き</div><div class="val" id="disk">–</div></div>
  </div>

  <div class="console">
    <div class="chead"><span class="t">Log · logs/latest.log</span><span class="h">末尾15行 · 3秒ごとに更新 · 自動スクロールなし</span></div>
    <pre id="log">読み込み中…</pre>
  </div>
</main>

<footer><div class="wrap fi">HwTab dashboard · HTTP :8787 · LAN 192.168.1.0/24 のみ · 外部CDN不使用</div></footer>

<script>
const $ = id => document.getElementById(id);
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
const fmt = (v,d) => (v===null||v===undefined||isNaN(v)) ? null : Number(v).toFixed(d===undefined?1:d);
const setMeter = (el,pct,cls) => { el.style.width = Math.max(0,Math.min(100,pct||0))+'%'; el.className = cls||''; };
const tileState = (id,st) => { const t=$(id); t.dataset.state=st||''; t.classList.toggle('na',!st&&t.classList.contains('na')?false:false); };
const naTile = id => { const t=$(id); t.classList.add('na'); t.dataset.state=''; };
const okTile = id => { const t=$(id); t.classList.remove('na'); };
function stateOf(v,warn,crit){ if(v===null||v===undefined||isNaN(v))return null; return v>=crit?'crit':(v>=warn?'warn':'ok'); }
setInterval(()=>{ $('clock').textContent = new Date().toLocaleTimeString('ja-JP',{hour12:false}); },1000);

function renderLog(lines){
  if(!lines||!lines.length){ $('log').textContent = 'n/a'; return; }
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

async function tick(){
  let s;
  try{
    const r = await fetch('/api/stats',{cache:'no-store'});
    if(!r.ok) throw new Error('http '+r.status);
    s = await r.json();
  }catch(e){
    const o=$('overall'); o.className='state crit'; $('overallTx').textContent='APIエラー';
    return;
  }
  const n=s.node||{}, mc=s.mc||{};
  let worst = mc.state==='Running' ? 'ok' : 'crit';

  /* CPU */
  const cpu = n.cpu;
  if(cpu===null||cpu===undefined){ $('cpu').innerHTML='n/a'; $('cpuFoot').textContent='n/a'; naTile('t-cpu'); setMeter($('cpuBar'),0,''); }
  else{
    okTile('t-cpu');
    const st=stateOf(cpu,85,95)||'ok';
    if(st!=='ok'&&worst!=='crit'&&st==='crit')worst='crit'; if(st==='warn'&&worst==='ok')worst='warn';
    $('cpu').innerHTML=fmt(cpu,0)+'<span class="unit">%</span>';
    $('cpuFoot').textContent=fmt(cpu,0)+'% / 閾値 85%';
    $('t-cpu').dataset.state=st==='ok'?'':st;
    setMeter($('cpuBar'),cpu,st);
  }

  /* RAM */
  if(n.ramUsed===null||n.ramUsed===undefined||!n.ramTotal){ $('ram').innerHTML='n/a'; $('ramFoot').textContent='n/a'; naTile('t-ram'); setMeter($('ramBar'),0,''); }
  else{
    okTile('t-ram');
    const p=n.ramUsed/n.ramTotal*100, st=stateOf(p,90,97)||'ok';
    if(st==='crit'&&worst!=='crit')worst='crit'; if(st==='warn'&&worst==='ok')worst='warn';
    $('ram').innerHTML=fmt(n.ramUsed)+'<span class="unit">GB</span>';
    $('ramFoot').textContent=fmt(n.ramUsed)+' / '+fmt(n.ramTotal,0)+' GB · '+Math.round(p)+'%';
    $('t-ram').dataset.state=st==='ok'?'':st;
    setMeter($('ramBar'),p,st);
  }

  /* HEAP */
  if(mc.heapUsed===null||mc.heapUsed===undefined||!mc.heapMax){ $('heap').innerHTML='n/a'; $('heapFoot').textContent='hwtab 再起動後に表示'; naTile('t-heap'); setMeter($('heapBar'),0,''); }
  else{
    okTile('t-heap');
    const p=mc.heapUsed/mc.heapMax*100, st=stateOf(p,85,95)||'ok';
    if(st==='crit'&&worst!=='crit')worst='crit'; if(st==='warn'&&worst==='ok')worst='warn';
    $('heap').innerHTML=fmt(mc.heapUsed)+'<span class="unit">GB</span>';
    $('heapFoot').textContent=fmt(mc.heapUsed)+' / '+fmt(mc.heapMax,0)+' GB · '+Math.round(p)+'%';
    $('t-heap').dataset.state=st==='ok'?'':st;
    setMeter($('heapBar'),p,st);
  }

  /* TPS */
  const tps=mc.tps;
  if(tps===null||tps===undefined){ $('tps').innerHTML='n/a'; $('tpsFoot').textContent='hwtab 再起動後に表示'; naTile('t-tps'); setMeter($('tpsBar'),0,''); }
  else{
    okTile('t-tps');
    const st=tps<10?'crit':(tps<15?'warn':'ok');
    if(st==='crit')worst='crit'; else if(st==='warn'&&worst==='ok')worst='warn';
    $('tps').innerHTML=fmt(tps)+'<span class="unit">/20</span>';
    $('tpsFoot').textContent=tps>=19.9?'フルスピード':'目標 20.0';
    $('t-tps').dataset.state=st==='ok'?'':st;
    setMeter($('tpsBar'),tps/20*100,st);
  }

  /* MSPT */
  const ms=mc.mspt;
  if(ms===null||ms===undefined){ $('mspt').innerHTML='n/a'; naTile('t-mspt'); setMeter($('msptBar'),0,''); }
  else{
    okTile('t-mspt');
    const st=ms>50?'crit':(ms>30?'warn':'ok');
    if(st==='crit'&&worst!=='crit')worst='crit'; if(st==='warn'&&worst==='ok')worst='warn';
    $('mspt').innerHTML=fmt(ms)+'<span class="unit">ms</span>';
    $('msptFoot').textContent='tick 平均 · 上限 50ms';
    $('t-mspt').dataset.state=st==='ok'?'':st;
    setMeter($('msptBar'),Math.min(100,ms/50*100),st);
  }

  /* players */
  if(mc.players===null||mc.players===undefined){ $('players').innerHTML='n/a'; naTile('t-players'); }
  else{ okTile('t-players'); $('players').innerHTML=mc.players+'<span class="unit">人</span>'; $('playersFoot').textContent=mc.players>0?'接続中':'誰もいない'; }

  /* strip */
  const up = mc.state==='Running';
  $('mcState').textContent = up?'Running':'Down';
  $('mcState').className = 'val'+(up?'':' na');
  $('mcUptime').textContent = mc.uptimeText||'n/a';
  $('uptime').textContent = n.uptimeText||'n/a';
  $('disk').textContent = (n.diskFreeGB===null||n.diskFreeGB===undefined)?'n/a':fmt(n.diskFreeGB)+' GB';

  renderLog(s.logTail);

  const labels={ok:'正常',warn:'警告',crit:'異常',down:'サーバー停止',err:'APIエラー'};
  const o=$('overall'); o.className='state '+worst; $('overallTx').textContent=labels[worst];
}
tick();
setInterval(tick,3000);
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
                    $body = [System.Text.Encoding]::UTF8.GetBytes((Get-SnapshotCached))
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
