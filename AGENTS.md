# 維護指引

- 本專案使用 agent-kit 輔助維護。主代理負責實作、整合與驗證。
- 功能從 `routeros/` 的手寫來源修改。安裝器及命令包裝腳本由 `tools/build.py` 產生。
- 日常驗證只執行 `python tools/check_rsc.py`。需要重建或打包時，參閱[維護說明](docs/MAINTAINING.md)。
- 公開變更記入 `CHANGELOG.md`。詳細工作紀錄、設備輸出與 agent-kit 任務檔保留在本機。
