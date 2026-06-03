# Changelog

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
