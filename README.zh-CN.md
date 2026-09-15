# TokenDeck

自用的 macOS 菜单栏工具：查看 AI 额度和消耗，切换 Codex 账号。

菜单栏显示剩余时间和额度。打开「AI 额度与消耗」，可以查看 Codex、Claude、Cursor、Gemini、OpenRouter、Grok 和 Kimi Code。

多平台查询复用本机 [CodexBar](https://github.com/steipete/CodexBar) CLI，需先在 CodexBar 配好对应服务。拿不到的数据会显示不可用；本地 Token 的标价估算不是会员实际账单。选择平台只切换查看内容，当前账号切换功能仍仅支持 Codex。

## 本地运行

需要 macOS 14+、Swift、Codex 桌面端和 CodexBar CLI（已验证 0.60.2）。查询工具从 `/opt/homebrew/bin/codexbar` 或 `/usr/local/bin/codexbar` 读取。

```sh
zsh scripts/package.sh
open "dist/TokenDeck.app"
```

TokenDeck 是自用后续版本。旧 GitHub Release 和 Homebrew cask 仍是 Codex Accounts，不会自动更新为本版本。

改名保留原来的账号、设置和钥匙串标识。切换 Codex 前先结束运行中的任务，因为切换会重启 Codex。

本地构建使用临时签名，尚未经过 Apple 公证。可信构建若被 macOS 拦截，可前往「系统设置 → 隐私与安全性 → 仍要打开」，无需关闭 Gatekeeper。

## 致谢

多平台接入参考 Peter Steinberger 的 CodexBar（MIT），见 [第三方声明](THIRD_PARTY_NOTICES.md)。TokenDeck 不内嵌凭据，也没有上传账号数据的服务器。
