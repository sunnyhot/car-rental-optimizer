# 发布与更新指南（原生 macOS + GitHub Release）

本文档说明如何打包、签名、发布和验证 Car Rental Optimizer 原生 macOS 应用的更新。

## 目录

1. [架构概览](#架构概览)
2. [版本号管理](#版本号管理)
3. [生成 EdDSA 签名密钥](#生成-eddsa-签名密钥)
4. [打包构建](#打包构建)
5. [代码签名与公证（macOS）](#代码签名与公证macos)
6. [生成 appcast](#生成-appcast)
7. [发布到 GitHub Pages](#发布到-github-pages)
8. [更新检查流程](#更新检查流程)
9. [手动验证更新](#手动验证更新)
10. [故障排查](#故障排查)
11. [相关文件](#相关文件)

---

## 架构概览

当前发布包使用 GitHub Release ZIP 分发。应用内「检查更新…」通过 GitHub latest release 跳转获取新版本号，发现新版本后直接下载约定命名的 ZIP 包，解压并校验 `.app`，然后启动独立安装脚本，在当前应用退出后替换安装并重新打开。

Sparkle 2 的 appcast 方案仍保留为未来选项；在没有 Developer ID 签名和 notarization 前，发布版不嵌入 Sparkle.framework，避免 ad-hoc 下载包被 Gatekeeper 拒绝加载嵌入框架。

```
┌───────────────────┐         ┌────────────────────────┐
│  SwiftUI App Menu │         │ GitHub Release latest  │
│  检查更新… (Cmd+U)│────────▶│ HEAD redirect/tag read │
│                   │         └──────────┬─────────────┘
└─────────┬─────────┘                    │
          │                              ▼
          │                 ┌──────────────────────────┐
          └────────────────▶│ Release ZIP asset        │
                            │ download / verify / swap │
                            └──────────────────────────┘
```

**更新框架**: 自定义轻量安装器（`UpdateChecker` + `MacReleaseInstaller`）
**更新源**: GitHub Release latest + `CarRentalOptimizer-vX.Y.Z.zip`
**更新触发**: 手动（菜单「检查更新…」）
**签名方案**: 当前为 ad-hoc codesign 校验；Developer ID + notarization 为后续正式分发方向

## 版本号管理

版本号定义在两个位置，**必须保持一致**：

1. `Sources/CarRentalOptimizer/AppInfo.swift` — `AppInfo.version`
2. `native/Info.plist` — `CFBundleShortVersionString` + `CFBundleVersion`

### 版本号规范

| 变更类型 | 版本号变更 | 示例 |
|---------|-----------|------|
| 修复 bug | PATCH +1 | 0.2.0 → 0.2.1 |
| 新增功能 | MINOR +1 | 0.2.0 → 0.3.0 |
| 重大变更 | MAJOR +1 | 0.2.0 → 1.0.0 |

⚠️ `CFBundleVersion`（build number）每次发版必须递增（如 1 → 2 → 3）。当前更新检查用 semantic version 判断新旧，build number 用于 macOS bundle 版本一致性和未来 Sparkle 兼容。

## 生成 EdDSA 签名密钥

Sparkle 使用 Ed25519 签名验证更新包的完整性。

### 首次设置（只需一次）

```bash
# 1. 构建 Sparkle 工具（自动解析 SPM 依赖后）
swift build

# 2. 生成密钥对
# 工具路径取决于 SPM 缓存位置，通常在：
.build/release/generate_keys
# 或从 Sparkle 分发包的 bin/ 目录获取

# 运行后输出示例：
# A key has been generated and saved in your keychain.
# Add the SUPublicEDKey key to the Info.plist:
# SUPublicEDKey
# pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=
```

### 配置公钥

将输出的公钥字符串填入 `Info.plist` 的 `SUPublicEDKey` 字段：

```xml
<key>SUPublicEDKey</key>
<string>你的公钥字符串</string>
```

### 密钥安全

- **私钥** 存储在你的 Mac 钥匙串中，**绝不要提交到 git**
- 如需在另一台 Mac 使用，用 `-x` / `-f` 选项导出/导入
- 丢失密钥后可通过 Developer ID 签名进行密钥轮换（见 Sparkle 文档）

## 打包构建

### 方式一：Xcode Archive（推荐）

```bash
# 使用 Xcode 打开生成的 .xcodeproj（或直接用 xcodebuild）
xcodebuild archive \
    -scheme CarRentalOptimizer \
    -archivePath build/CarRentalOptimizer.xcarchive

xcodebuild -exportArchive \
    -archivePath build/CarRentalOptimizer.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist
```

### 方式二：swift build + 手动打包

```bash
# 构建 Release 配置
swift build -c release

# 产物位于 .build/release/CarRentalOptimizer

# 创建 .app bundle 目录结构
mkdir -p "build/租车比价助手.app/Contents/MacOS"
mkdir -p "build/租车比价助手.app/Contents/Frameworks"
mkdir -p "build/租车比价助手.app/Contents/Resources"

# 复制可执行文件
cp .build/release/CarRentalOptimizer "build/租车比价助手.app/Contents/MacOS/"

# 复制 Info.plist
cp native/Info.plist "build/租车比价助手.app/Contents/"

# 复制 Sparkle.framework
cp -R .build/release/Sparkle.framework "build/租车比价助手.app/Contents/Frameworks/"

# 创建 DMG
hdiutil create -volname "租车比价助手" \
    -srcfolder "build/租车比价助手.app" \
    -ov -format UDZO \
    "build/CarRentalOptimizer-0.2.0.dmg"
```

### 方式三：用 Sparkle 自带工具辅助

如果通过 Xcode 项目集成，可以直接使用 Xcode 的 Product → Archive 流程。

## 代码签名与公证（macOS）

### Gatekeeper 结论

ad-hoc 签名只证明 bundle 内部结构自洽，不能让浏览器下载的应用通过 Gatekeeper。被 Safari、Chrome 或 GitHub 网页下载后的 ZIP 会带 quarantine，解压出的 app 首次双击会被 `spctl` 拒绝：

```bash
spctl --assess --type execute --verbose=4 "租车比价助手.app"
# 租车比价助手.app: rejected
```

这不是 SwiftUI 崩溃，也不是 Info.plist 损坏。面向其他用户的“下载后双击打开”分发必须使用 Developer ID Application 证书签名，并完成 Apple notarization。没有有效 Developer ID 证书时，只能用于本机测试或让用户明确执行 quarantine 清理。

本机测试安装：

```bash
scripts/install-local-app.sh build/CarRentalOptimizer-v0.8.3.zip
```

启动 smoke test：

```bash
scripts/verify-launch.sh /Applications/租车比价助手.app
```

### 签名（推荐，生产环境）

```bash
# Developer ID 签名
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    --options runtime \
    "build/租车比价助手.app"

# 验证签名
codesign --deep --verify --strict "build/租车比价助手.app"
```

### 公证（Notarization）

```bash
# 提交公证
xcrun notarytool submit "build/CarRentalOptimizer-0.2.0.dmg" \
    --apple-id "your@email.com" \
    --team-id "TEAMID" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# 装订公证票据
xcrun stapler staple "build/CarRentalOptimizer-0.2.0.dmg"
```

### 不签名（仅开发/测试）

未签名的应用能正常运行更新检查，但 macOS Gatekeeper 会警告。
用户需要右键 → 打开来绕过 Gatekeeper。

## 生成 appcast

### 自动生成（推荐）

```bash
# 1. 将所有版本的 DMG/ZIP 放入同一目录
mkdir -p update_archives
cp build/CarRentalOptimizer-0.2.0.dmg update_archives/

# 2. 运行 generate_appcast（Sparkle 工具）
generate_appcast update_archives/

# 3. 生成产物：
#    update_archives/appcast.xml  — 更新 feed
#    update_archives/*.delta       — 增量更新包
```

### appcast.xml 结构参考

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>租车比价助手 更新</title>
    <item>
      <title>版本 0.2.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://sunnyhot.github.io/car-rental-optimizer/CarRentalOptimizer-0.2.0.dmg"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream"
      />
      <description>
        <![CDATA[
          <h2>新功能</h2>
          <ul><li>Sparkle 自动更新集成</li></ul>
        ]]>
      </description>
    </item>
  </channel>
</rss>
```

## 发布到 GitHub Pages

### 方案：使用 `gh-pages` 分支托管 appcast + 更新包

```bash
# 1. 创建/切换到 gh-pages 分支
git checkout --orphan gh-pages
git rm -rf .

# 2. 复制 appcast 和更新包
cp update_archives/appcast.xml .
cp update_archives/CarRentalOptimizer-*.dmg .

# 3. 推送
git add .
git commit -m "Publish appcast v0.2.0"
git push origin gh-pages
```

### GitHub Pages 配置

在 GitHub 仓库 Settings → Pages 中：
- Source: Deploy from a branch
- Branch: `gh-pages` / `/ (root)`

发布后 appcast URL 为：
`https://sunnyhot.github.io/car-rental-optimizer/appcast.xml`

此 URL 已配置在 `Info.plist` 的 `SUFeedURL` 中。

## 更新检查流程

### 自动检查

- Sparkle 在 App 启动后自动初始化
- 默认每 **24 小时**在后台检查一次更新（首次启动不检查，避免打扰用户）
- 发现新版本后弹出更新提示窗口

### 手动检查

- 点击菜单栏 **租车比价助手** → **检查更新…**
- 立即检查是否有新版本
- 菜单项在更新检查进行时自动禁用（由 `canCheckForUpdates` 属性控制）

### 未配置更新源时的行为

- 如果 `appcast.xml` 不存在（如 `SUFeedURL` 指向的 URL 返回 404），Sparkle 会静默失败
- **不会崩溃**，不会弹出错误窗口
- 用户点击「检查更新…」时可能显示"无法检查更新"提示
- 日志输出到 Console.app，搜索 `Sparkle` 或 bundle ID 查看详情

## 手动验证更新

### 前提条件

1. 已生成 EdDSA 密钥并配置公钥到 `Info.plist`
2. 已发布 `appcast.xml` 和更新包到 GitHub Pages

### 验证步骤

```bash
# 1. 构建旧版本（如 0.1.0）
# 确保 CFBundleVersion 低于新版

# 2. 构建并发布新版本（如 0.2.0）
swift build -c release
# 打包 → 签名 → generate_appcast → 推送到 gh-pages

# 3. 运行旧版本 App
# 4. 点击菜单 → 检查更新
# 5. 应弹出"发现新版本 0.2.0"提示
# 6. 点击安装 → App 自动下载并重启
```

### 快速测试技巧

```bash
# 清除上次检查时间（触发立即检查）
defaults delete com.carrental.optimizer SULastCheckTime

# 降低版本号用于测试
# 临时修改 Info.plist 中 CFBundleVersion 为 0
```

## 故障排查

### "检查更新"菜单项始终灰色

- Sparkle 尚未完成初始化（首次启动需要等一秒）
- 检查 Console.app 日志中 Sparkle 相关错误

### 无法检查更新 / 无法连接更新服务器

- 检查 `SUFeedURL` 配置的 URL 是否可访问
- `curl https://sunnyhot.github.io/car-rental-optimizer/appcast.xml`
- macOS Sequoia 本地网络隐私设置可能影响测试

### 更新下载后无法安装

- macOS Gatekeeper 阻止了未签名应用
- 解决：代码签名 + 公证（推荐）
- 或 `xattr -cr /path/to/app.app`（仅开发测试）

### EdDSA 签名验证失败

- 确认 `Info.plist` 中 `SUPublicEDKey` 与生成密钥时输出的公钥一致
- 确认 `generate_appcast` 运行时有访问钥匙串的权限
- 重新运行 `generate_appcast` 重新签名

### Sparkle.framework 加载失败

- 确认 `Sparkle.framework` 在 `Contents/Frameworks/` 中且符号链接完整
- 确认 Runpath Search Paths 包含 `@loader_path/../Frameworks`
- 使用 `otool -L` 检查可执行文件的动态库引用

## 相关文件

| 文件 | 说明 |
|------|------|
| `Package.swift` | SwiftPM 配置，含 Sparkle 依赖 |
| `Sources/CarRentalOptimizer/App.swift` | SwiftUI App 入口，集成 UpdaterManager |
| `Sources/CarRentalOptimizer/UpdaterManager.swift` | Sparkle 更新管理（ViewModel + Menu View + Controller） |
| `Sources/CarRentalOptimizer/AppInfo.swift` | 应用版本号常量 |
| `Sources/CarRentalOptimizer/Resources/Info.plist` | Sparkle 配置（SUFeedURL, SUPublicEDKey）+ 版本信息 |
| `appcast/appcast.xml` | 更新 feed 占位文件 |
| `docs/release-guide.md` | 本文档 |

### 需要人工配置的项

以下配置包含占位值，发布前必须替换：

1. `Info.plist` → `SUPublicEDKey`: 替换为 `generate_keys` 输出的真实公钥
2. `Info.plist` → `SUFeedURL`: 确认 URL 指向实际的 appcast 托管地址
3. `appcast/appcast.xml`: 需要用 `generate_appcast` 生成真实内容
4. 代码签名证书：需要有效的 Apple Developer ID（如需分发给其他用户）
