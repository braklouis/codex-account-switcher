# Codex Accounts

<img src="Assets/AppIcon.png" width="96" alt="Codex Accounts 图标">

给有多个 Codex 账号的人做的 Mac 小工具。在菜单栏看看还剩多少额度，需要时切个账号，不用反复退出、登录。

[English](README.md) · [下载安装包](https://github.com/braklouis/codex-account-switcher/releases/latest)

## 能做什么

- 把账号放在一起管理，当前使用的账号排在最上面。
- 菜单栏上下两行：上面是重置倒计时，下面是剩余额度。
- 额度可以显示百分比、进度条，或者两者一起显示。
- 剩余低于 75%、50%、25% 时发通知提醒。
- 支持中英文、开机启动，也可以只留在菜单栏里，不占 Dock。

账号保存在你这台 Mac 的钥匙串中，不会上传给作者，也没有遥测。

## 安装

需要 **macOS 14 及以上、Apple Silicon 芯片，以及官方 Codex 桌面应用**。

```sh
brew trust --cask braklouis/tap/codex-accounts
brew tap braklouis/tap
brew install --cask braklouis/tap/codex-accounts
```

旧版 Homebrew 如果没有 `brew trust`，跳过第一行即可。也可以从 [Releases](https://github.com/braklouis/codex-account-switcher/releases/latest) 下载，解压后拖进「应用程序」。

### 提示 Apple 无法验证？

目前还没有做 Apple 公证。如果你信任下载来源，可以这样打开：

1. 先打开一次应用，关闭警告，不要选「移到废纸篓」。
2. 进入 **系统设置 → 隐私与安全 → 仍要打开**。
3. 按提示确认，再点「打开」。

不用关闭系统的 Gatekeeper。以上针对「无法验证」提示；如果系统明确提示检测到恶意软件，不要照此放行。[Apple 官方说明](https://support.apple.com/en-us/102445)。

## 怎么用

打开工具，点「保存当前账号」，或者点「登录新账号」通过浏览器添加。出现钥匙串请求时允许访问，然后刷新额度。

选择账号即可切换。切换会重启 Codex，所以先结束正在运行的任务和 CLI 会话。不同账号仍然共用本地任务历史和项目。

语言、菜单栏样式、开机启动和通知都在「设置」里调整。额度每 5 分钟自动检查一次。

目前支持使用 Codex 默认目录和文件登录存储的会员账号，暂不支持 API key 或自定义凭据存储。这是个人开源项目，不是 OpenAI 官方应用。

## 自己编译

安装 Apple 开发工具后：

```sh
git clone https://github.com/braklouis/codex-account-switcher.git
cd codex-account-switcher
swift test --disable-sandbox
zsh scripts/package.sh
open 'dist/Codex Accounts.app'
```

最后一行加上 `--args --demo` 可以用虚构账号体验。

## 关于

额度展示参考了 [CodexBar](https://github.com/steipete/CodexBar) 的思路。使用 SwiftUI 和 AppKit 开发，图标由 AI 生成。

[MIT 许可证](LICENSE) · [安全与隐私](SECURITY.md) · [参与开发](CONTRIBUTING.md)
