# Car Rental Optimizer — 租车比价助手

[![Release](https://img.shields.io/github/v/release/sunnyhot/car-rental-optimizer?label=Release)](https://github.com/sunnyhot/car-rental-optimizer/releases/latest)
[![CI](https://github.com/sunnyhot/car-rental-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/sunnyhot/car-rental-optimizer/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)

macOS 原生桌面应用，静默调用一嗨和神州官方接口，比较**真实租车总成本**（租车费 + 到店路线估算）。

## 为什么是租车比价助手

- **可信数据优先**：只展示官方接口返回的真实方案——没有官方结果时不给推测价格，宁缺毋滥
- **总成本视角**：不只比租车费，MapKit 估算到店打车/公交成本与跨城/异店风险一起算
- **静默查询**：不要求打开平台页面或粘贴搜索结果；神州 H5 网关匿名直调，一嗨先匿名请求、仅 401 时才提示登录
- **价格监控**：心仪方案一键创建监控，后台巡查降价与到期，历史趋势一目了然

## 安装

推荐 Homebrew（自动跟随最新 Release，且不受 Gatekeeper 未公证拦截）：

```bash
brew tap sunnyhot/tap
brew install --cask sunnyhot/tap/car-rental-optimizer
```

或从 [GitHub Releases](https://github.com/sunnyhot/car-rental-optimizer/releases/latest) 下载 zip，用 `scripts/install-local-app.sh` 安装（见下方「安装本机测试包」）。

## 快速上手

1. 左栏输入取车位置、取还日期、车型与搜索半径
2. 中间查看候选方案与报价可信度标签，右侧看推荐总价、费用拆分与到店成本
3. 心仪方案一键「创建价格监控」，之后在监控中心（`⇧⌘M`）跟踪降价与到期

## 功能

### 三栏比价工作区
- 左侧输入位置、取还车日期、车型、半径、还车方式和平台选择
- 中间展示静默 API 查询出的候选方案；平台未开放、无车、需登录、需验证码或接口失败显示为平台状态
- 右侧展示推荐总价、租车费用拆分、打车/公共交通到店估算和跨城提醒
- 每次搜索显示诊断摘要：已查平台、成功平台、原始报价数、可见结果数和路线估算状态
- 平台失败、登录失效、验证码或解析失败时给出可执行的恢复建议；上次搜索成功则保留候选并明确标记为历史结果

### 报价可信度
候选方案和详情页使用统一的可信度标签：完整报价 / 部分费用待复核 / 路线估算缺失 / 跨城·异店风险——下单前该注意什么一目了然。

### 价格监控中心
- 按需处理、监控中、已暂停、已过期筛选；默认把需处理、近期降价、临近取车和到期巡查排在前面
- 顶部健康摘要：需处理数量、近 24 小时降价、今日巡查和后台巡查状态
- 识别连续失败与失败后的恢复事件；历史趋势展示最近价格、高低点、相比上次与首次的变化
- 支持手动指定车型、批量暂停/恢复当前筛选、立即巡查，以及应用保持运行时的后台巡查开关

### 登录与恢复
- 一嗨库存报价返回登录态 401 时提供一嗨登录入口；神州确认页费用接口需要登录时提供神州登录入口
- 登录后 session cookie 保存在本机 Application Support，覆盖安装或重启后自动恢复

### 效率与更新
- 快捷键：`⌘R` 重新比较，`⇧⌘R` 立即巡查到期监控，`⇧⌘M` 打开监控中心
- 菜单「检查更新…」读取 GitHub Release，发现新版本后自动下载、替换安装并重启

### 数据边界
原生版本不使用内置车源数据生成生产推荐，不要求用户复制搜索结果；没有官方接口结果时不会给出推测价格或候选车源。价格监控同样只基于官方接口结果记录历史快照；历史报价会标记为可能失效，最终下单前仍应打开平台复核实时价格。

## 构建（Swift/SwiftUI）

### 前置条件

- macOS 14 (Sonoma) 或更高版本
- Xcode Command Line Tools（`xcode-select --install`）
- Swift 6.0+（`swift --version` 确认）

### 构建 / 运行 / 测试

```bash
swift build
swift run CarRentalOptimizer
swift test
```

### 安装本机测试包

GitHub Release 里的当前 ZIP 是本机测试包。macOS 会对浏览器下载的应用加 quarantine；如果没有 Developer ID 签名和公证，直接双击可能被 Gatekeeper 拦截。

本机测试安装请用：

```bash
scripts/install-local-app.sh build/CarRentalOptimizer-v<version>.zip
```

或下载 release 后：

```bash
scripts/install-local-app.sh ~/Downloads/CarRentalOptimizer-v<version>.zip
```

脚本会复制到 `/Applications/租车比价助手.app`、清除 quarantine、把真实可执行文件安装到
`~/Library/Application Support/CarRentalOptimizer/runtime/`，再验证 bundle 并做一次启动 smoke test。
一嗨和神州登录 cookie 会保存在同一 Application Support 目录下的独立文件，覆盖安装不会清掉它们。

## 项目结构

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
