# Car Rental Optimizer — 租车比价助手

macOS 原生桌面应用，静默调用一嗨和神州官方接口，比较真实租车总成本（租车费 + 到店路线估算）。

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

### 安装本机测试包

GitHub Release 里的当前 ZIP 是 ad-hoc 签名包。macOS 会对浏览器下载的应用加 quarantine；如果没有 Developer ID 签名和公证，直接双击可能被 Gatekeeper 拦截。

本机测试安装请用：

```bash
scripts/install-local-app.sh build/CarRentalOptimizer-v0.6.10.zip
```

或下载 release 后：

```bash
scripts/install-local-app.sh ~/Downloads/CarRentalOptimizer-v0.6.10.zip
```

脚本会复制到 `/Applications/租车比价助手.app`、清除 quarantine、验证 bundle，并做一次启动 smoke test。

### 运行测试

```bash
swift test
```

### 当前能力

原生版本现在是可信数据优先的三栏比价工具：

- 左侧输入位置、取还车日期、车型、半径、还车方式和平台选择。
- 中间展示静默 API 查询出的候选方案，不要求用户打开平台页面或粘贴搜索结果。
- 候选区只展示官方接口返回的真实方案；平台未开放、无车、需登录、需验证码或接口失败会显示为平台状态。
- 右侧展示推荐总价、租车费用拆分、打车/公共交通到店估算和跨城提醒。
- 菜单「检查更新…」会读取 GitHub Release；发现新版本后可自动下载、替换安装并重启。
- 一嗨库存报价如果返回登录态 401，左侧平台状态会提供一嗨登录入口；登录后 cookie 保存在本应用 WebKit 数据中，后续查询会静默复用。

原生版本不再使用内置车源数据生成生产推荐，也不需要用户复制搜索结果。没有官方接口结果时，应用不会给出推测价格或候选车源。神州城市、门店和车型价格使用 H5 网关匿名直调；一嗨城市和门店可匿名读取，库存报价会先匿名请求，只有平台明确返回 401 时才提示登录。路线成本使用 MapKit 路线距离估算，用于辅助比较到店成本。

### 项目结构

```
Package.swift                              # Swift Package Manager 配置
Sources/CarRentalOptimizer/
├── App.swift                              # @main SwiftUI 应用入口
├── AppInfo.swift                          # 应用名、版本号等常量
├── ContentView.swift                      # 原生工作区入口
├── SearchViewModel.swift                  # 地理编码、平台状态与比价流程
├── LiveRentalSearchService.swift          # 神州 H5 API 和一嗨 WebKit 加密 API 桥接
├── AddressGeocoder.swift / AppleMapService.swift
├── PlatformBrowser*.swift                 # 历史页面证据读取组件，保留给测试/兼容
├── *PanelView.swift                       # 搜索、结果、明细视图
└── EstimatedMapService.swift              # MapKit 不可用时的路线成本兜底
Sources/CarRentalDomain/
└── *.swift                                # 平台证据解析、车型匹配、距离、排序、搜索编排等领域逻辑
Tests/CarRentalOptimizerTests/
└── *.swift                                # 原生应用与 ViewModel 测试
```

原生领域逻辑和 ViewModel 均有测试覆盖，`swift test` 可验证当前可运行状态。

---

## Electron 版本（保留，计划废弃）

### 保留原因

Electron 版本曾是唯一的桌面运行入口，包含完整业务逻辑（平台自动化、页面解析、比价排序）。
原生版本已具备静默官方 API 查询、平台状态识别和真实候选排序。Electron 版本仅作为历史实验入口保留，后续可删除。

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
| 3 | 迁移平台自动化（登录态管理、页面读取）到 Swift | ✅ 已完成 |
| 4 | 迁移完整 UI 到 SwiftUI | ✅ 静默 API 查询工作流已完成 |
| 5 | 移除 Electron 依赖（删除 `electron/`、`src/`、`package.json`） | 待全部迁移后执行 |

在阶段 5 完成前，`package.json` 和 `electron/` 目录将继续保留在仓库中。
