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

### 当前能力

原生版本现在是可运行的三栏比价工具：

- 左侧输入位置、取还车时间、车型、半径、还车方式和平台选择。
- 中间展示按总成本排序的候选方案。
- 右侧展示推荐总价、租车费用拆分、打车/公共交通到店成本和跨城提醒。

当前车源与路线成本使用内置 Mock 数据，适合先验证完整交互和排序逻辑。真实平台自动化仍保留在 Electron/React 版本中，后续可继续迁移到 Swift 原生服务。

### 项目结构

```
Package.swift                              # Swift Package Manager 配置
Sources/CarRentalOptimizer/
├── App.swift                              # @main SwiftUI 应用入口
├── AppInfo.swift                          # 应用名、版本号等常量
├── ContentView.swift                      # 原生工作区入口
├── SearchViewModel.swift                  # 搜索状态与 mock 比价流程
├── *PanelView.swift                       # 搜索、结果、明细三栏视图
├── MockRentalAdapters.swift               # 一嗨/神州模拟车源
└── MockMapService.swift                   # 模拟打车/公共交通成本
Sources/CarRentalDomain/
└── *.swift                                # 车型匹配、距离、排序、搜索编排等领域逻辑
Tests/CarRentalOptimizerTests/
└── *.swift                                # 原生应用与 ViewModel 测试
```

原生领域逻辑和 ViewModel 均有测试覆盖，`swift test` 可验证当前可运行状态。

---

## Electron 版本（保留，计划废弃）

### 保留原因

Electron 版本曾是唯一的桌面运行入口，包含完整业务逻辑（平台自动化、页面解析、比价排序）。
原生版本已具备 Mock 数据下的完整比价交互。Electron 版本仍保留真实平台窗口读取、页面解析等实验性能力，直到这些能力迁移到 Swift 原生服务。

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
| 2 | 迁移领域逻辑（车型匹配、费用排序）到 Swift | ✅ 已完成 |
| 3 | 迁移平台自动化（登录态管理、页面解析）到 Swift | 待执行 |
| 4 | 迁移完整 UI 到 SwiftUI | ✅ Mock 版本已完成 |
| 5 | 移除 Electron 依赖（删除 `electron/`、`src/`、`package.json`） | 待全部迁移后执行 |

在阶段 5 完成前，`package.json` 和 `electron/` 目录将继续保留在仓库中。
