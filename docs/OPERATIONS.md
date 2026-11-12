# 使用、診斷與回復

## 安裝與更新

安裝或更新前，先備份設備並在隔離 CHR 驗證。上傳根目錄的 `FHR-install-all.rsc`，在 WinBox Terminal 執行一次匯入。安裝器先解析內嵌來源、核對同名腳本與排程的擁有者標記，再寫入 23 支腳本並以宣告權限執行自我測試。已辨識的 FHR 排程及符合舊版 v0.4 名稱與註解的排程會先停用。

```routeros
/import file-name=FHR-install-all.rsc
```

看到 `SELFTEST PASS: 47` 與 `INSTALLED 1.0.0` 後，依以下適用的情境操作。

**全新安裝。** 先依需要調整已啟用服務與排除地區，再第一次套用。從用戶端確認效果後，可選擇啟用排程。

```routeros
/system script run FHR.apply
/system script run FHR.status
```

**已有受管理的 DNS。** 匯入後，先執行 `/system script run FHR.doctor` 核對現有 DNS 和排程。若這台設備原本需要自動維護，再執行以下兩條命令恢復排程並確認狀態。

```routeros
/system script run FHR.enable-schedule
/system script run FHR.status
```

遇到匯入錯誤時先保留日誌，確認哪些腳本已建立、排程是否已停用，再處理指出的錯誤並重新匯入。下列查詢可用於檢查現況。

```routeros
/system script print detail without-paging where name~"^FHR[.]"
/system scheduler print detail without-paging where name~"^FHR[.]"
/ip dns static print detail without-paging where comment~"^FHR:auto:"
/log print without-paging where topics~"script"
```

輸出可能含本機管理資訊。對外開 issue 時只摘錄相關版本、階段、錯誤與匿名化片段；帶簽章的 Release 網址只留主機與路徑類型。

## 服務與設定

需要帶參數時，在同一個 Terminal 工作階段執行 `/system script run FHR.load` 及 `:global FHR`，再執行需要的動作。各列是獨立範例。

| 目的 | 指令或操作 |
|---|---|
| 先測 GitHub，再決定是否套用 | `$FHR action="test" service="github"`；檢查輸出後，另行執行 `$FHR action="apply" service="github"` |
| 查看快取、重新探索 | `$FHR action="list" service="github"`；`$FHR action="scan" service="github"` 會重掃並更新快取 |
| 單次指定地區 | `$FHR action="region" service="github" region="NRT"` 重新探索並套用；`$FHR action="switch" service="github" region="NRT"` 使用快取重驗再套用 |
| 每次只選指定 POP | `$FHR action="set" property="region" value="NRT"`，恢復跨區選擇時將 `value` 設為空字串 |
| 調整排除地區 | `$FHR action="set" property="excluded" value="\|SIN\|QPG\|"`。單獨一個直線符號表示空集合；指定的地區仍需探測成功 |
| 降低測量負擔 | `$FHR action="set" property="shortlist" value=4`、`$FHR action="set" property="rounds" value=2`；下輪每個獨立測速服務的樣本目標可降到 64 MiB，加上探索等流量 |
| 要求有下載樣本的候選 | `$FHR action="set" property="allowLatencyFallback" value=false`；X 的樣本仍來自 GitHub |
| 停用／啟用 Twitch | `$FHR action="disable" service="twitch"` 會還原該服務的 DNS，`$FHR action="enable" service="twitch"` 讓它參與下次一般套用 |
| 加入自訂網域 | `$FHR action="add" domain="files.pythonhosted.org"`。會檢查當時的 A、Fastly 網段和 HTTPS；可附同主機、實際存在的 `url` 作為測速物件 |
| 調整自訂服務 | `set-test-url` 設定測速網址，`set-probe-path` 設定探測路徑。可用 `$FHR action="remove" service="custom.files.pythonhosted.org"` 還原並移除該項 |
| 版本資訊 | `$FHR action="check-update"` 查詢原 Python 專案的 Release。RouterOS 移植版由發布者另行分發並手動匯入 |

初次安裝若只想看單一服務，可使用帶 `service` 的命令。排程跑的是整組已啟用服務。預設的 `test` 和 `scan` 不主動提交新選擇，但會寫入狀態、使用暫時探測項目；公共入口也會先復原未完成的舊 DNS 交易。包括 `FHR.status` 在內，凡經過該入口的動作都可能觸發復原。若要求只查現況，執行 `FHR.doctor` 或上方的 `print` 指令。

## 怎麼判讀 404 與選點結果

