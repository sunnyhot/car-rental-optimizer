# Changelog

## [0.2.1] - 2026-05-28

### Fixed
- 修复 macOS 应用打开报错"可能已损坏或不完整"：build-app.sh 添加 codesign ad-hoc 签名步骤（签名 Sparkle.framework → 签名整个 bundle → 验证签名 → 清除隔离属性）

## [0.2.0] - 2026-05-28

### Added
- 原生 macOS SwiftUI 应用骨架
- 核心功能：租车成本比较与推荐
- Sparkle 2 自动更新集成
