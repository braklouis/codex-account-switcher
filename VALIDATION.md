# 验证记录

2026-09-08，在本机 Apple Silicon / Swift 6.3.3 / Codex 26.901.51231 上完成：

- `swift test`：15 项 XCTest 全部通过。虚构凭据覆盖不同用户同一工作区、API key 拒绝、无效登录、额度未知值与多 bucket、存储模式限制、0600 文件权限、符号链接拒绝、退出拒绝、钥匙串保存失败、启动/写入失败恢复、恢复失败提示。
- Release 编译及 `codesign --verify --strict` 通过。
- 应用 `--self-check`：独立测试钥匙串添加、读取、更新及清理；本机官方 app-server initialize / account/read；独立 home 返回未登录；辅助进程退出与临时 home 删除，全部通过。
- 原生窗口演示检查：3 个虚构账号、当前账号、短期/每周额度、刷新按钮、登录入口、切换确认框正常呈现；点击备用账号并确认后，“当前登录”和“使用中”状态成功切换到虚构账号 2。

尚未验证：真实第二账号的浏览器 OAuth 完成、真实额度返回、真实桌面重启后的账号切换。当前 Codex 正用于开发，没有替换其登录或关闭它。演示和自检不会代替上述真实验收。

自检命令（只操作专用测试钥匙串与空白临时 home）：

```sh
'dist/Codex Accounts.app/Contents/MacOS/CodexAccounts' --self-check
```

在受限构建环境中可把编译缓存放到临时目录：

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/codex-accounts-module-cache swift test --disable-sandbox --cache-path /private/tmp/codex-accounts-swift-cache
```

## 0.1.1 额度修复

- 真实服务诊断定位：`account/login/start.chatgptAuthTokens requires experimentalApi capability`（-32600）。初始化补上 experimentalApi 能力。
- 错误分类区分协议不兼容、认证过期、网络、限流和未知服务错误，不显示原始服务文本。
- 18 项 XCTest 全部通过，Release 打包及签名校验通过。
- 重新打开 0.1.1 应用并刷新，两个已保存账号均成功展示真实额度、多 bucket 和重置时间；未切换或重启 Codex 桌面应用。

## 0.2.0 视觉更新

- 原创 ImageGen 图标已加入应用资源与 Info.plist；打包生成 16–1024px ICNS。
- SwiftUI 额度卡片改为纵向百分比、渐变细条和分钟级更新的重置倒计时；主要 Codex bucket 优先，其余可展开，保留服务原始窗口信息。
- Debug / Release 编译及签名校验通过；实际窗口截图检查通过，两个真实账号成功刷新，主要窗口显示百分比、重置时间和更新时间。认证及切换逻辑未改动。
- 参考 CodexBar 的额度窗口与倒计时展示思路，未复制其源码或图标。

## 菜单栏额度面板

- MenuBarExtra 改为 window 样式，直接复用账号额度卡片，显示剩余百分比、进度条、重置倒计时及可展开的其他额度。
- 打开面板时刷新当前身份；缺失或超过一分钟的数据触发读取，忙碌时不重复请求。主窗口和面板共用数据。
- 切换入口在面板内保留重启确认，账号编辑集中到管理窗口。
- Release 编译与签名校验通过，新版已重新打开。系统菜单栏自动定位超时，弹出面板视觉验证待手动完成。

## 0.3.0 菜单栏常驻、登录启动与额度通知

- 21 项 XCTest 全部通过，新增阈值边界、跨档合并、周期重置及重启后去重测试。
- Release 编译及签名校验通过。
- 真实设置窗口检查：隐藏 Dock 开启；SMAppService 登录启动状态「已启用」；提醒开关开启，系统通知「已允许」。后台启动后真实额度读取正常。
- 未为验收重启 Mac；登录启动验证到系统注册状态。未人工消耗额度触发所有通知档位，档位逻辑由测试覆盖。
