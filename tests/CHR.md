# 在隔離 CHR 驗收

使用可還原快照的 CHR 7.24.5 x86_64，先限制對外連線。下面的腳本會改動測試機的 DNS、排程與檔案。每種情境從獨立快照開始，所用安裝器取自待交付 ZIP，先與 `manifests/runtime.sha256` 比對。

1. **安裝與重新匯入。** 匯入 `FHR-install-all.rsc`，核對 `SELFTEST PASS: 47`、`INSTALLED 1.0.0`、23 支腳本、既有設定與排程狀態。重複匯入後比對物件數及設定。再從有既有設定、DNS 和排程的快照測原地更新。
2. **排程整合。** 在已安裝的快照，把 `chr-integration.rsc` 上傳為 `integration.rsc`，匯入 `chr-scheduled-integration.rsc`。等排程真正觸發後核對 `LAB SCHEDULED INTEGRATION PASS: 20`、外來 A／AAAA、交易回復與鎖。此測試使用固定的網路回應。
3. **權限與狀態。** 匯入 `chr-limited-read.rsc` 測試不足權限時的讀取。在另一份快照，將 `chr-storage-guards.rsc` 的內容裝入 LAB 腳本，宣告 `ftp,read,write,policy,test,sensitive`，以 `use-script-permissions` 執行。查看 `LAB LIMITED READ PASS` 與 `LAB STORAGE GUARDS PASS`，並核對主檔與前一版副本。
4. **既有排程資料。** 在另一份測試安裝中匯入 `chr-scheduler-prepare.rsc`，待一次性的 LAB 排程以受限權限執行。原地匯入候選安裝器，再匯入 `chr-scheduler-verify.rsc`。等新的排程觸發後，讀回八筆 DNS、健康狀態及副本，檢查鎖。
5. **正式週期與開機。** 讓正式的 `FHR.auto` 與 `FHR.health` 跑過完整週期，再重新開機觀察 `FHR.boot`。比較實際 DNS、狀態備份與殘留工作。另從獨立快照測中斷復原、`FHR.restore` 和 `FHR.uninstall`。

真實路線與下載表現從用戶端另外量測，記錄解析器、IP 版本、出口、實際遠端 IP、傳輸大小及用時。[用戶端核對方式](../docs/OPERATIONS.md)
