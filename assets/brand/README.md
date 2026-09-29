# 再漫畫X 圖示

原創書頁與 X 的組合，保留閱讀 App 的藍色辨識，使用深藍、亮藍、青色及白色。名稱由使用者指定；簡體「再漫画X」、繁體「再漫畫X」。

v2.0.0 使用本目錄的向量稿。內建生圖後續已恢復並產生試作；使用者比較後確認保留 App 目前使用的圖示，因此未將生圖稿替換進正式資產。

- 可編輯來源：`zaimanhua-x.svg`。
- 完整預覽：`zaimanhua-x-1024.png`。
- App 內圖片：`../images/zaimanhua_x.png`。
- Android：各密度傳統圖示、adaptive 前景／背景、Android 13 單色圖示。
- Windows：ICO 含 16、24、32、48、64、128、256 尺寸。

重建 PNG 與 ICO（需要 Node.js 和 sharp；可傳入已安裝的 node_modules 位置）：

```text
node tools/generate_brand_icons.cjs [path/to/node_modules]
```
