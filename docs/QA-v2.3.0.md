# v2.3.0 發版紀錄

日期：2026-09-30。版本：`2.3.0+23000`。狀態：[已正式發布](https://github.com/funkeyyou/zaimanhua/releases/tag/v2.3.0)，發布時間 13:02:20（UTC+8）。

範圍：漫畫與輕小說 AI 搜尋、專題合集與專題詳情改用新接口（#3）及其他小幅調整。對外說明見 [版本說明](releases/v2.3.0.md)。

## 本機驗證

- analyze：0 error／0 warning（13 則既有 info）；212 項測試全部通過。
- AI 搜尋：以假資料測試理解需求、代表作只收本傳（畫集、外傳不算）、候選交錯排序與分批挑選、「找更多作品」不重送已讀候選、某批失敗留到下一輪，以及整批失敗時改列候選；另以真實接口實測「女主很強的奇幻冒險」，第一輪挑出 14 部（修正前 5 部），再按一次「找更多作品」多 9 部，約 15 秒。
- AI 服務設定：`tools/ai/make_ai_defines.dart` 以每次不同的隨機遮罩混淆後注入；缺少或損壞的設定會隱藏 AI 功能。倉庫、提交內容、建置參數檔、CI 日誌及 APK／Windows 的 `app.so` 都搜不到 Key、網址或模型名稱明文。
- 專題（#3）：`/app/v1/subject` 已 404，改走 `/api/v1/zt/h5/list` 與 `/api/v1/zt/h5/detail`。以真實接口逐一解析 57 個專題、2,840 筆收錄作品，全部成功；略過 1 筆重複及 3 筆官方詳情與本地索引都查不到書名的失效條目。專題合集與詳情頁在 360、840、1180 寬及繁體 1.8 倍字下沒有溢位，手機一欄，折疊機與平板並排。
- MuMu（Android 15）覆蓋安裝本機正式簽名包並啟動，程序持續執行，沒有崩潰紀錄或 E/flutter；AI 搜尋的漫畫與輕小說結果、繁體介面、搜尋紀錄分開保存已實測，使用者試用後決定保留。

## 候選版

- [CI 36667170300](https://github.com/funkeyyou/zaimanhua/actions/runs/36667170300)：分析、測試、Android／Windows 建置全部通過；兩個平台的日誌都顯示已寫入混淆後的 AI 設定，沒有明文。
- Android 候選版 2.3.0（23000），簽章與前版相同；Windows 候選版 `2.3.0+23000`、57 個檔案，可正常開啟，視窗標題「再漫畫X」。使用者驗收後同意發布。

## 發布檢查

- Tag `v2.3.0` 指向 `390aa1589b28faebdff72a7c34c123f12b9e91ec`，`zaimanhua` 主分支以快轉合併到同一提交。
- 服務設定存於 repo secret `ZAI_AI_CONFIG`；正式建置前先以同名 tag 建立 Release 草稿，CI 產物上傳到草稿，核對後才公開。
- [正式 CI 36668626032](https://github.com/funkeyyou/zaimanhua/actions/runs/36668626032)：分析、測試、Android／Windows 建置及資產上傳全部成功；兩個平台的「Prepare AI defines」都寫入混淆後的設定。
- 正式 APK／ZIP 下載到 `build/release-2.3.0/current/`，大小及 SHA-256 與 GitHub Release 的 digest 完全一致。
- 正式 APK：套件 `com.xycz.zmhx`，versionName 2.3.0、versionCode 23000，名稱「再漫画X」，簽章 SHA-256 `4e2f84076e0c2a4361a8b23d9678b58b763bb43ecd45f437aa9bd0acd018b222` 與 v2.2.0 相同；三種架構的 `libapp.so` 都沒有 Key、網址或模型名稱明文。MuMu 覆蓋安裝並啟動，程序持續執行，沒有崩潰紀錄或 E/flutter。
- 正式 Windows ZIP：57 個檔案，EXE ProductVersion `2.3.0+23000`，`app.so` 沒有明文設定。
- 匿名 latest API 直連與經 gh-proxy 都回傳 v2.3.0（非草稿、非預發布），含兩個資產的 SHA-256 digest；經 gh-proxy 下載 ZIP 約 3 秒。Release 標題為「再漫畫X v2.3.0」。
- 舊版 v2.2.0 的 APK／ZIP 已備份在 `build/release-2.2.0/current/`，刪除前再次核對大小及 SHA-256；舊 Release 已移除、tag 保留，下載頁僅保留最新版。
- 候選版臨時分支 `codex/release-2.3.0` 與候選 CI 36667170300 已清理；正式 tag、CI、本機產物及備份保留。

| 資產 | bytes | SHA-256（GitHub digest） |
| --- | ---: | --- |
| ZAI-X-android.apk | 92708739 | `8cea22109c79965479f6459e1c8018bfd7ff8598b6e82037bd68ca52c29650b9` |
| ZAI-X-windows-x64.zip | 32039132 | `2c44f29c7d72a506888ca9fcb5dc3873ce9752ff125e071aa85159b4a7587ba6` |

## 驗證限制

- AI 搜尋的斷網錯誤畫面、每日 50 次上限的提示未在裝置上觸發；由單元測試涵蓋次數計算。
- 輕小說 AI 搜尋以 MuMu 實測兩句描述，未另外做大量描述的品質評估。
- 實體摺疊機與平板未在本輪重新驗收，版面由 widget 測試涵蓋。
- AI 服務的 Key 隨公開安裝包發布，混淆只防止倉庫與一般字串搜尋外洩；服務端已限制為低階模型並設有用量上限。
