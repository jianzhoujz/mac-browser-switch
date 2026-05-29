# AGENTS.md — 给 AI 协作 Agent 的项目指南

本文件是项目唯一的「面向 AI 阅读」入口文档。任何 AI Agent（Claude
Code / Cursor / Codex / Gemini Code Assist / Cline 等）在开始工作前
都应先读完本文，再去翻代码。本文回答四个问题：

1. **这是什么项目？** —— 一句话定位 + 用户视角
2. **代码长什么样？** —— 单文件 Swift 应用的结构地图
3. **设计原则是什么？** —— 为什么要这样写，哪些路已经走过别再走
4. **开发与发布流程？** —— 构建、安装、调试、提交规范

---

## 1. 项目一句话定位

macOS 菜单栏快速切换默认浏览器的小工具。**单文件 Swift 应用**
（[Sources/BrowserSwitch.swift](Sources/BrowserSwitch.swift)），常驻菜单
栏，无主窗口、无 Dock 图标。

### 用户视角

菜单栏出现一个 `BrowserSwitch` 文本标题，点开就是当前机器上所有注册为
`https` 处理程序的浏览器列表，当前默认浏览器旁边有勾。点任意一项触发
macOS 自带的「是否要更改默认网络浏览器」确认弹窗，用户确认即完成切换。

```
BrowserSwitch
──────
   Safari
 ✓ Google Chrome              ← 当前默认
   Arc
   Firefox
   Microsoft Edge
   …
──────
 ☑ 开机启动
   检查更新…
   GitHub 主页
──────
   版本 X.Y.Z
   退出                       ⌘Q
```

`LSUIElement` accessory 应用 —— 无 Dock 图标、无主窗口、常驻菜单栏。

### 为什么需要这个东西

macOS 切换默认浏览器要点四下（`系统设置 → 应用程序 → 默认网络浏览器
→ 选择 → 确认`）。本项目把列表搬到菜单栏，省下前三下。最后那下系统弹
窗是 Apple 强制的安全机制（见 §3.1），无法绕过，也不试图绕过。

---

## 2. 代码结构地图

### 仓库布局

```
mac-browser-switch/
├── AGENTS.md                       ← 本文件，AI 入口
├── README.md                       ← 英文 README（默认）
├── README.zh-CN.md                 ← 中文 README
├── LICENSE                         ← MIT
├── .gitignore
├── Sources/
│   └── BrowserSwitch.swift         ← 全部业务代码，单文件
├── Resources/
│   └── AppIcon.icns                ← 应用图标
├── tools/
│   └── make_app_icon.swift         ← 从 emoji 生成 iconset 的脚本
├── packaging/
│   └── dmg/                        ← DMG 打包用的 .DS_Store / 背景图 / 卷标图
├── scripts/
│   └── package-release.sh          ← 打 DMG + 更新 homebrew-tap Cask
├── docs/
│   └── images/                     ← README 用图
├── build.sh                        ← swiftc + lipo + codesign，输出 build/BrowserSwitch.app
├── install.sh                      ← 构建 + 装到 /Applications + LaunchAgent
├── uninstall.sh                    ← 反向操作
└── package-dmg.sh                  ← 从 build/BrowserSwitch.app 打 dmg 到 dist/
```

### 单文件源码结构（[Sources/BrowserSwitch.swift](Sources/BrowserSwitch.swift)）

按出现顺序：

| 符号 | 职责 |
| --- | --- |
| `struct AppConfig` | 不变量：app 名、bundle ID、display name、GitHub repo、launchAgentID、日志文件名 |
| GitHub release 工具 | `VersionNumber` 比较 + 检查更新 URL 常量 |
| `struct Browser` | 一个候选浏览器的数据：bundleID、displayName、appURL、icon、version |
| `enum BrowserCatalog` | LaunchServices 封装：`allBrowsers()` / `currentDefault()` / `setDefault(bundleID:)` |
| `class AppDelegate` | NSStatusItem、菜单构建（`menuWillOpen:` 时重建）、动作处理、更新检查、自启、日志 |
| 入口 | `NSApplication.shared.run()` |

代码量预计 600–800 行。**没有 `#if` 编译分支**（与 input-indicator 不同，
本项目只有一个产品）。

### `BrowserCatalog` 关键方法

