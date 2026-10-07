# ZAI-X iOS · 個人自用適配

基於 [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua) 的再漫畫X，為個人 iPhone / iPad 使用補充平台適配與 IPA 建置。保留公開 fork，依個人需要更新。

[下載 IPA](https://github.com/LxyveeX/ZAI-X-iOS/releases) · [简体中文](README.md) · [English](README.en.md)

## 狀態與安裝

**目前為預覽版，尚未完成實機測試。** 2.4.1 已通過 225 項測試、iOS Release 編譯與 iPad 模擬器首次啟動檢查；iPadOS 16.7 上的簽名安裝、登入及完整閱讀流程仍待實機驗證。

在 Releases 的 **Assets** 下載未簽名 `.ipa`，匯入自己的簽名工具，使用有效憑證與描述檔簽名後安裝。最低系統要求為 **iOS / iPadOS 15.0**，應用程式識別碼為 `com.lxyveex.zaix`，可與舊版並存。首次使用需重新登入；舊版的本機下載、設定及未同步紀錄不會自動移轉。

每次 **Build iOS IPA** 成功後會自動建立獨立的預覽版 Release，保存 IPA、SHA-256、建置資訊及 iPad 啟動截圖，並保留先前版本。預覽版請在 Releases 手動下載；目前 App 的「檢查更新」只讀取正式版。

## 適配範圍

沿用上游分類、專題、書架、下載與雙頁閱讀，補充分類首次載入修正、iOS 工程與外掛整合、iPad 分享彈窗、照片權限及背景任務註冊。上游私有 AI 服務設定未包含於此建置，相關入口保持隱藏；iOS 背景更新由系統排程。

完整安裝與建置方式見 [iOS 說明](docs/IOS.md)，測試範圍見 [驗證紀錄](docs/IOS_VALIDATION.md)。

## 來源與授權

適配基礎為 [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua) v2.4.0；再漫畫接口遷移來自 [Fusn126/ZAI_X](https://github.com/Fusn126/ZAI_X)，原始專案為 [xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj/tree/zaimanhua)。保留原作者及貢獻者署名，原始碼沿用 [GPL-3.0](LICENSE)。

上游完整介紹及 Android / Windows 版本見 [上游倉庫](https://github.com/funkeyyou/zaimanhua)。本專案為社群第三方客戶端；作品內容與圖片的著作權屬於相應權利人。
