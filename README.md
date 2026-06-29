# Car Rental Optimizer — 租车比价助手

macOS 原生桌面应用，静默调用一嗨和神州官方接口，比较真实租车总成本（租车费 + 到店路线估算）。

## 构建（Swift/SwiftUI）

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

GitHub Release 里的当前 ZIP 是本机测试包。macOS 会对浏览器下载的应用加 quarantine；如果没有 Developer ID 签名和公证，直接双击可能被 Gatekeeper 拦截。

本机测试安装请用：

```bash
scripts/install-local-app.sh build/CarRentalOptimizer-v0.9.2.zip
```

或下载 release 后：

```bash
scripts/install-local-app.sh ~/Downloads/CarRentalOptimizer-v0.9.2.zip
```

脚本会复制到 `/Applications/租车比价助手.app`、清除 quarantine、把真实可执行文件安装到
`~/Library/Application Support/CarRentalOptimizer/runtime/`，再验证 bundle 并做一次启动 smoke test。
一嗨和神州登录 cookie 会保存在同一 Application Support 目录下的独立文件，覆盖安装不会清掉它们。

### 运行测试

```bash
swift test
```

### 当前能力

原生版本现在是可信数据优先的三栏比价工具：

- 左侧输入位置、取还车日期、车型、半径、还车方式和平台选择。
- 中间展示静默 API 查询出的候选方案，不要求用户打开平台页面或粘贴搜索结果。
- 候选区只展示官方接口返回的真实方案；平台未开放、无车、需登录、需验证码或接口失败会显示为平台状态。
- 查询结果会显示本次搜索诊断摘要：已查平台、成功平台、原始报价数、可见结果数和路线估算状态。
- 平台失败、登录失效、验证码或解析失败时，会给出可执行的恢复建议；如果上次搜索成功，界面会保留上次候选并明确标记为历史结果。
- 候选方案和详情页使用统一的报价可信度标签，说明完整报价、部分费用待复核、路线估算缺失或跨城/异店风险。
- 右侧展示推荐总价、租车费用拆分、打车/公共交通到店估算和跨城提醒。
- 候选方案和详情页可一键创建价格监控，记录租车时间、车型、平台和门店匹配信息。
- 「监控中心」会按需处理、监控中、已暂停和已过期筛选监控，默认把需处理、近期降价、临近取车和到期巡查排在前面。
- 监控中心顶部展示健康摘要：需处理数量、近 24 小时降价、今日巡查和后台巡查状态。
- 监控会识别连续失败和失败后的恢复事件，并在历史趋势中展示最近价格、历史高低点、相比上次和首次的变化。
- 监控支持手动指定车型、批量暂停/恢复当前筛选、立即巡查当前筛选，以及应用保持运行时的后台巡查开关。
- 菜单快捷键支持 `⌘R` 重新比较，`⇧⌘R` 立即巡查到期监控，`⇧⌘M` 打开监控中心。
- 菜单「检查更新…」会读取 GitHub Release；发现新版本后可自动下载、替换安装并重启。
- 一嗨库存报价如果返回登录态 401，左侧平台状态会提供一嗨登录入口；神州确认页费用接口需要登录时会提供神州登录入口。登录后会保存对应平台 session cookie 到本机 Application Support，并在覆盖安装或重启后自动恢复。

原生版本不再使用内置车源数据生成生产推荐，也不需要用户复制搜索结果。没有官方接口结果时，应用不会给出推测价格或候选车源。神州城市、门店和车型价格使用 H5 网关匿名直调；一嗨城市和门店可匿名读取，库存报价会先匿名请求，只有平台明确返回 401 时才提示登录。路线成本使用 MapKit 路线距离估算，用于辅助比较到店成本。
价格监控同样只基于官方接口结果记录历史快照；历史报价会标记为可能失效，最终下单前仍应打开平台复核实时价格。

### 项目结构

```
Package.swift                              # Swift Package Manager 配置
Sources/CarRentalOptimizer/
├── App.swift                              # @main SwiftUI 应用入口
├── AppInfo.swift                          # 应用名、版本号等常量
├── ContentView.swift                      # 原生工作区入口
├── SearchViewModel.swift                  # 地理编码、平台状态与比价流程
├── Monitor*.swift                         # 价格监控存储、调度、通知、中心页与创建表单
├── LiveRentalSearchService.swift          # 神州 H5 API 和一嗨 WebKit 加密 API 桥接
├── AddressGeocoder.swift / AppleMapService.swift
├── PlatformBrowser*.swift                 # 历史页面证据读取组件，保留给测试/兼容
├── *PanelView.swift                       # 搜索、结果、明细视图
└── EstimatedMapService.swift              # MapKit 不可用时的路线成本兜底
Sources/CarRentalDomain/
└── *.swift                                # 平台证据解析、车型匹配、价格监控、距离、排序、搜索编排等领域逻辑
Tests/CarRentalOptimizerTests/
└── *.swift                                # 原生应用与 ViewModel 测试
```

原生领域逻辑和 ViewModel 均有测试覆盖，`swift test` 可验证当前可运行状态。