| 方法 | 用途 |
| --- | --- |
| `allBrowsers()` | `LSCopyAllHandlersForURLScheme("https" as CFString)` → 去重 → 每个 bundle ID 用 `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 解析为 app URL → 读 `Bundle(url:).infoDictionary` 拿 displayName 和 version → `NSWorkspace.shared.icon(forFile:)` 缩到 16×16 |
| `currentDefault()` | `LSCopyDefaultHandlerForURLScheme("https" as CFString)` → bundle ID。**只在 `menuWillOpen:` 时调，不缓存**。 |
| `setDefault(bundleID:)` | 同时设 `http` 和 `https` 两个 scheme。macOS 自己弹确认框，本应用不弹自己的。 |

### `AppDelegate` 关键方法

| 方法 | 用途 |
| --- | --- |
| `applicationDidFinishLaunching` | 创建 `NSStatusItem`、装菜单、初始构建一次 |
| `menuWillOpen(_:)` | **每次打开菜单都重建** —— 这样新装/卸载的浏览器、外部用其他工具切换默认浏览器的结果都能即时反映 |
| `selectBrowser(_:)` | 菜单项 action：拿 bundleID → `BrowserCatalog.setDefault` → 写日志（不刷新菜单，因为系统弹窗会盖在前面） |
| `toggleLaunchAtLogin` / `enableLaunchAtLogin` / `disableLaunchAtLogin` | 写 `~/Library/LaunchAgents/local.mac-browser-switch.plist` + `launchctl bootstrap/bootout`（与 input-indicator 同模式） |
| `checkForUpdates` / `finishUpdateCheck` | HEAD 请求 `releases/latest`，从重定向 URL 路径里抽 tag 比较版本（与 input-indicator 同模式） |
| `openGitHub` / `quit` | 普通跳转和退出 |

---

## 3. 设计原则（动手前必读）

### 3.1 **尊重 macOS 的确认弹窗，不要试图绕过**

切换 `http` / `https` 的默认处理程序时，macOS 一定会弹「是否要将默认
网络浏览器更改为 X？」的确认对话框。这是 Apple 在 LaunchServices 层
对默认浏览器 scheme 的特殊保护，**已知所有规避路径都不可行**：

| 方案 | 为什么不行 |
| --- | --- |
| 用付费 Apple Developer ID + 公证 | 已验证不行。Velja、Browserosaurus、Choosy 等都是正式签名 + 公证的商业应用，调用同一个 API 也会弹同样的窗 |
| 申请特殊 entitlement | Apple 没有为第三方 app 提供这种 entitlement |
| 用 `defaults write` 直接改 `com.apple.LaunchServices/com.apple.launchservices.secure` 的 plist | 写完后 LaunchServices 会忽略并自动恢复；从 macOS 13 起这个 plist 还会被 SIP 保护 |
| 模拟点击确认按钮 | 需要辅助功能权限 + 弹窗结构每个 macOS 版本都变；本质是 UI 自动化，违反 App Sandbox 设计意图，未来 macOS 升级随时翻车 |
| 调旧的 `LSSetDefaultHandlerForURLScheme` 在沙盒外的私有变体 | 不存在 |

**结论**：本应用的 UX 设计明确接受确认弹窗。README 中文/英文版都把它
作为「预期行为」写清楚。**任何想抑制这个弹窗的 PR/改动都应直接拒绝**。

### 3.2 **浏览器列表来自 LaunchServices，不要硬编码**

`LSCopyAllHandlersForURLScheme("https")` 返回的是当前系统注册过的 https
handler bundle ID 列表，这是「哪些应用算浏览器」的权威来源。硬编码
（"Safari", "Chrome", "Firefox", "Edge"...）会有两个问题：

1. 漏新出现的浏览器（Arc、Zen、Orion、Brave、Vivaldi、Chromium 各种
   fork、内测分支）
2. 漏用户本地装的 PWA / SSB 包装器（这些也合法地注册 https handler）

实测在我的机器上 `LSCopyAllHandlersForURLScheme` 至少能正确返回：Safari、
Chrome、Edge、Firefox、Arc、Brave、Chromium nightly、Velja（用作转发器
时也算）。

### 3.3 **菜单在 `menuWillOpen:` 重建，不要用 timer**

浏览器列表和当前默认值只在两个场景变化：

1. 用户在系统设置或其他工具里手动改了
2. 用户装/卸载了某个浏览器

这两件事用户都不会在「菜单关着」时关心。在 `NSMenuDelegate` 的
`menuWillOpen:` 里重建菜单，既保证拿到的状态是最新的，又零额外开销。
**不要装定时器轮询 LaunchServices**——浪费 CPU、没有用户可见收益。

### 3.4 **`setDefault` 后:刷新菜单栏图标,但不重建菜单**

`LSSetDefaultHandlerForURLScheme` 会触发 macOS 弹窗。这个弹窗有自己
的生命周期,期间应用菜单已经关掉了。

- **菜单本身**:不要尝试在完成回调里 `rebuildMenu()`,会和系统弹窗
  状态打架。等下次菜单打开(`menuWillOpen:`)时再调 `currentDefault()`
  重建即可。
- **菜单栏图标**(NSStatusItem 的 button image):**要**在完成回调里
  通过 `BrowserCatalog.currentDefault()` 重新查询并调
  `refreshStatusItemIcon` 刷新。否则用户切换浏览器后,菜单栏图标要等
  下次打开菜单才更新,体验上像是"切换没生效"。注意必须重新查询
  LaunchServices 而不是直接用回调里的 `browser` —— 用户可能在系统
  弹窗里点了"取消",此时默认浏览器并未改变。

### 3.5 **同时设置 `http` 和 `https`**

很多旧代码只调 `LSSetDefaultHandlerForURLScheme("http", ...)`，结果
`https` 的默认 handler 没变，用户实际点 https 链接还是去原来的浏览器。
正确做法是 `http` 和 `https` 两次都调。**`mailto` 不在本应用范围内**
（那是邮件客户端的默认值，不是浏览器）。

### 3.6 **不要乱加权限请求**

本应用不需要任何敏感权限。**不要**为了任何「便利特性」去申请：

- 辅助功能（Accessibility）：本应用没有任何 AX 读取需求
- 输入监控（Input Monitoring）：本应用不监听键盘
- 完全磁盘访问：本应用只读 `~/Library/Logs/` 自己的日志

零权限是用户体验和审计透明度的一部分。一旦弹了权限请求，用户会怀疑这
个应用在偷偷做别的事。

---

## 4. 工程化规范

### 4.1 构建

```bash
./build.sh                   # → build/BrowserSwitch.app
```

[build.sh](build.sh) 流程（与 input-indicator 同模板，但**没有** variant
分支）：

1. 清空 `build/`
2. `swiftc` 分别编译 arm64 和 x86_64 切片
3. `lipo -create` 合并成 universal binary
4. 拷贝 `Resources/AppIcon.icns`
5. 写 `Info.plist`（含 `LSUIElement=true`、版本号、构建时间）
6. `codesign --force --deep --sign -`（ad-hoc 签名）

环境变量：

- `APP_VERSION` 覆盖版本号（默认见 build.sh 顶部）
- `REGENERATE_APP_ICON=1` 重新从 emoji 生成图标

### 4.2 本地安装与调试

```bash
./install.sh                 # 停旧进程 → 构建 → 替换 /Applications/BrowserSwitch.app → 写 LaunchAgent → 启动
./uninstall.sh
```

日志位置：

```text
~/Library/Logs/BrowserSwitch.log
```

超过 1 MB 自动轮转为 `.old`。

### 4.3 发布流程

```bash
./scripts/package-release.sh <版本号>
```

会：

1. 调 `./package-dmg.sh` 输出 `dist/BrowserSwitch-<版本号>.dmg`
2. 算 sha256
3. 把 `../homebrew-tap/Casks/mac-browser-switch.rb` 里的 `version` 和
   `sha256` 字段就地替换
4. 打印 `gh release create v<版本号> ...` 命令让作者手动跑

**本仓库的脚本不会自动 `git commit`、不会 `git push`、不会调 `gh
release create`。** 这是 user 全局 CLAUDE.md 中 git 安全协议的一部分：
对外可见的 push / release 一律由作者手动确认。

### 4.4 提交规范

- Commit message 用中文 + Conventional Commits 前缀（`fix:` / `feat:` /
  `docs:` / `refactor:`）。第一行简短描述，空行后写 body 解释「为什么」
  和影响面
- 每个 commit 末尾自动加 `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`
  当 AI Agent 参与时
- 遵循 user 全局 CLAUDE.md 中的 git 安全协议：永不 amend、永不
  `--no-verify`、不主动 push（用户明示后再 push）

### 4.5 与 homebrew-tap 仓库的耦合

发布产物需要更新同一级目录的 `homebrew-tap` 仓库：

- Cask 文件：[../homebrew-tap/Casks/mac-browser-switch.rb](../homebrew-tap/Casks/mac-browser-switch.rb)
- README 里的索引段落：[../homebrew-tap/README.md](../homebrew-tap/README.md)

`scripts/package-release.sh` 会自动改 Cask 的 version + sha256；README
段落本身不会改动，第一次发布时手动加，之后版本号在 Cask 里就够了。

---

## 5. 给 AI 的工作守则

在本仓库做改动时：

- **优先编辑** [Sources/BrowserSwitch.swift](Sources/BrowserSwitch.swift)（业务全在这一个文件）
- **改完必须**编译通过：`./build.sh`
- **改 UX 或菜单结构**前，先重读 §3 的「设计原则」，特别是 §3.1（不要
  试图绕过 macOS 确认弹窗）和 §3.6（不要乱加权限）
- **有 UI 变化**（菜单项、tooltip）记得同步更新 [README.md](README.md)
  和 [README.zh-CN.md](README.zh-CN.md)
- **新增设计原则或调研结论**记得回头更新本文 §3 对应小节
- 不要新建 `docs/ARCHITECTURE.md` / `CONTRIBUTING.md` / `CLAUDE.md` 等
  并行的「AI 文档」——本项目唯一的 AI 入口就是这个 AGENTS.md
- 只有作者本机才用得上的内容（个人安装位置、release 路径）放到
  `DEVELOPMENT_CONTEXT.md`（需加入 .gitignore），不要入库
