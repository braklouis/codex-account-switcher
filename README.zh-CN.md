# Codex Accounts

原生 macOS 菜单栏 Codex 账号切换与额度查看工具。[English](README.md)

## 功能

- 多账号保存在本机钥匙串，通过官方浏览器登录添加账号。
- 菜单栏直接显示短期 / 每周剩余额度：百分比、分段条、两者同时显示。
- 浅青蓝与浅紫配色、重置倒计时和其他额度窗口。
- 确认后切换账号并正常重启 Codex，失败时尝试恢复原登录。
- 隐藏 Dock、登录启动、每 5 分钟刷新、低于 75% / 50% / 25% 去重提醒。
- 设置中选择简体中文或 English；少量底层诊断仍可能显示中文。

## 安装

需要 macOS 14+、Apple Silicon 和已安装的官方 Codex 桌面应用。Intel 源码构建尚未验证。

```sh
brew trust --cask braklouis/tap/codex-accounts
brew tap braklouis/tap
brew install --cask braklouis/tap/codex-accounts
```

旧版 Homebrew 若没有 `brew trust` 命令，可省略第一行。授予信任前应检查 cask 内容。


也可从 [Releases](https://github.com/braklouis/codex-account-switcher/releases/latest) 下载 ZIP，解压后移入应用程序目录。

这是项目自行维护的 Homebrew tap，安装包使用固定 SHA-256 校验。目前为 ad-hoc 签名，**未经过 Apple Developer ID 签名和公证**。若首次打开被系统拦截，请仅在信任下载来源后，在「系统设置 → 隐私与安全」使用「仍要打开」。安装脚本不会关闭 Gatekeeper 或清除隔离标记。

更新：`brew update` 后执行 `brew upgrade --cask braklouis/tap/codex-accounts`。

## 使用与限制

打开工具，选择「保存当前账号」或「登录新账号」，允许钥匙串访问，再刷新额度。切换前先结束运行中的 Codex 任务和 CLI 会话。

默认仅显示菜单栏、尝试注册登录启动并申请通知权限，可在设置中关闭。移动应用后，需要重新关闭并开启登录启动。

仅支持默认 `~/.codex` 和文件型登录存储，不支持 API key、自定义 home、明确配置的 keyring / auto。本工具是独立社区项目，与 OpenAI 无隶属或背书关系，不会增加或重置订阅额度。

**账号切换不等于数据隔离**：本地任务历史、项目和 Codex 目录由账号共用。账号保存在不经 iCloud 同步的本机钥匙串；切换时以 0600 权限原子写入登录文件。额度通过本机官方 app-server 读取，不向作者上传账号，无遥测和 API 代理。异常退出可能留下 0700 权限的临时登录目录。完整边界见 [SECURITY.md](SECURITY.md)。

## 开发

```sh
swift test --disable-sandbox
zsh scripts/package.sh
open 'dist/Codex Accounts.app' --args --demo
```

演示使用虚构账号，不接触真实凭据。打包架构跟随构建主机；重新构建可能重新触发钥匙串授权。MIT 开源，欢迎 PR。请勿在反馈中贴出真实令牌、邮箱、登录文件或账号截图。

额度窗口展示参考 [CodexBar](https://github.com/steipete/CodexBar) 的设计思路，没有复制源码或图标。图标来源见 [Assets/README.md](Assets/README.md)。