| 發生階段 | FHR 的判定 |
|---|---|
| 內建主要探測 | GitHub Raw README、X 圖片、Twitch 圖片需要 Fetch 成功且 HTTP 為 2xx／3xx，還須有合格 POP。HTTP 404 會淘汰該候選。Twitch 另讀 `k.twitchcdn.net` 的標頭取得 POP。 |
| 自訂服務的一般入口 | 預設 `anyStatus=true`，可接受 HTTP 200–499；之後仍檢查主要 POP。 |
| 寫入前的一般別名 | 收到 200–499 可通過 HTTP 這一關，包括某些 API 根路徑的 403／404／405。已知但不符政策的 POP 會被拒絕，未知別名 POP 可以通過。 |
| 別名正好是本次測速資源 | 最後預檢要求 2xx。測量準備與取樣另有條件，HEAD 要求 200；整檔 GET 期待 200，分段 GET 期待 206，並檢查完成與下載量。 |
| 已有資源但取樣全部失敗 | 不能因為勾選了 `allowLatencyFallback` 就推論成功。進入取樣流程後需要至少一筆有效樣本；無合格候選時保留原有 DNS。 |

`APPLIED` 表示已寫入該服務的 A；`KEPT DNS` 是原有選擇仍合格；`NO CHANGE` 通常表示無合格候選；`SERVICE FAILED` 需看服務與原因。只有下載錯誤一行時，無從判斷是被容許的別名探測、失效的外部資源，還是該次選點失敗。請對照同時段 `SERVICE`、`BENCHMARK`、`SAMPLE`、`RESULT` 和實際 DNS 狀態。

## 怎樣確認電腦真的用到該入口

1. 在 Windows 用平常的解析路徑查 A 與 AAAA，再用 `-Server` 指定路由器 DNS 比對。如果平常使用 Pi-hole／SmartDNS，確認這些名稱的 A 查詢會送到能回答覆寫的那一層。兩邊互相轉送相同名稱會造成循環。
2. 用相同資源開一條新的下載連線，記錄遠端 IP、IP 版本、實際 WAN／VPN、HTTP 狀態、下載位元組與耗時。有 GitHub 重新導向時，應檢查最後提供資產的主機；API、首頁及根路徑的 HEAD 無法代表大檔下載速度。
3. 在多 WAN 上，路由器發起的 Fetch 走本機輸出，電腦流量則經過轉送與 `prerouting`。以實際 mangle、路由及 VPN 規則計數核對兩者；若出口不同，請將結果分開記錄。這套工具只調 DNS，不接手既有的 GitHub VPN 規則。

以下 PowerShell 在互動時輸入本機參數，毋須把私有 IP 或短效簽章網址寫進文件。最後一段實際下載指定資源，請選大小合適且可公開存取的測試檔。

```powershell
$name = 'release-assets.githubusercontent.com'
$routerDns = Read-Host '路由器的 DNS 位址'
Resolve-DnsName $name -Type A
Resolve-DnsName $name -Type AAAA
Resolve-DnsName $name -Type A -Server $routerDns
Resolve-DnsName $name -Type AAAA -Server $routerDns

$assetUrl = Read-Host 'GitHub Release 公開資產網址'
curl.exe -4 -L -sS -o NUL -w 'HTTP=%{http_code} IP=%{remote_ip} bytes=%{size_download} seconds=%{time_total} Bps=%{speed_download}\n' $assetUrl
```

要觀察 APP 平常的雙協定選擇，另跑一次不帶 `-4` 的下載並記錄實際 IP。瀏覽器有獨立 DoH 時需另外核對它的連線。測試公開報告應移除帶簽章的查詢字串。

## 停止、回復、移除

| 目的 | 命令與結果 |
|---|---|
| 暫停後續自動操作 | `/system script run FHR.disable-schedule`。既有選點通常繼續使用；正在執行的工作需另查 `/system script job print` |
| 回到某服務上次的選點 | `$FHR action="rollback" service="github"`。有舊選點時先重驗；無舊選點時還原該服務 |
| 回到接管前 DNS 並停用排程 | `/system script run FHR.restore`。曾接管舊紀錄時會還原那些紀錄 |
| 清除設定和快取、保留腳本 | `/system script run FHR.purge`。會先還原 DNS |
| 完整移除 | `/system script run FHR.uninstall`。先 purge，再刪自有腳本和排程；手動上傳檔可自行管理 |

若狀態毀損或有忙碌鎖，保留主檔、`.prev` 與錯誤日誌，先檢查工作和排程。不要用 purge 當更新步驟。要回到舊程式版本時，請依相容的路由器備份或該版已驗證的更新程序操作；`rollback` 只切換服務選點。
