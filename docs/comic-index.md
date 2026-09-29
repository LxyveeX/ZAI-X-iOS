# 本地漫畫索引與神隱作品

對應 issue：[#1 隱藏漫畫無法被搜尋](https://github.com/funkeyyou/zaimanhua/issues/1)、[#2 為無權限的漫畫載入資訊](https://github.com/funkeyyou/zaimanhua/issues/2)。

## 神隱作品的詳情與章節（#2）

v4api 會依請求參數 `_v`（官方 App 版本）決定要不要回傳隱藏作品。不帶或低於 2.2.x 時，詳情與章節一律回「漫画不存在或已被删除」；帶上 `_v=2.3.8` 後就能拿到完整章節列表，評論本來就不受限。

- 只有漫畫詳情 `/comic/detail/{id}` 與章節 `/comic/chapter/{comicId}/{chapterId}` 會帶 `_v`（`Api.APP_VERSION`）。實測一般作品加上後回應結構與內容不變。
- 能不能看圖仍由帳號權限決定：沒有權限時章節回 `canRead:false`、`page_url` 為空。閱讀器與下載會直接顯示「需要登入／等級不足」的說明，不再去等已失效的舊網頁介面。
- 詳情頁依 `canRead` 顯示權限提示，依 `hidden` 在狀態列標示「神隱」；「自動收藏神隱漫畫」設定因此重新生效（預設關閉）。

## 本地漫畫索引（#1）

官方 `/search/index` 不會回傳 `hidden=1` 的作品（實測全部搜不到），`copyright=1` 也有九成以上搜不到，另外還有少數兩者皆否卻搜不到的作品。所以另外維護一份全站作品清單，在 App 內本地搜尋。

```text
tools/comic_index/build_comic_index.dart ── 逐一讀取詳情（帶 _v）
        │
        ├─ assets/comic_index/        App 內建快照（第一次使用、連不上 GitHub 時用）
        └─ comic-index 分支            .github/workflows/comic_index.yml 每天更新（單一提交、強制覆蓋）
                │
                └─ App 下載到本機：依序試 raw.githubusercontent.com → gh-proxy.com 加速代理 → jsDelivr
```

- 每天台北時間 03:40 增量更新：只抓新 ID，加上輪替的 1/14 舊 ID（每本兩週重新確認一次，每天約 6,700 個請求、GitHub 上約 11 分鐘），內容沒變就不發布。手動執行 workflow 可選全量重抓。
- 正式打包（`build_release.yml`）建置前會換成 comic-index 分支的最新清單並核對筆數，取不到就沿用倉庫內快照。
- App 在搜尋漫畫時自動檢查更新：真的連上（已是最新或更新成功）後 24 小時內不再檢查；所有來源都連不上時，2 小時後再試。手機只在 Wi-Fi／有線網路時自動檢查（約 2.6 MB）。行動網路可到「我的 → 更多設定 → 漫畫 → 本地漫畫索引 → 檢查更新」手動更新，手動不受這些限制。
- 下載來源依序為 raw.githubusercontent.com、gh-proxy.com（第三方公益加速代理，在原網址前加上 `https://gh-proxy.com/`）、jsDelivr。單一來源讀 meta 超過 15 秒、下載超過 2 分鐘，或檔案大小、版本、筆數不符，就換下一個來源；全部通過才替換本機清單。
- 搜尋結果頂端顯示「官方搜索没有收录的作品」：官方結果還有下一頁時，只補神隱或 copyright=1 的作品；官方結果已完整（不足一頁）時，本地有、官方沒有的都補上；官方搜尋失敗時全部顯示。已出現在這個區塊的作品不會在官方結果重複列出。
- 比對會做繁轉簡（`lib/app/t2s_chars.g.dart`，由 `tools/i18n/gen_t2s.py` 從 OpenCC 產生）、全形轉半形、英文轉小寫並去掉空白與標點；以空白分隔的多個關鍵字須全部命中；依「標題相同 → 別名相同 → 標題開頭 → 標題包含 → 別名包含 → 作者」排序。
- 設定可關閉「搜索时补上官方未收录的作品」。

### 檔案格式

`comic_index.tsv.gz` 為 gzip 的 UTF-8 文字：

```text
#ZCI1\t<version yyyyMMddHHmm UTC>\t<generatedAt>\t<count>\t<maxId>
<id>\t<標題>\t<別名，以 | 分隔>\t<作者，以 / 分隔>\t<旗標>\t<狀態 0/1 連載/2 完結>\t<熱度>
```

旗標位元：1＝`hidden==1`（神隱）、2＝其他非 0 的 `hidden`、4＝`copyright==1`、8＝未登入不能閱讀、16＝`is_lock==1`。`comic_index.json` 記錄 version、count、bytes。

### 常用指令

```powershell
# 全量重抓（約 9 萬次請求；可中斷續跑）
dart run tools/comic_index/build_comic_index.dart --cache=$env:TEMP\comic_index_raw.jsonl --out-dir=assets/comic_index --floor=89000

# 增量（與 CI 相同）
dart run tools/comic_index/build_comic_index.dart --previous=assets/comic_index/comic_index.tsv.gz --rotate=14 --out-dir=$env:TEMP\comic_index_out --skip-unchanged

# OpenCC 更新後重建繁轉簡字表
python tools/i18n/gen_t2s.py
```

### 已知限制

- 旗標無法完全預測官方搜尋會不會回傳；官方結果超過一頁時，少數未標旗標、但官方搜不到的作品不會補上（輸入更完整的書名即可）。
- `_v` 的門檻由伺服器決定，日後若提高，需要同步調整 `Api.APP_VERSION` 與爬蟲的 `kAppVersion`。
- 本地結果的封面、題材、最新章節是顯示時才向詳情介面補抓，同時最多 3 個請求；展開後最多顯示 50 部。
- gh-proxy.com 是第三方公益服務，可能失效或被封鎖，失效時會改用 jsDelivr；經代理拿到的內容同樣要通過大小、版本與筆數檢查才會採用。

## 驗證紀錄（2026-09-29）

- 全量爬取 ID 1–89,500：有效 82,950 部（神隱 10,416、copyright=1 22,229），0 失敗；gzip 2.59 MB。增量（只抓新 ID）與輪替合併皆在套件外直接執行成功。
- 本機 analyze 0 error／0 warning（13 條既有 info），124 項測試通過（新增索引與神隱詳情共 20 項，含以內建索引實搜 48894、海賊王）。
- 本機 release APK 建置成功，MuMu 覆蓋安裝：搜尋「Naruto」頂端補上火影忍者等 3 部神隱作品；「OP」以別名把海賊王排第一，收合／展開與 50 部上限提示正常；火影忍者（570 話）詳情、評論正常，閱讀顯示等級不足說明；48894 在 Lv.4 帳號下可閱讀（第 01 話 38 頁）；設定頁顯示索引筆數與資料時間。日誌無 FATAL EXCEPTION、Unhandled Exception、RenderFlex 或 E/flutter。
- MuMu 線上更新：「檢查更新」在版本相同時顯示已是最新；資料分支換新版後可下載、驗證並替換，重開 App 後仍優先使用下載的版本。
- [CI 36545939679](https://github.com/funkeyyou/zaimanhua/actions/runs/36545939679)（功能分支手動觸發）：analyze、測試、Android／Windows 建置全部成功，兩個建置 job 都換上 comic-index 分支的清單。
- [comic-index 36547238935](https://github.com/funkeyyou/zaimanhua/actions/runs/36547238935)：GitHub runner 可連上 v4api，增量（rotate=7）掃 13,064 個 ID、0 失敗、約 22 分鐘，新增 1 部後發佈 82,951 部。
- 追加調整：每日更新改成 14 天輪一遍；App 改成真的連上才開始計時（全部失敗 2 小時後重試），下載來源加入 gh-proxy.com。新增 5 項測試（共 129 項通過），涵蓋 GitHub 連不上改走 gh-proxy、檔案不完整換來源、失敗不占用 24 小時額度。以 App 同一個 HTTP 套件實際經 gh-proxy 下載 comic-index：82,951 部，雜湊與原檔相同。MuMu 覆蓋安裝後手動更新成功換成 17:31 版，搜尋與日誌正常。
- 尚未驗證：模擬器無法用 adb 輸入中文，中文書名搜尋只由單元測試覆蓋；Windows 版未實機測試；gh-proxy 在大陸直連網路下的可用性（本機測試可能經過代理）。
