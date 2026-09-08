# Contributing

Use synthetic accounts and `--demo` when developing UI changes. Do not switch or upload anyone else's accounts for testing.

Run `swift test --disable-sandbox`, `zsh scripts/package.sh`, and `git diff --check` before submitting a pull request. Describe the user-visible behavior, validation, and remaining limits. Changes to authentication, file permissions, subprocess lifetimes, or rollback require focused regression tests.

Keep credentials, local logs, build products, and personal screenshots out of commits. Report vulnerabilities privately as described in SECURITY.md. Contributions are provided under the project's MIT license.
