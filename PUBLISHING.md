# Modrinth公開用データ(HwTab)

このドキュメントは Modrinth へのアップロード時にそのまま使えるメタデータと説明文です。
実際のアップロードはアカウント操作が必要なため、本リポジトリでは準備のみを行っています。

## 基本メタデータ

| 項目 | 値 |
|---|---|
| Title | HwTab |
| Slug | `hwtab` |
| Summary | Hardware stats (RAM / JVM heap / CPU / temperature) in your TAB list header. Server-side only, vanilla clients welcome. |
| Categories | `server`, `utility` |
| Environment | **Server** only (client: unsupported) |
| License | MIT |
| Version | 1.0.0 |
| Game versions | 1.21, 1.21.1 |
| Loaders | NeoForge(21.1.0 以上) |
| File | `hwtab-1.0.0.jar` |

## Body(そのまま貼り付け可 / Markdown)

---

**HwTab** は、NeoForge 1.21.x 専用サーバーで動作するサーバーサイドmodです。
サーバーマシンのハードウェア状態を **TABリストのヘッダー** にリアルタイム表示します。

```
RAM 15.2/15.7GB | JVM 3.4/6.0GB | CPU 22% | 62C
```

### 特徴

- 🖥️ **RAM / JVMヒープ / CPU / CPU温度** を1秒ごとに更新
- 🌡️ 温度は 70°C超で黄色、85°C超で赤に変化
- 🔌 **クライアント導入不要** — バニラクライアントのまま参加可能
- 🤝 BetterTab など **フッター系modと共存可**(ヘッダーのみ使用)
- 🛡️ 例外はすべて握り潰す設計で、modが原因でサーバーが落ちない
- 📊 同梱スクリプトで **TPS/MSPT/プレイヤー数** も発布し、Kubernetes風Webダッシュボード(:8787)から参照可能

### 導入

1. `hwtab-1.0.0.jar` をサーバーの `mods/` に入れて再起動
2. (任意)[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) を `hwtools/` に置き、
   リポジトリ同梱の `hw_stats_loop.ps1` をスケジュールタスクで常駐させると RAM/CPU/温度が表示されます
   (詳細は [GitHub README](https://github.com/motchii709/hwtab) を参照)

何も設定しなくても **JVMヒープ使用量だけは常に表示** されます。

### 既知の制限

- Hyper-V / VBS 有効環境ではCPU温度センサーが読めず、温度表示が n/a になります
  (CPU使用率・RAM・JVM・TPS/MSPT は通常通り取得できます)
- 温度・RAM・CPUは外部スクリプト(`hw_stats_hw.txt`)経由の値です。スクリプト未設定時は該当項目が非表示になります

### 技術詳細

- modが `hw_stats_hw.txt`(ハードウェア値)を読み込み、サーバー側の値(`server.getAverageTickTimeNanos()` /
  `tickRateManager()` / プレイヤー数 / MXBeanヒープ)とマージして `hw_stats.txt` としてアトミックに再発布します
- 30秒以上更新のないハードウェアファイルは自動で n/a 扱い
- NeoForge 21.1.234 / Minecraft 1.21.1 で実機検証済み

---

## アップロード手順(参考)

1. Modrinth にログイン → Dashboard → **Create a project**
2. Slug: `hwtab`(検索済み・空き確認済み)/ License: MIT / Categories: server, utility
3. Versions → **Create a version**:
   - Version number: `1.0.0`
   - Channel: release
   - Game versions: 1.21, 1.21.1
   - Loaders: neoforge
   - Files: `hwtab-1.0.0.jar`
   - Primary file の環境: **Server**
4. Body に上記Markdownを貼り付け(画像は後日ゲーム内TABのスクリーンショットを追加)
