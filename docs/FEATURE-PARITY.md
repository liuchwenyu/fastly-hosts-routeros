# 上游與 RouterOS 移植範圍

本表對照 fastly-hosts-adjust 0.8.3 與 FHR 1.0.0 的程式行為。實測範圍見[專案說明](../README.md)。

| 工作 | 上游 Python | RouterOS 實作 |
|---|---|---|
| 產生候選 | IPv4 網段、服務尾碼與已解析位址 | `FHRRanges`／`FHRDiscover` 按 /24 展開，依服務試尾碼並驗證。網段快照可備援；只有主要探測得到可辨識 POP 才能入選 |
| 探測與計時 | Python 多執行緒、socket、TLS／HTTP | `FHRParallel`／`FHRProbe` 用背景工作執行 HTTPS，再以暫時 Netwatch 測 TCP；不足時用有標示的 HEAD 請求時間 |
| GitHub | Raw 與 Release 共用路線，用 Release 大檔測量 | `FHRGitHubAsset`／`FHRSignedURL` 由公開 API 取得實際資產，更新短效網址，寫入前再檢查兩個完整網域 |
| X 圖片 | 以 GitHub 作為測速依據 | `FHREvaluateX` 重新驗證 X 的 .159、TLS 及與供體相同的 POP |
| Twitch | 五個主機、兩個尾碼，從首頁選 JS | `FHRTwitchAsset` 與服務設定處理 .214／.167。範圍限網頁及相關資源 |
| 其他網域 | 自訂 Fastly 網域與測速網址 | `FHRAddCustom` 驗證實際 A 與 Fastly 網段及 HTTPS，從位址辨識尾碼，可選同主機的下載物件 |
| 取樣與排序 | 串流讀取、輪替、順暢次數與中位數 | `FHRMeasure`／`FHRRank` 保留順序概念，採整體 Fetch 時間計算近似速率，取樣期間的數字不能與上游直接對換 |
| 選擇政策 | 上游有預設路線比較流程 | 此版預設排除 SIN／QPG，再從合格候選中選擇。順暢分數的 30% 是同輪相對門檻。另有目前入口的 20% 容差 |
| 變更名稱解析 | 修改本機 hosts 管理區塊 | `FHRCommit`／`FHRRestore` 更新路由器精確靜態 A，保存接管前快照與交易。生效範圍由查詢路徑、快取與應用程式選擇決定 |
| 日常操作 | test、apply、region、switch、list、restore、purge 等 | 以 RouterOS 命令提供；加入受限權限排程、健康檢查與上一選點回復。試選也會使用快取和復原機制 |
| 更新與介面 | 桌面／命令列、檢查或取得上游程式 | 以 CLI 與本機匯入交付。`check-update` 僅顯示 Python 上游版本。上游 GUI、EXE、自動替換執行檔與完整城市翻譯未移植 |

[固定提交、程式與授權](../UPSTREAM.md) · [RouterOS 架構](ARCHITECTURE.md)
