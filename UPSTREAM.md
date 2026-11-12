# 上游來源與授權

| 項目 | 已核對的內容 |
|---|---|
| 上游專案與作者 | [AFAlimru/fastly-hosts-adjust](https://github.com/AFAlimru/fastly-hosts-adjust) |
| 移植參考版本 | 上游程式的 `VERSION` 為 `0.8.3`。固定[提交](https://github.com/AFAlimru/fastly-hosts-adjust/commit/336e105f71b8fce123d5bfdc9f635b9b8d500d0b) 於 2026-10-11T13:32:06Z，完整 SHA 為 `336e105f71b8fce123d5bfdc9f635b9b8d500d0b` |
| 參考檔案 | [Python 主程式](https://github.com/AFAlimru/fastly-hosts-adjust/blob/336e105f71b8fce123d5bfdc9f635b9b8d500d0b/fastly_hosts.py) · [上游測試目錄](https://github.com/AFAlimru/fastly-hosts-adjust/tree/336e105f71b8fce123d5bfdc9f635b9b8d500d0b/tests) |
| 上游授權 | MIT，Copyright (c) 2026 AFAlimru。包內的[原文](licenses/fastly-hosts-adjust-MIT.txt)與[該提交的 LICENSE](https://github.com/AFAlimru/fastly-hosts-adjust/blob/336e105f71b8fce123d5bfdc9f635b9b8d500d0b/LICENSE)相同，Git blob 為 `d5c34a8fbc641526d297a1009db7f3164eadc182` |
| 移植版授權 | [LICENSE](LICENSE) 收錄 MIT 條文，以及 AFAlimru、Fastly Hosts RouterOS contributors 兩行著作權聲明 |
| 分發說明 | 複製或再分發本軟體或其重要部分時，隨附原著作權與許可聲明。若另提供可下載安裝器，請把安裝器與 LICENSE 一起交付。專案包已包含全文與[署名資訊](NOTICE)。[MIT 條文](https://opensource.org/license/mit) |

移植取用服務與尾碼對照、候選探索、POP 辨識、排名和 X 借用 GitHub 測速結果等設計。RouterOS 版另外實作 Fetch、Netwatch、具擁有者標記的 DNS A 紀錄、交易復原、狀態檔、原生自我測試與排程。套件內的 Python 是本機開發工具及參考模型。完整上游 Python 應用、執行檔、CHR 映像與第三方測速資產均由其原發行者提供，未收錄於此套件。[移植對照](docs/FEATURE-PARITY.md)

## 技術參考

- RouterOS 的腳本執行權限、Fetch 憑證與回應格式、檔案及 Netwatch。[Scripting](https://help.mikrotik.com/docs/spaces/ROS/pages/47579229/Scripting) · [Fetch](https://help.mikrotik.com/docs/spaces/ROS/pages/8978514/Fetch) · [Files](https://help.mikrotik.com/docs/spaces/ROS/pages/2555971/Files) · [Netwatch](https://help.mikrotik.com/docs/spaces/ROS/pages/8323208/Netwatch)
- RouterOS 的靜態 A／AAAA 查詢與本機、轉送封包的差異。[DNS](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS) · [Packet Flow](https://help.mikrotik.com/docs/spaces/ROS/pages/328227/Packet+Flow+in+RouterOS)
- Fastly 提供網段清單，並說明 `X-Served-By` 可能含多個快取伺服器、僅反映回應當時資訊。[IP 清單](https://api.fastly.com/public-ip-list) · [X-Served-By](https://www.fastly.com/documentation/reference/http/http-headers/X-Served-By/)

本移植版的支援範圍與原生驗收狀態見[專案說明](README.md)。
