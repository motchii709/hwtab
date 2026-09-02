param([string]$Mode = 'restart')
# nop - MC server action executor (spawned by dashboard, runs detached)
$ErrorActionPreference = 'Continue'
$stateFile = 'C:\Users\motch\MCServer\hwtools\mc_action_state.txt'
$logFile = 'C:\Users\motch\MCServer\logs\latest.log'

function Write-State([string]$phase, [string]$msg) {
    $safe = $msg -replace '"', "'"
    $json = '{"mode":"' + $Mode + '","phase":"' + $phase + '","msg":"' + $safe + '","pid":' + $PID + ',"epoch":' + [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + '}'
    try { [System.IO.File]::WriteAllText($stateFile, $json) } catch { }
}

Write-State 'initiating' ('ACTION ' + $Mode.ToUpper() + ' DISPATCHED')

if ($Mode -eq 'stop' -or $Mode -eq 'restart') {
    Write-State 'stopping' 'ENDING TASK MCServer-7m'
    schtasks /end /tn MCServer-7m | Out-Null
    Start-Sleep -Seconds 6
    $left = @(Get-Process java -ErrorAction SilentlyContinue)
    foreach ($p in $left) {
        Write-State 'stopping' ('KILLING LEFTOVER JAVA PID ' + $p.Id)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 4
    $portFree = -not (Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue)
    if (-not $portFree) { Start-Sleep -Seconds 6 }
    if ($Mode -eq 'stop') {
        Write-State 'done' 'SERVER STOPPED'
        exit 0
    }
}

if ($Mode -eq 'start' -or $Mode -eq 'restart') {
    Write-State 'starting' 'LAUNCHING TASK MCServer-7m'
    schtasks /run /tn MCServer-7m | Out-Null
    $deadline = (Get-Date).AddSeconds(300)
    $done = $false
    while ((Get-Date) -lt $deadline -and -not $done) {
        Start-Sleep -Seconds 5
        $j = @(Get-Process java -ErrorAction SilentlyContinue)
        $l = Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue
        $portTxt = 'no'
        if ($l) { $portTxt = 'LISTEN' }
        Write-State 'waiting' ('BOOT java=' + $j.Count + ' port=' + $portTxt)
        if ($j.Count -gt 0 -and $l -and (Test-Path $logFile)) {
            $tail = Get-Content $logFile -Tail 25 -ErrorAction SilentlyContinue
            if ($tail -match 'Done \(') { $done = $true }
        }
    }
    if ($done) { Write-State 'done' 'SERVER IS UP - DONE' } else { Write-State 'failed' 'TIMEOUT WAITING FOR BOOT' }
}
