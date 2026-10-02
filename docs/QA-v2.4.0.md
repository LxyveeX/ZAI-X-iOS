# v2.4.0 發版紀錄

日期：2026-10-02。版本：`2.4.0+24000`。狀態：[已正式發布](https://github.com/funkeyyou/zaimanhua/releases/tag/v2.4.0)，發布時間 14:02:07（UTC+8）。

範圍：使用者等級頁與題庫認證 AI 一鍵答題。對外說明見 [版本說明](releases/v2.4.0.md)。

## 本機驗證

- analyze：0 error／0 warning（13 則既有 info）；225 項測試全部通過（新增 13 項）。
- 接口：等級頁讀 `/v1/u_center/user_level/info`。題庫認證是官方 H5（`user-auth.zaimanhua.com`），依其前端改走 account-api 的 `/v1/auth/prepare`、`/v1/auth/question_list`、`/v1/auth/post`、`/v1/auth/review`。考卷 50 題、限時 30 分鐘，`correct_option` 一律為空；交卷內容是 `{題目 id: "A" 或 "A,C"}` 的 JSON 字串，與官方前端（uni-app 預設以 JSON 送出 POST）相同。
- AI 答題：以假資料測試考卷與成績解析、交卷字串、選項字母的各種寫法、單選只取一個、書名號擷取與站內資料附註、低把握題以較高思考程度複查、請求失敗重試，以及少數題缺答時補猜、缺太多時不交卷。
- MuMu（Android 15）：以本機正式簽名包實測入口、等級頁、AI 作答（約 1 分 47 秒，複查 14 題）、交卷前檢查畫面與倒數，以及離開確認；放棄的考卷經 `/v1/auth/review` 確認沒有留下成績，`prepare` 仍可作答。之後使用者自行交卷過關，帳號升為 Lv5。
- 繁體介面：新文字已重新產生整句對照表。「通過」在逐字轉換會變成「透過」，介面改用「過關」。

## 候選版

- 候選 CI 36968700486：分析、測試、Android／Windows 建置全部通過；兩個平台的「Prepare AI defines」都寫入混淆後的設定，日誌搜不到 Key、網址或模型名稱明文。
- 使用者以 MuMu 實測同一份程式碼並交卷過關後同意發布。

## 發布檢查

- Tag `v2.4.0` 指向 `ed8cf611256cc824553ab3fc0cd464d2220edca3`，`zaimanhua` 主分支以快轉合併到同一提交。
- 正式建置前先以同名 tag 建立 Release 草稿，CI 產物上傳到草稿，核對後才公開。
- [正式 CI 36969568285](https://github.com/funkeyyou/zaimanhua/actions/runs/36969568285)：分析、測試、Android／Windows 建置及資產上傳全部成功。
- 正式 APK／ZIP 下載到 `build/release-2.4.0/current/`，大小及 SHA-256 與 GitHub Release 的 digest 完全一致。
- 正式 APK：套件 `com.xycz.zmhx`，versionName 2.4.0、versionCode 24000，名稱「再漫画X」，簽章 SHA-256 `4e2f84076e0c2a4361a8b23d9678b58b763bb43ecd45f437aa9bd0acd018b222` 與 v2.3.0 相同；三種架構的 `libapp.so` 都沒有 Key、網址或模型名稱明文。MuMu 覆蓋安裝並啟動，程序持續執行，沒有崩潰紀錄或 E/flutter，「我的」頁顯示 Lv.5。
- 正式 Windows ZIP：57 個檔案，EXE ProductVersion `2.4.0+24000`，`app.so` 沒有明文設定。
- 匿名 latest API 直連與經 gh-proxy 都回傳 v2.4.0（非草稿、非預發布），含兩個資產的 SHA-256 digest；經 gh-proxy 下載 ZIP 約 5 秒。Release 標題為「再漫畫X v2.4.0」。
- 舊版 v2.3.0 的 APK／ZIP 已備份在 `build/release-2.3.0/current/`，刪除前再次核對大小及 SHA-256；舊 Release 已移除、tag 保留，下載頁僅保留最新版。
- 候選版臨時分支 `codex/release-2.4.0` 與候選 CI 36968700486 已清理；正式 tag、CI、本機產物及備份保留。

| 資產 | bytes | SHA-256（GitHub digest） |
| --- | ---: | --- |
| ZAI-X-android.apk | 92939451 | `e941eab88fd480208e53f1376a6d0c7bd3977e3031b5e07c857d667ed27eed77` |
| ZAI-X-windows-x64.zip | 32091479 | `6ce39ed0b9ac9caa281f9f2c27e7cb829dcab4551f1d2681380ae29d59900c01` |

## 驗證限制

- 官方不公布正確答案，AI 的正確率只能從交卷分數判斷；本輪只有使用者的一次正式交卷（過關），沒有多份考卷的統計。
- 每日 5 次上限的提示與斷網時的錯誤畫面未在裝置上觸發；次數計算沿用 AI 搜尋已有單元測試的同一函式。
- Windows 版沒有實機開啟等級頁與答題頁；功能是共用的 Dart 程式碼，由正式 CI 建置與單元測試涵蓋。
- AI 服務設定與 v2.3.0 相同：Key 隨公開安裝包發布，混淆只防止倉庫與一般字串搜尋外洩；服務端已限制為低階模型並設有用量上限。
