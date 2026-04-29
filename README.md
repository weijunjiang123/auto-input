# AutoInput

AutoInput 是一个轻量 macOS 菜单栏应用，用来按前台应用自动切换输入法。它主要解决开发场景里的中英文切换问题：打开终端、编辑器或代码工具时自动切到英文输入法，减少手动切换。

## 功能

- 菜单栏常驻运行
- 按应用 Bundle ID 匹配规则
- 为每个应用指定目标输入法
- 支持默认输入法 fallback
- 支持搜索应用规则
- 支持本地 JSON 配置

## 系统要求

- macOS 13 或更高版本
- Swift 6 / Xcode Command Line Tools
- 已在系统设置中启用需要切换的输入法

## 使用

1. 构建或下载 `AutoInput.app`。
2. 打开应用后，它会出现在菜单栏。
3. 点击菜单栏图标，进入 `设置`。
4. 设置默认输入法，并为应用添加专属规则。

配置文件位置：

```text
~/Library/Application Support/AutoInput/config.json
```

## 本地构建

运行核心测试：

```bash
export SWIFTPM_CACHE_PATH="$PWD/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift run AutoInputCoreTests
```

构建可执行文件：

```bash
export SWIFTPM_CACHE_PATH="$PWD/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build --product AutoInput
```

打包 `.app`：

```bash
Scripts/build_app.sh
```

打包脚本会把根目录的 `logo.png` 转成 `AutoInput.icns`，并写入应用图标。

输出路径：

```text
dist/AutoInput.app
```

生成 DMG 安装包：

```bash
Scripts/build_dmg.sh
```

输出路径：

```text
dist/AutoInput-0.1.0-macOS.dmg
```

本地签名和校验：

```bash
codesign --force --deep --sign - dist/AutoInput.app
codesign --verify --deep --strict dist/AutoInput.app
plutil -lint dist/AutoInput.app/Contents/Info.plist
```

## CI

GitHub Actions 工作流位于：

```text
.github/workflows/build.yml
.github/workflows/release.yml
```

`build.yml` 会在 PR、`main` / `master` 推送和手动触发时执行：

- 核心测试
- Debug 编译
- Release 打包
- Ad-hoc 签名
- Bundle 校验
- 上传 zip 和 dmg artifact

`release.yml` 会在推送版本 tag 时自动发布 Release：

- tag 格式：`v0.1.0`、`v1.2.3`
- 产物：`AutoInput-<tag>-macOS.zip`、`AutoInput-<tag>-macOS.dmg`
- 校验文件：`.zip.sha256`、`.dmg.sha256`

发布一个新版本：

```bash
git checkout main
git pull
git tag v0.1.0
git push origin v0.1.0
```

如果通过 PR 发布，推荐流程是：

1. 创建 PR，等待 `Build AutoInput` 通过。
2. 合并 PR 到 `main`。
3. 在合并后的 commit 上创建并推送 `v*.*.*` tag。
4. GitHub Actions 自动创建 Release，并上传 zip/dmg 安装包。

## 当前限制

- 当前版本只支持按应用切换。
- 输入法必须先在 macOS 系统设置中启用。
- `英文标点` 目前作为规则偏好保存，后续可扩展为更细的输入行为控制。
- CI 产物使用 ad-hoc 签名，正式分发仍建议使用 Apple Developer ID 签名和 notarization。
