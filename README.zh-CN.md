# BrowserSwitch

![macOS](https://img.shields.io/badge/macOS-12.0%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-brightgreen)
![Intel](https://img.shields.io/badge/Intel-supported-brightgreen)
![Release](https://img.shields.io/github/v/release/jianzhoujz/mac-browser-switch)

一个常驻 macOS 菜单栏的小工具，用来快速切换系统默认浏览器，不用每次都去打开「系统设置」。

[English README](README.md)

> 🤖 **AI 协作 Agent / 贡献者请先阅读 [AGENTS.md](AGENTS.md)**：这是项目唯一的「面向 AI 阅读」入口文档，包含代码结构、设计原则、构建与发布流程。

---

## 为什么需要这个

macOS 切换默认浏览器要点四下：`系统设置 → 应用程序 → 默认网络浏览器 → 选择 → 确认`。如果你一天要切几次，就会觉得很烦。BrowserSwitch 把这个下拉菜单直接放到了菜单栏：

![菜单截图](docs/images/menu.png)

点一下浏览器，就切好了。

## 安装

### 通过 Homebrew 安装（推荐）

```bash
brew tap jianzhoujz/tap
brew install --cask mac-browser-switch
```

### 更新

```bash
brew update
brew upgrade --cask mac-browser-switch
```

### 卸载

```bash
brew uninstall --cask mac-browser-switch
```

### 手动安装

从 [GitHub Releases](https://github.com/jianzhoujz/mac-browser-switch/releases) 下载 `BrowserSwitch-<版本号>.dmg`，打开后把 `BrowserSwitch.app` 拖到 `Applications`，再从 `/Applications` 启动。

## 首次启动

当前应用是 **ad-hoc 签名**（没有付费 Apple Developer ID）。macOS 可能会提示：

- 「无法打开 BrowserSwitch，因为 Apple 无法检查其是否包含恶意软件」 — 打开 `系统设置 → 隐私与安全性`，向下滚动，点击「仍要打开」。
- 「BrowserSwitch 已损坏，无法打开」 — 移除 quarantine 标记：

  ```bash
  xattr -dr com.apple.quarantine /Applications/BrowserSwitch.app
  ```

只需要处理一次。本应用 **不需要任何额外权限** — 无需辅助功能、无需输入监控、无需完全磁盘访问权。

## 切换的过程

点击菜单里的某个浏览器后，BrowserSwitch 会请求 LaunchServices 把那个 app 设为 `http` 和 `https` 的默认处理程序。随后 macOS 会自己弹一个确认对话框：

> 是否要将默认网络浏览器更改为 **Firefox**？

点「使用 Firefox」就完成切换了，菜单里的对勾会在下次打开时移动到 Firefox。

这个确认弹窗是 macOS 在默认浏览器 scheme 上的安全机制 — 即便是付费签名并完成公证的商业应用（Velja、Browserosaurus 等）也会触发同样的弹窗，没有可以抑制它的 entitlement。BrowserSwitch 没有尝试绕过这一步。

## 菜单结构

```
BrowserSwitch
──────
   Safari
 ✓ Google Chrome              ← 当前默认
   Arc
   Firefox
   Microsoft Edge
   …                          ← 所有注册为 https 处理程序的 app
──────
 ☑ 开机启动
   检查更新…
   GitHub 主页
──────
   版本 0.1.0
   退出                       ⌘Q
```

每次打开菜单都会重新枚举浏览器，所以刚装上的浏览器会立刻出现。

## 系统要求

- macOS 12.0 Monterey 或更高版本
- Apple Silicon 或 Intel Mac

## 偏好用命令行？

如果你更想脚本化切换默认浏览器，Homebrew 上的 [`defaultbrowser`](https://github.com/kerma/defaultbrowser) 公式可以从终端完成同样的事。BrowserSwitch 只是同一套 `LSSetDefaultHandlerForURLScheme` API 之上的菜单栏壳，两者可以并存。

## 开发

### 构建

```bash
./build.sh                   # → build/BrowserSwitch.app
```

输出 universal binary（`arm64` + `x86_64`），ad-hoc 签名。

### 本地安装 / 开发循环

```bash
./install.sh                 # 停旧进程 → 构建 → 装到 /Applications → 写 LaunchAgent
./uninstall.sh               # 反向操作
```

### 打 DMG

```bash
./package-dmg.sh             # → dist/BrowserSwitch-<版本号>.dmg
```

### 发布（仅维护者）

```bash
./scripts/package-release.sh 0.2.0
```

会打 DMG、把 sha256 更新到 `../homebrew-tap/Casks/mac-browser-switch.rb`，并打印一条 `gh release create` 命令让你手动执行。

### 日志

```text
~/Library/Logs/BrowserSwitch.log
```

超过 1 MB 自动轮转。需要排查问题时直接打开这个文件。

## 反馈

Bug 报告和功能请求请提交到 [GitHub Issues](https://github.com/jianzhoujz/mac-browser-switch/issues)。

## 许可

MIT。详见 [LICENSE](LICENSE)。
