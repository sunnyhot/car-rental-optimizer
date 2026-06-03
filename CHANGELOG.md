# Changelog

## [0.6.0] - 2026-06-03

### Added
- 新增静默 API 数据工作流：神州使用 H5 官方网关直接读取城市、门店和车型价格；一嗨使用隐藏 WebKit 调官方加密 API。
- 新增地址地理编码和 MapKit 路线距离，用于把打车/公共交通成本纳入总成本排序。
- 车型为空时自动忽略半径、选最近取车点，并按车型去重保留最低总成本。

### Changed
- 主界面移除内嵌官方页面区域，搜索时不再要求用户切换页面或粘贴结果。
- 一嗨库存接口会先匿名请求；只有平台响应体明确返回 401 时才提示需要登录 cookie，不会伪造一嗨价格。
- 升级 release 安装脚本默认版本为 v0.6.0。

## [0.5.2] - 2026-06-03

### Added
- 原生 SwiftUI 版本新增内嵌一嗨/神州官方页面，搜索时自动读取当前页面文本并解析候选方案，不再要求用户复制搜索结果。

### Changed
- 检查更新改为只读取 GitHub Releases latest 页面跳转，不再请求 `api.github.com`。
- 更新 release 安装脚本默认版本为 v0.5.2。

## [0.5.1] - 2026-06-03

### Fixed
- 检查更新增加 GitHub `/releases/latest` 重定向兜底；即使 GitHub API 匿名请求被限流，也能从最新 release tag 判断是否有新版本。
- 更新 release 安装脚本默认版本为 v0.5.1。

## [0.5.0] - 2026-06-03

### Added
- 新增应用内“检查更新…”菜单，直接检测 GitHub 最新 Release。
- 新增版本比较逻辑和更新检测测试，覆盖新版、已是最新版、网络失败场景。

### Changed
- 继续保持无 Sparkle 运行时依赖，避免 ad-hoc 包重新触发未公证框架拦截。
- 更新 release 安装脚本默认版本为 v0.5.0。

## [0.4.0] - 2026-06-03

### Added
- 原生应用改名为「租车比价助手」，新增 macOS app icon。
- 新增官方页面证据解析和平台状态：等待证据、可用、未开放/无车、需登录、需验证码、解析失败。

### Changed
- 原生 SwiftUI 生产入口移除内置车源数据，不再生成一嗨/神州推测候选方案。
- 日期选择改为仅年月日，取车日期不能早于当天，还车日期不能早于取车日期。
- 路线成本明确标为本地估算，和官方租车证据区分展示。

### Removed
- 删除废弃的根目录 Swift 副本，避免旧实现被误用。

## [0.3.3] - 2026-06-03

### Fixed
- 移除发布版 Sparkle 动态框架依赖，避免未公证 ad-hoc 下载包在启动时被 Gatekeeper 拒绝加载嵌入框架
- 发布验证新增 ad-hoc 包不得链接 Sparkle.framework 的检查

### Changed
- 暂停应用内自动更新菜单；待 Developer ID 签名和 notarization 配置完成后再恢复

## [0.3.2] - 2026-06-03

### Fixed
- 补齐 macOS app bundle 标准元信息，避免 Gatekeeper/LaunchServices 将包识别为非标准 bundle
- 发布包验证新增 bundle 元信息检查，覆盖 `CFBundlePackageType` 和 `CFBundleInfoDictionaryVersion`

## [0.3.1] - 2026-06-03

### Fixed
- 修复 GitHub Release ZIP 解压后 Sparkle.framework 符号链接丢失，导致 macOS 提示应用已损坏无法打开
- 发布包验证新增 ZIP 解压回归检查，确保压缩包 round-trip 后 app bundle 签名仍有效

## [0.3.0] - 2026-06-02

### Added
- 接通原生 SwiftUI 三栏比价工作区，`swift run CarRentalOptimizer` 可直接查询 Mock 候选方案
- 新增原生搜索 ViewModel、一嗨/神州 Mock 车源、Mock 路线成本和推荐明细展示
- 新增 ViewModel 回归测试，覆盖默认搜索能返回排序结果并选中首条候选

### Changed
- README 更新为当前原生 Mock 比价工具状态，不再描述为占位骨架

## [0.2.4] - 2026-05-29

### Fixed
- 修复 macOS 应用打开报错"可能已损坏或不完整"：在 Info.plist 中添加 CFBundleExecutable 键（macOS LaunchServices 依赖此字段定位可执行文件）


## [0.2.3] - 2026-05-29

### Fixed
- 修复 Release workflow 构建失败：添加 Xcode 版本选择步骤（与 CI workflow 一致）
- 修复 Release workflow 中文路径编码问题：添加 UTF-8 locale 环境变量
- 修复 CI 管道 `| tee` 吞噬 exit code：添加 `set -o pipefail`（ci.yml + release.yml）
- 修复 ZIP 打包中文文件名兼容性：使用 Python zipfile 替代系统 zip 命令
- 修复 codesign 验证：ad-hoc 签名使用非严格模式
- 同步 AppInfo.swift 版本号与 Info.plist
- 修复 Swift concurrency 编译错误：CarRentalOptimizerApp 添加 @MainActor 注解（CI macos-14 Xcode 15.4 严格执行并发检查）

## [0.2.2] - 2026-05-28

### Added
- GitHub Actions CI workflow（构建验证 PR）
- GitHub Actions Release workflow（自动构建、打包 zip、shasum、创建 GitHub Release 并上传产物）

## [0.2.1] - 2026-05-28

### Fixed
- 修复 macOS 应用打开报错"可能已损坏或不完整"：build-app.sh 添加 codesign ad-hoc 签名步骤（签名 Sparkle.framework → 签名整个 bundle → 验证签名 → 清除隔离属性）

## [0.2.0] - 2026-05-28

### Added
- 原生 macOS SwiftUI 应用骨架
- 核心功能：租车成本比较与推荐
- Sparkle 2 自动更新集成
