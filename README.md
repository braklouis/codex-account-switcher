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
brew trust --cask braklouis/tap/codex-accounts
brew tap braklouis/tap
brew install --cask braklouis/tap/codex-accounts
```

Older Homebrew versions without `brew trust` can omit the first command. Review the cask before granting trust.


Update with `brew update` followed by `brew upgrade --cask braklouis/tap/codex-accounts`.

The tap is maintained by this project; this is not a listing in the official Homebrew cask repository. The cask verifies the release ZIP with a pinned SHA-256 and does not run credential-changing installation scripts.

### macOS first launch: Apple cannot verify the app

You may see a warning that Apple cannot verify Codex Accounts is free of malware. This release is **ad-hoc signed**, but has **no Apple Developer ID signature or Apple notarization**. Ad-hoc signing does not verify the publisher's identity. This warning means Apple cannot provide that verification; it is not itself a positive malware detection, nor does it prove the app is safe. Homebrew installation and SHA-256 verification do not replace notarization.

If you downloaded this release from this repository or its linked Homebrew cask, have reviewed the source/security information, and choose to trust it:

1. Move the app to **Applications** (Homebrew normally does this), then try opening it once.
2. Dismiss the warning without moving the app to Trash.
3. Open **Apple menu → System Settings → Privacy & Security**.
4. Scroll to **Security**, find the message about Codex Accounts, and click **Open Anyway**.
5. Authenticate if prompted, then confirm **Open**. macOS saves an exception for this app; an update may require approval again.

If Open Anyway is missing, try opening the app again, then return to Settings. On an organization-managed Mac, contact your administrator if policy prevents approval. A separate warning that the app **will damage your computer**, contains malware, or is damaged is not covered by these instructions: stop and investigate rather than overriding it.

Do not disable Gatekeeper globally or remove quarantine with terminal commands. The installer does neither. You can also review and build the source yourself. A later Developer ID-signed and notarized release would address the missing publisher verification; the current release has not completed that process.

A subsequent **Keychain access** prompt is separate: the app needs access to its saved accounts. Read that prompt carefully before approving.

[Apple's official first-launch guidance](https://support.apple.com/en-us/102445).

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
