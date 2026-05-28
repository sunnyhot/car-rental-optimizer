# Car Rental Optimizer — 租车总成本比较

macOS 原生桌面应用，自动比较一嗨和神州租车的总取车成本（含租车费 + 到店交通费）。

## 原生构建（Swift/SwiftUI）

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode Command Line Tools（`xcode-select --install`）
- Swift 6.0+（`swift --version` 确认）

### 构建

```bash
swift build
```

### 运行

```bash
swift run CarRentalOptimizer
```

### 运行测试

```bash
swift test
```

### 项目结构

```
Package.swift                              # Swift Package Manager 配置
Sources/CarRentalOptimizer/
├── App.swift                              # @main SwiftUI 应用入口
├── AppInfo.swift                          # 应用名、版本号等常量
└── ContentView.swift                      # 三栏布局主界面骨架
Tests/CarRentalOptimizerTests/
└── AppInfoTests.swift                     # 基础测试
```

当前为原生骨架阶段，提供三栏布局占位界面（搜索条件 / 候选方案 / 推荐明细），后续任务将逐步迁移业务逻辑。

---

## Electron 版本（保留，计划废弃）

### 保留原因

Electron 版本曾是唯一的桌面运行入口，包含完整业务逻辑（平台自动化、页面解析、比价排序）。
原生版本尚处于骨架阶段，尚未迁移这些功能。在此期间保留 Electron 入口以保证功能可用。

### Electron 构建

```bash
npm install
npm run dev          # 开发模式
npm run build        # 生产构建
npm test             # 运行测试
```

### 废弃计划

| 阶段 | 内容 | 状态 |
|------|------|------|
| 1 | 原生 SwiftUI 骨架搭建 | ✅ 已完成 |
| 2 | 迁移领域逻辑（车型匹配、费用排序）到 Swift | 待执行 |
| 3 | 迁移平台自动化（登录态管理、页面解析）到 Swift | 待执行 |
| 4 | 迁移完整 UI 到 SwiftUI | 待执行 |
| 5 | 移除 Electron 依赖（删除 `electron/`、`src/`、`package.json`） | 待全部迁移后执行 |

在阶段 5 完成前，`package.json` 和 `electron/` 目录将继续保留在仓库中。
