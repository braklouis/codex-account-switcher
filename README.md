# TokenDeck

A personal macOS menu bar app for AI quota, usage and Codex account switching.

[简体中文](README.zh-CN.md)

Keep reset time and remaining quota in the menu bar, switch saved Codex accounts, and open **AI usage & spend** for Codex, Claude, Cursor, Gemini, OpenRouter, Grok and Kimi Code.

The provider dashboard uses the locally installed [CodexBar](https://github.com/steipete/CodexBar) CLI. Each provider needs its own working login or API configuration in CodexBar. Missing data is unavailable, not zero. Local token cost estimates are not subscription bills. Switching the dashboard provider does not change a service login; account switching currently applies to Codex only.

## Run locally

Requires macOS 14+, Swift, the Codex desktop app and CodexBar CLI (tested with 0.60.2). The CLI is discovered at `/opt/homebrew/bin/codexbar` or `/usr/local/bin/codexbar`.

```sh
zsh scripts/package.sh
open "dist/TokenDeck.app"
```

TokenDeck is a private local continuation. The old public repository releases and Homebrew cask contain Codex Accounts, not this version. No automatic publishing is configured by this change.

Existing Codex accounts, preferences and Keychain entries retain their original identifiers. Finish active Codex tasks before switching accounts: switching restarts Codex.

The local build is ad-hoc signed, not Apple-notarized. If macOS blocks a trusted build, use System Settings → Privacy & Security → Open Anyway; do not disable Gatekeeper.

## Credits

Provider integration references CodexBar by Peter Steinberger (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). TokenDeck does not embed its credentials or upload account data to a TokenDeck server.

## Product selection

Use the menu bar product chips to change the displayed service, and the account menu to choose an account. Codex selection switches its login; other providers select a monitored account returned by CodexBar. Choose products controls which services appear and remembers your selection. Qwen Cloud, GLM (z.ai / BigModel), and DeepSeek are available alongside the existing products. Login configuration opens CodexBar; TokenDeck reuses those logins without copying secrets.

Regression checks: `zsh scripts/check-provider-models.sh` (add `--live` to verify configured Grok and OpenRouter queries).
