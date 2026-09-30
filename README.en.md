# ZAI-X (再漫画X)

[English](README.en.md) · [简体中文 / Full reference](README.md) · [繁體中文](README.zh-TW.md) · [Download](https://github.com/funkeyyou/zaimanhua/releases/latest) · [Report an issue](https://github.com/funkeyyou/zaimanhua/issues)

**An unofficial third-party client for Zaimanhua (再漫画, zaimanhua.com) on Android and Windows.**

Read manga, light novels and news from Zaimanhua, with AI-assisted search, access to hidden titles, dual-page reading on foldables and tablets, and automatic daily check-in. The app interface is in Chinese (Simplified or Traditional).

<p>
  <img src="docs/images/ai-search.jpg" alt="AI search: for “titles like Frieren: Beyond Journey's End”, the AI read 45 descriptions and picked 11 titles, each with a reason" width="260">
  <img src="docs/images/comic-detail.jpg" alt="Detail page of the hidden title Made in Abyss, showing its description and full list of 79 chapters" width="260">
</p>

*Left: AI search read 45 descriptions and picked 11 titles. Right: hidden titles open with their details and full chapter list. The screenshots show the Android app in Simplified Chinese.*

## What it does

- **AI search**: describe what you want in one sentence, such as “fantasy adventure with a strong female lead”. The AI turns it into genre filters and representative titles, gathers candidates from categories, the official search and a local index, reads their descriptions, and returns matches with a short reason. “Find more” continues with candidates it has not read yet.
- **Hidden and delisted titles**: titles missing from the official search come from a bundled local index that updates daily. Hidden titles open with their details, full chapter list and comments.
- **Reader**: dual-page spreads on foldables and tablets, next-chapter preloading, adjustable tap zones, keyboard page turns on Windows, per-title reading settings and an E-ink mode.
- **Library**: sort by update time, filter titles with unread updates, get new-chapter notifications on Android, and sync reading progress with your Zaimanhua account.
- **Account**: automatic daily check-in, task reward claiming and profile editing.
- **Updates**: in-app updates are verified by SHA-256. On Windows, v2.2.0 and later replace the app folder automatically and roll back if anything fails.

## Requirements

Android 7.0 or later, or Windows 10/11 (64-bit). Most content is readable without an account; subscriptions, progress sync, check-in and some chapters need a Zaimanhua account, which you sign in to inside the app.

This is an unofficial community project, not affiliated with Zaimanhua or DMZJ (动漫之家).

## Install

These links always point to the [latest release](https://github.com/funkeyyou/zaimanhua/releases/latest). If GitHub is slow, the gh-proxy links go through a third-party mirror; compare the file with the SHA-256 shown on the release page.

- **Android**: [ZAI-X-android.apk](https://github.com/funkeyyou/zaimanhua/releases/latest/download/ZAI-X-android.apk) (mirror: [gh-proxy](https://gh-proxy.com/https://github.com/funkeyyou/zaimanhua/releases/latest/download/ZAI-X-android.apk)). Allow installing apps from unknown sources the first time.
- **Windows**: [ZAI-X-windows-x64.zip](https://github.com/funkeyyou/zaimanhua/releases/latest/download/ZAI-X-windows-x64.zip) (mirror: [gh-proxy](https://gh-proxy.com/https://github.com/funkeyyou/zaimanhua/releases/latest/download/ZAI-X-windows-x64.zip)). Extract it to a writable folder such as `D:\Apps\ZAI-X` and run `ZAI-X.exe`. No installer or administrator rights are needed. Avoid `C:\Program Files`, where in-app updates cannot replace the files.

## Updates

Open **我的 → 检查更新** (Me → Check for updates) in the app. On Android, the new version installs over the old one and keeps your data. On Windows, v2.2.0 and later update in place; older versions need one manual update by extracting the new ZIP over the old folder. Windows keeps your library, history, settings and downloads in AppData, so replacing the app folder does not lose them.

## AI search and privacy

AI search sends only your description and the candidates' public information (title, author, genres, status, popularity and description), never your account or reading history. Release builds include the AI service: each device gets 50 AI searches per day, “Find more” counts as one, and repeating the same description within 30 minutes is not counted again.

## Build from source

- Use Flutter 3.47.2. On Windows, build from an ASCII-only path (a directory junction works), because non-ASCII paths break native builds.
- AI search needs an OpenAI-compatible `/chat/completions` endpoint. Put `{"baseUrl": "https://example.com/v1", "apiKey": "...", "model": "..."}` in a JSON file outside the repository, run `dart run tools/ai/make_ai_defines.dart --in config.json --out ai_defines.json`, then build with `--dart-define-from-file=ai_defines.json`. CI reads the same JSON from the `ZAI_AI_CONFIG` secret. Without it, the AI toggle is hidden.
- See the [full Chinese reference](README.md#开发) and the [roadmap](docs/ROADMAP.md) for details.

## Credits and license

Based on [xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj), a third-party DMZJ (动漫之家) client, and [Fusn126/ZAI_X](https://github.com/Fusn126/ZAI_X), which moved it to the Zaimanhua API. Licensed under [GPL-3.0](LICENSE). Following the original project's statement, it must not be used for commercial purposes.

All titles and images belong to their authors and Zaimanhua. If this project infringes your rights, please open an [issue](https://github.com/funkeyyou/zaimanhua/issues).
