# 重建與驗證

## 日常檢查

在專案根目錄用 Python 3.12 或更新版本執行 RouterOS linter。它只使用標準函式庫，結束碼為 0 即通過。手動 GitHub Actions 也執行這條指令。

```text
python tools/check_rsc.py
```

## 按需重建與打包

需要產生安裝器和來源 ZIP 時，在專案根目錄執行以下指令。

```text
python tools/build.py
python tools/package.py
python tools/package.py --verify dist/fastly-hosts-routeros-1.0.0.zip
```

若要核對分發內容，可將 ZIP 解壓到空目錄，在解壓出的 `fastly-hosts-routeros` 內執行 `python tools/package.py --check-tree`。ZIP 固定了成員順序、時間與權限。壓縮函式庫可能影響 ZIP 整體位元組，解壓後的內容可用 `SHA256SUMS` 逐檔比對。

## 檔案分工

| 路徑 | 用途 |
|---|---|
| `routeros/FHR-{config,core,storage,network,benchmarks,discovery,dns,engine,commands,selftest}.rsc` | 十份手寫來源。設定內的 `version` 同時提供產生器使用 |
| `tools/build.py` | 產生載入器、命令包裝、說明、診斷、移除與多檔安裝器共 14 份，以及根目錄單檔安裝器 |
| `manifests/embedded-sources.json` | 23 支內嵌腳本的 SHA-256。測試會解碼安裝器並比對獨立模組 |
| `manifests/runtime.sha256` | 此版本的 24 份 RouterOS 模組與單檔安裝器基準。打包器另外固定清單及安裝器的雜湊 |
| `tools/package-files.txt` | 逐檔列出分發內容。打包器另加入 `SHA256SUMS`，輸出到 `dist/` |
| `tests/` | Python 參考模型、回歸測試與隔離 CHR 驗收腳本 |

準備新的原生程式版本時，重建後檢查差異，再更新候選版本的雜湊基準。日後進行 CHR 測試時，從待驗 ZIP 取出安裝器，將其 SHA-256 與測試結果一併記錄。[CHR 測試步驟](../tests/CHR.md)
