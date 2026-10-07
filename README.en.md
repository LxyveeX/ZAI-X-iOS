# ZAI-X iOS · Personal-use port

A personal iPhone / iPad adaptation of [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua), maintained as a public fork for personal use.

[Download IPA](https://github.com/LxyveeX/ZAI-X-iOS/releases) · [简体中文](README.md) · [繁體中文](README.zh-TW.md)

## Status and installation

**Preview builds; physical-device testing is pending.** Version 2.4.1 passed 225 tests, an iOS Release build and an iPad simulator startup check. Signing, login and the complete reading flow on iPadOS 16.7 still need device verification.

Download the unsigned `.ipa` from a release's **Assets**, then sign and install it with your own certificate and provisioning profile. Minimum OS: **iOS / iPadOS 15.0**. Bundle ID: `com.lxyveex.zaix`. It can coexist with the old app; sign in again after installation. Old local downloads, settings and unsynced history do not transfer automatically.

Each successful **Build iOS IPA** run is archived as a separate prerelease, including the IPA, SHA-256 checksum, build metadata and iPad startup screenshot. Previous builds remain available. Preview builds are downloaded manually; the current in-app updater reads stable releases only.

## Scope

This fork adds iOS project and plugin integration, iPad sharing, photo permissions, background-task registration and a category initial-load fix. It retains the upstream reader and catalog features. The upstream private AI service configuration is not included, so AI entry points stay hidden. iOS schedules background refresh.

See the Chinese [installation and build guide](docs/IOS.md) and [validation record](docs/IOS_VALIDATION.md).

## Credits and license

Based on [funkeyyou/zaimanhua](https://github.com/funkeyyou/zaimanhua) v2.4.0, through [Fusn126/ZAI_X](https://github.com/Fusn126/ZAI_X), originating from [xiaoyaocz/flutter_dmzj](https://github.com/xiaoyaocz/flutter_dmzj/tree/zaimanhua). Original attribution is retained and the source remains under [GPL-3.0](LICENSE).

For the full upstream description and Android / Windows builds, visit the [upstream repository](https://github.com/funkeyyou/zaimanhua). This is an unofficial community client. Content and images belong to their respective rights holders.
