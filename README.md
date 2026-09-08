# Codex Accounts

<img src="Assets/AppIcon.png" width="96" alt="Codex Accounts icon">

A small native macOS menu bar app for switching your own Codex accounts and checking remaining quota.

**[简体中文](README.zh-CN.md)** · [Releases](https://github.com/braklouis/codex-account-switcher/releases) · [Security](SECURITY.md) · [MIT license](LICENSE)

## Features

- Save multiple accounts in the local macOS Keychain; add accounts through the official browser sign-in.
- Show short-term and weekly remaining quota directly in the menu bar: percentages, segmented bars, or both.
- Light cyan and soft violet quota colors, detailed reset countdowns, and additional quota buckets.
- Switch accounts with a confirmation and a graceful Codex restart; attempt rollback if switching fails.
- Menu bar only mode, optional Dock icon, launch at login, and alerts below 75%, 50%, and 25%.
- Simplified Chinese / English selection in Settings. Some low-level system and diagnostic messages may remain Chinese.
- SwiftUI + AppKit, no third-party application dependencies, no telemetry or account upload service.

This is an independent community project, not affiliated with or endorsed by OpenAI. It does not increase or reset your subscription limits.

## Requirements

- macOS 14 or later. The prebuilt release and Homebrew cask currently support **Apple Silicon only**.
- The official Codex desktop app installed and launched at least once.
- ChatGPT subscription sign-in with the default `~/.codex` home and file-based credential storage. API keys, custom homes, and explicit `keyring` / `auto` storage are not supported.
- Intel source builds are not verified.

## Install with Homebrew

```sh
brew tap braklouis/tap
brew install --cask braklouis/tap/codex-accounts
```

Update with `brew update` followed by `brew upgrade --cask braklouis/tap/codex-accounts`.

The tap is maintained by this project; this is not a listing in the official Homebrew cask repository. The cask verifies the release ZIP with a pinned SHA-256 and does not run credential-changing installation scripts.

### macOS first launch

The release is **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper may block first launch. Only if you trust the downloaded release, use macOS **System Settings → Privacy & Security → Open Anyway** after attempting to open the app. The installer does not disable Gatekeeper or remove quarantine. Alternatively, build from source below.

## Download manually

Download `Codex-Accounts-0.4.0-arm64.zip` from [Releases](https://github.com/braklouis/codex-account-switcher/releases/latest), extract it, and move `Codex Accounts.app` into Applications. Checksums are included with the release.

## Use

1. Open Codex Accounts, then choose **Save current account** or **Add account**.
2. Allow its Keychain access request. A rebuilt app may request access again because ad-hoc signatures change.
3. Refresh quota, then open **Settings → Language / 语言** to select your language and menu bar style.
4. Before switching, finish running Codex tasks and close CLI sessions; confirm **Switch and restart**.

By default, the app stays in the menu bar, attempts to enable launch at login, and requests notification permission. These can be disabled in Settings. Keep the app in its installed location; after moving it, toggle launch at login off and on again.

Quota checks run every five minutes while awake. Unknown, expired, or failed data is not treated as zero. Older values may remain dimmed in account cards. Notifications are deduplicated per account, window, and reset cycle.

## Privacy and boundaries

Credentials are held in a device-local, non-iCloud Keychain item. Account switching writes the official `~/.codex/auth.json` with mode `0600` through an atomic rename. Quota reads use the installed official Codex app-server in an isolated temporary home; access tokens travel over local stdio, not command-line arguments. The app does not send saved accounts to the maintainer or proxy API requests.

**Switching accounts is not data isolation:** accounts share local Codex task history, projects, and the same home directory. Cloud tasks and permissions remain account-specific. Do not use concurrent CLI sessions or another switcher during a switch.

Temporary login homes use `0700` permissions and are removed on normal completion. A crash or forced termination can leave private temporary files. The macOS account and its Keychain remain a trust boundary; this tool cannot protect credentials from a compromised local account. Read [SECURITY.md](SECURITY.md) for details and reporting guidance.

## Build and contribute

Install Apple's command-line developer tools with a Swift compiler compatible with this package (validated with Swift 6.3.3), then:

```sh
git clone https://github.com/braklouis/codex-account-switcher.git
cd codex-account-switcher
swift test --disable-sandbox
zsh scripts/package.sh
open 'dist/Codex Accounts.app' --args --demo
```

Demo mode uses synthetic accounts and never reads or changes real credentials. Run without `--demo` to use real accounts. `--self-check` performs an isolated Keychain and app-server integration check; it is not a real multi-account switching test.

Release builds default to ad-hoc signing. Maintainers may provide `SIGN_IDENTITY` to the packaging script; notarization is a separate step and is not performed by this script. The package is native to the build host architecture.

Before submitting changes, run tests and `git diff --check`. Do not include auth files, Keychain exports, raw logs, real account screenshots, or tokens in issues or pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgments

Quota-window presentation was inspired by [CodexBar](https://github.com/steipete/CodexBar). No source code or artwork was copied. The app icon is an original AI-generated asset; its provenance is recorded in [Assets/README.md](Assets/README.md).
