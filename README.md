# HwTab

**HwTab** は、Minecraft **NeoForge 1.21.1** 専用サーバー向けのサーバーサイドmodです。
サーバーを動かしているマシンのハードウェア状態(RAM / JVMヒープ / CPU / CPU温度)を、
ゲーム内 **TABリストのヘッダー** に1秒ごとに表示します。

```
RAM 15.2/15.7GB | JVM 3.4/6.0GB | CPU 22% | 62C
```

- ラベルは灰色、数値はAQUA。温度は **70°C超で黄色、85°C超で赤** に変わります(ASCII表記 `C`)。
- 取れない項目(温度センサーが無い環境など)は自動で省略されます。
- **サーバー専用mod** です。クライアントには何も追加せず、バニラクライアントのまま参加できます
  (`displayTest="IGNORE_ALL_VERSION"`)。
- BetterTab 等が使用している **フッターとは干渉しません**(ヘッダーのみ使用)。

同梱の `scripts/`(PowerShell)を使うと、TABヘッダー用のハードウェア値に加えて
`tps` / `mspt` / `players` / `jvm` を含む統計ファイルが生成され、
付属の **MC Node Dashboard**(Kubernetes風Webダッシュボード、ポート8787)からも
同じ値を参照できます。

---

## 必要要件

| 項目 | バージョン |
|---|---|
| Minecraft | 1.21 / 1.21.1 |
| NeoForge | 21.1.x(21.1.234で動作確認) |
| Java(サーバー) | 21以上 |
| 温度取得(任意) | Windows + [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) |

## インストール

1. `hwtab-1.0.0.jar` をサーバーの `mods/` フォルダに入れます。
2. (任意)後述の `hw_stats_loop.ps1` を設定すると RAM/CPU/温度 が表示されます。
   何も無くても **JVMヒープだけは常に表示** されます。
3. サーバーを再起動して完了。クライアント側の導入は不要です。

## 仕組み

```
[hw_stats_loop.ps1]  --3秒ごと-->  hw_stats_hw.txt   (ram= cpu= temp=)
        (LibreHardwareMonitor)                |
                                              v
[HwTab mod]  --1秒ごとにマージ+サーバー値追加-->  hw_stats.txt
             (tps= mspt= players= jvm= をmodが上書き書き込み)  |
                                                              v
                                   TABヘッダー表示 + MC Node Dashboard (:8787)
```

modは `hw_stats_hw.txt`(ハードウェア値)を読み、サーバー自身の値(TPS/MSPT/プレイヤー数/
JVMヒープ)とマージして `hw_stats.txt` として **上書き发布** します(modがauthoritative)。
`hw_stats_hw.txt` が30秒以上更新されていない場合はその項目を n/a 扱い、
ファイル読み書きの例外はすべて握り潰すので **modが原因でサーバーが落ちることはありません**。

## ハードウェア値の供給設定(Windows)

### 1. LibreHardwareMonitor の配置

1. [Releases](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases) から
   `LibreHardwareMonitor.zip`(net472版)をダウンロードして展開します。
2. 中身一式を `C:\Users\motch\MCServer\hwtools\` に置きます
   (`LibreHardwareMonitorLib.dll` が見える場所ならどこでも構いません)。

### 2. 常駐ループの登録

`scripts/hw_stats_loop.ps1` をサーバーディレクトリ横の `hwtools` に置き、
管理者 PowerShell で以下のようにシステム起動時に常駐させます:

```powershell
$action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\motch\MCServer\hwtools\hw_stats_loop.ps1'
$trigger  = New-ScheduledTaskTrigger -AtStartup
$principal= New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'MCServer-HWStats' -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Start-ScheduledTask -TaskName 'MCServer-HWStats'
```

> ノートPCでタスクがバッテリー切替時に静かに停止されないよう、
> `AllowStartIfOnBatteries` / `DontStopIfGoingOnBatteries` / `ExecutionTimeLimit=PT0S`
> は必ず指定してください(この3点がないと Task Scheduler が黙って常駐をkillします)。

3秒ごとに `hw_stats_hw.txt` が更新され、数秒後にTABヘッダーへ反映されます。

### 3. MC Node Dashboard(任意)

`scripts/mc_dashboard.ps1` は依存ゼロの HttpListener 製Webダッシュボードです。
上と同じ手順で `MCServer-Dashboard` タスクとして登録すると、
`http://<サーバーIP>:8787/` で K8s風のダークテーマUI(Node Health / Workload: minecraft-server /
Log Tail)が見られます。LAN外部には出しません(ファイアウォールで 192.168.1.0/24 のみ許可推奨):

```powershell
New-NetFirewallRule -DisplayName 'MCServer Dashboard' -Direction Inbound -Protocol TCP `
  -LocalPort 8787 -RemoteAddress 192.168.1.0/24 -Action Allow
```

温度は環境により取得できないことがあります(Hyper-V/VBS 有効なマシンでは CPU温度MSRが
読めないため「n/a」と表示されます。CPU使用率・RAMは通常通り取得できます)。

---

## ビルド

### 方法A: ModDevGradle(推奨・再現性あり)

```powershell
# Java 21 (JDK) が必要
git clone https://github.com/motchii709/hwtab.git
cd hwtab
gradle build
# → build/libs/hwtab-1.0.0.jar
```

### 方法B: javac 直 Jar(Gradle不要)

NeoForgeの実行時クラスは **パッチ済み `neoforge-<ver>-server.jar`** に含まれるため、
これをクラスパスの先頭に置くのがポイントです(`libraries/net/neoforged/neoforge/<バージョン>/`)。

```powershell
# サーバーの libraries フォルダがある場所で実行例
$nserver = 'C:\Path\To\MCServer\libraries\net\neoforged\neoforge\21.1.234\neoforge-21.1.234-server.jar'
$srv     = 'C:\Path\To\MCServer\libraries\net\minecraft\server\1.21.1-20240808.144430\server-1.21.1-20240808.144430-srg.jar'
$uni     = 'C:\Path\To\MCServer\libraries\net\neoforged\neoforge\21.1.234\neoforge-21.1.234-universal.jar'
$libs    = (Get-ChildItem -Recurse 'C:\Path\To\MCServer\libraries' -Filter *.jar | % FullName) -join ';'

javac -g --release 21 -encoding UTF-8 `
  -cp "$nserver;$srv;$uni;$libs" `
  -d out src\main\java\dev\motch\hwtab\HwTabMod.java

jar --create --file hwtab-1.0.0.jar -C out . -C src\main\resources .
```

> ※ `setTabListHeader` / `getAverageTickTimeNanos` / `tickRateManager` は
> NeoForgeパッチ済み server jar にしか存在しないため、素の vanilla `server-*.srg.jar` だけでは
> コンパイルできません(実際に確認済み)。

## 既知の制限

- **温度が取得できない環境がある**: Hyper-V / VBS(コア分離メモリ整合性)有効の Windows では
  CPU温度 MSR がブロックされ、LibreHardwareMonitor でも `null` になります。
  その場合ヘッダー・ダッシュボードとも温度は n/a 表示です(タスク記載の `MSAcpi_ThermalZoneTemperature`
  非対応マシンも同様)。
- **1秒ごとにファイルI/O**: `hw_stats.txt` の書き換えはアトミック(tmp → move)なので
  読み取り側が壊れることはありませんが、RAMディスク等に移すことも可能です。
- **フッター非対応**: BetterTab 等と同居させるため、HwTab はヘッダーのみを扱います。

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。
