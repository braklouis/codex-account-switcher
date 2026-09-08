# Security

## Report privately

Use this repository's GitHub **Security → Report a vulnerability** feature. Do not open a public issue containing credentials or exploit details. Share a minimal reproduction with synthetic data. Never send your `auth.json`, access/refresh tokens, Keychain exports, or unredacted logs. If a real credential has been exposed, revoke the affected session with its provider; deleting the text alone is insufficient.

## What the app does

- Stores account snapshots in a device-only, non-synchronizing macOS Keychain item (`local.codexaccounts.vault.v1`).
- Reads the default Codex file-based session. Only a confirmed switch replaces it, using an atomic `0600` temporary file and rename.
- Requests a graceful Codex quit; refusal stops the switch. Rollback is attempted on write or launch failure and may itself fail.
- Launches the installed official Codex app-server directly, not via a shell. Uses a private temporary home and local stdio; tokens are not command arguments. Raw subprocess stderr is discarded.
- Opens only HTTPS browser login URLs with the exact `auth.openai.com` or `auth0.openai.com` host. Quota network requests are performed by the official child process.
- Terminates only its own temporary helpers on cleanup. It does not force-kill the desktop app.
- Has no maintainer backend, telemetry endpoint, token upload, auto-switcher, API proxy, or quota-reset call.

## Limitations

This is a personal convenience utility, not a credential sandbox or independent security audit. Other software running as your user may compromise local credentials. Accounts share Codex local history and configuration. Close CLI sessions and avoid concurrent switchers. Custom credential stores and managed environments are not fully supported.

Unexpected termination can leave a private `codex-accounts-*` temporary directory. Remove only those belonging to completed operations; do not remove an active login directory. Uninstalling preserves saved Keychain accounts. Remove unwanted accounts in the app before uninstalling, and disable launch at login first.

The prebuilt release is ad-hoc signed and not notarized. SHA-256 pins the downloaded archive, but is not an independent publisher identity guarantee. Installers do not bypass macOS security. Release artifacts contain the compiled application and its icon, not account stores or debug logs.

## Maintainer release checks

1. Run `gitleaks git . --log-opts="--all" --redact` to scan reachable Git history.
2. Scan a clean source export and the extracted release with `gitleaks dir ... --redact`.
3. Inspect all tracked file names, historical blobs, commit metadata, image assets, and archive contents for private data. Automated scanners cannot prove absence of every secret.
4. Run unit tests, build from a clean source export, remove debug symbols, and verify the app signature.
5. Check the ZIP hash matches the Homebrew cask. Do not add quarantine removal, remote shell execution, or automatic Keychain deletion to the cask.
6. Push only the reviewed branch and release tag. Do not push all local refs blindly.
