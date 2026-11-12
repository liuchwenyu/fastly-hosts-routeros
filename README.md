# Fastly Hosts RouterOS

Fastly Hosts RouterOS（FHR）是 fastly-hosts-adjust 的非官方 RouterOS 移植版。路由器從多個 Fastly IPv4 入口探測連線與下載表現，為使用這台 DNS 的用戶端更新指定網域的靜態 A 紀錄。[上游來源與授權](UPSTREAM.md)

**1.0.0 候選包。** 原生驗收目標是 RouterOS CHR 7.24.5 x86_64。這份安裝器尚待完成 CHR 的安裝、正式排程與重開機驗收。其他 RouterOS 版本、實體 ARM64 設備與不同 WAN／VPN 的下載表現也待實測。

| 服務 | 預設涵蓋範圍 |
|---|---|
| GitHub | `raw.githubusercontent.com`、`release-assets.githubusercontent.com` |
| X 圖片 | `pbs.twimg.com`。借用 GitHub 排名，再檢查 X 本身的 TLS 與快取節點（POP） |
| Twitch | 網頁、API 與靜態資源。直播影音和聊天室另走其他路徑 |
| 自訂 | 可驗證為 Fastly IPv4 的網域，可另設同主機的測速網址 |

## 安裝與試用

1. 先備份目標設備。在隔離 CHR，將根目錄的 `FHR-install-all.rsc` 上傳到 WinBox 的 Files，在終端執行下方匯入命令。路由器不需要 Python。
2. 等待 `SELFTEST PASS: 47` 及 `INSTALLED 1.0.0` 兩個標記。匯入會建立腳本、檢查狀態檔，並停用既有 FHR 排程。遇到錯誤先查腳本與排程現況。
3. 新裝可用 `FHR.doctor` 查看現況。準備切換 DNS 時執行 `FHR.apply`，核對用戶端實際解析與下載，再依需要啟用 `FHR.enable-schedule`。已有受管理 DNS 的設備，先核對既有紀錄與設定。[操作、更新與回復](docs/OPERATIONS.md)

```routeros
/import file-name=FHR-install-all.rsc
```

新建排程預設每六小時選一次入口，每十五分鐘檢查健康狀態。GitHub、Twitch 各跑滿 10 個候選、3 輪、每輪 8 MiB，下載樣本合計 **480 MiB／次**，另有探測與重試流量。用戶端若走 IPv6、獨立 DoH 或不同的 WAN／VPN，應在實際裝置上確認遠端 IP 與下載結果。[設定與資料流](docs/ARCHITECTURE.md)

## 維護

[重建與驗證](docs/MAINTAINING.md) · [隔離 CHR 驗收](tests/CHR.md) · [上游功能對照](docs/FEATURE-PARITY.md) · [版本紀錄](CHANGELOG.md)

本移植版採 MIT 授權，保留上游作者及移植貢獻者的署名。[LICENSE](LICENSE) · [NOTICE](NOTICE)
