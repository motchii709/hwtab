# nop
# ============================================================
#  hw_stats_loop.ps1  (MCServer hardware stats producer)
#  Writes C:\Users\motch\MCServer\hw_stats_hw.txt every 3 seconds:
#     ram=<usedGB>/<totalGB> cpu=<percent> temp=<celsius>
#  Consumed by the HwTab mod (merged into hw_stats.txt) and the
#  MC Node Dashboard (port 8787).
#  Temperature uses LibreHardwareMonitor; on machines where the
#  CPU temp MSR is not readable (e.g. Hyper-V/VBS) the temp key
#  is simply omitted and consumers show n/a.
#  ASCII only - safe for PowerShell 5.1.
# ============================================================
$ErrorActionPreference = 'Continue'
$hwFile = 'C:\Users\motch\MCServer\hw_stats_hw.txt'
$lhmDir = 'C:\Users\motch\MCServer\hwtools'

$lhm = $null
$cpuHw = $null
try {
    if (Test-Path (Join-Path $lhmDir 'LibreHardwareMonitorLib.dll')) {
        Get-ChildItem $lhmDir -Filter *.dll | ForEach-Object { try { [void][System.Reflection.Assembly]::LoadFrom($_.FullName) } catch { } }
        Add-Type -Path (Join-Path $lhmDir 'LibreHardwareMonitorLib.dll')
        $lhm = New-Object LibreHardwareMonitor.Hardware.Computer
        $lhm.IsCpuEnabled = $true
        $lhm.IsMotherboardEnabled = $true
        $lhm.IsMemoryEnabled = $true
        $lhm.IsGpuEnabled = $false
        $lhm.IsStorageEnabled = $false
        $lhm.IsNetworkEnabled = $false
        $lhm.IsControllerEnabled = $false
        $lhm.IsPsuEnabled = $false
        $lhm.IsBatteryEnabled = $false
        $lhm.Open()
        foreach ($hw in $lhm.Hardware) {
            if ($hw.HardwareType -eq 'Cpu') { $cpuHw = $hw; break }
        }
    }
} catch {
    $lhm = $null
    $cpuHw = $null
}

while ($true) {
    $ramU = $null
    $ramT = $null
    $cpu = $null
    $temp = $null

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramT = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramU = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    } catch { }

    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -ne $cpu) { $cpu = [int][math]::Round($cpu) }
    } catch { }

    if ($null -ne $cpuHw) {
        try {
            $cpuHw.Update()
            foreach ($s in $cpuHw.Sensors) {
                if ($s.SensorType -eq 'Load' -and $s.Name -eq 'CPU Total' -and $null -ne $s.Value) {
                    $cpu = [int][math]::Round([double]$s.Value)
                }
                if ($s.SensorType -eq 'Temperature' -and $null -ne $s.Value) {
                    $v = [double]$s.Value
                    if ($v -gt 0 -and $v -lt 120) {
                        if ($s.Name -match 'Package|Tdie|Tctl') { $temp = [int][math]::Round($v) }
                        elseif ($null -eq $temp) { $temp = [int][math]::Round($v) }
                    }
                }
            }
        } catch { }
    }

    $line = ''
    if ($null -ne $ramU -and $null -ne $ramT) { $line = "ram=$ramU/$ramT" }
    if ($null -ne $cpu) { $line = "$line cpu=$cpu" }
    if ($null -ne $temp) { $line = "$line temp=$temp" }
    try { Set-Content -Path $hwFile -Value $line.Trim() -Encoding ASCII } catch { }

    Start-Sleep -Seconds 3
}
