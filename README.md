# Car Rental Optimizer — 租车比价助手

[![Release](https://img.shields.io/github/v/release/sunnyhot/car-rental-optimizer?label=Release)](https://github.com/sunnyhot/car-rental-optimizer/releases/latest)
[![CI](https://github.com/sunnyhot/car-rental-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/sunnyhot/car-rental-optimizer/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)

macOS 原生桌面应用，静默调用一嗨和神州官方接口，优先展示**平台确认应付金额**，并把到店交通估算单独列出。

## 为什么是租车比价助手

- **可信数据优先**：只展示官方接口返回的真实方案——没有官方结果时不给推测价格，宁缺毋滥
- **总成本视角**：不只比租车费，MapKit 估算到店打车/公交成本与跨城/异店风险一起算
- **登录核价**：可主动登录平台；神州登录后读取确认页应付总额，不再仅补基础服务费。一嗨未取得完整确认金额时仍标记部分报价
- **价格监控**：心仪方案一键创建监控，后台巡查降价与到期，历史趋势一目了然

## 安装

推荐 Homebrew（自动跟随最新 Release，且不受 Gatekeeper 未公证拦截）：

```bash
brew tap sunnyhot/tap
brew install --cask sunnyhot/tap/car-rental-optimizer
```

或从 [GitHub Releases](https://github.com/sunnyhot/car-rental-optimizer/releases/latest) 下载 zip，用 `scripts/install-local-app.sh` 安装（见下方「安装本机测试包」）。

## 快速上手

1. 启动后自动获取当前位置；设置取还时间、车型与搜索半径，可先点击“登录神州核价”完成官网登录
2. 点击“登录完成，重新比较”，查看“平台确认应付”、平台费用明细、核价时间；到店交通估算另列
3. 心仪方案一键「创建价格监控」，之后在监控中心（`⇧⌘M`）跟踪降价与到期

## 功能

### 三栏比价工作区
- 位置仅显示系统当前位置，可重新定位，不支持手动输入或下拉选择；定位未成功时不能开始搜索
- 设置车型、半径和平台；在双月日历选择取还日期，不再选择时分。通常默认 10:00 取还，当天取车用至少提前两小时的未来整点，跨日还车对齐取车时刻；同日默认 18:00 还车，具体时刻以界面文字为准
- 日历点击“确定”后才应用，取消或关闭不改原行程；默认时段无效时提示另选日期，不自动改变用户选择的日期；当前仅支持同店取还
- 中间展示静默 API 查询出的候选方案；平台未开放、无车、需登录、需验证码或接口失败显示为平台状态
- 右侧展示租车费用与到店估算；缺失费用显示“未确认/未单列”，不按免费解释，费用完整的方案优先
- 每次搜索显示诊断摘要：已查平台、成功平台、原始报价数、可见结果数和路线估算状态
- 一嗨指定车型查询只纳入当前城市和有坐标且在范围内的城市，优先探测当前城市最近 4 个门店；使用统一查询预算，慢请求不阻塞已完成报价，结果会说明已查范围
- 平台失败、登录失效、验证码或解析失败时给出可执行的恢复建议；上次搜索成功则保留候选并明确标记为历史结果

### 车型基础参数缓存

- 每次搜索完成后自动处理全部结果（不只当前筛选或点开的车辆），按车系去重；先用缓存，缺失或过期资料以最多两条资料请求并行补全，不阻塞报价。
- 显示处理进度和“尺寸齐全 / 部分 / 暂缺 / 待重试”统计，缺失资料可单独重试；尺寸齐全指长宽高、轴距，并不保证所有配置或具体年款已确认。
- 资料请求间隔至少 1 秒，遇到 HTTP 429 遵守 Retry-After 冷却，不继续向资料源发送请求，也不把限流误报成没有资料。
- 车长、车宽、车高、轴距等参考参数首次取得后保存本机；候选卡片直接显示车长/轴距，详情和对比区同步更新，重启或断网仍可查看。
- 30 天是刷新周期，不是删除期限；刷新失败继续使用旧资料并标记待更新，不以空字段覆盖已有参数。
- 只有简介、没有尺寸的缓存会继续尝试补全，失败后短时退避；同车型并发查看合并联网请求。
- 车型检索支持品牌别名和年款前缀；新能源、L、PLUS 等版本分开，车系参数不视作租赁车辆具体年款或配置保证。
- 能源版本不明确且车型库返回多个能源版本时，仅采用这些版本共同一致的尺寸，保留对照来源，不据此推断电池、续航或具体交付配置。

### 报价可信度
候选方案和详情页使用统一的可信度标签：完整报价 / 部分费用待复核 / 路线估算缺失 / 跨城·异店风险——下单前该注意什么一目了然。

### 可信比较边界

- 结果仅代表已查询门店，不是全网或整个半径内最低价；空车型查询聚焦最近有报价门店。
- 部分报价只提供已知费用，不是最终应付价；未确认费用的方案不标价格优势。
- 平台确认应付是当前预订方案的报价，不是已经支付或用车结束后的实际结算。平台可能根据保障、优惠、库存和时间重新计价。
- 到店交通是估算，不含还车后的接驳、油电、过路停车；不能据此承诺跨城净节省。
- 取还车时间必须明确，还车晚于取车；旧版只有日期的监控会暂停，需要确认时间后重新创建。

### 价格监控中心
- 按需处理、监控中、已暂停、已过期筛选；默认把需处理、近期降价、临近取车和到期巡查排在前面
- 顶部健康摘要：需处理数量、近 24 小时降价、今日巡查和后台巡查状态
- 原方案监控严格保持平台、门店、车型与配置标识；找不到原方案时记录未匹配，不自动换成便宜替代车
- 降价提醒与趋势仅使用同一方案、费用完整的快照；旧快照未保存可比性信息时不作为降价基准
- 识别连续失败与恢复事件；巡查中断后可恢复，不会永久停在“检查中”
- 支持手动指定车型、批量暂停/恢复当前筛选、巡查当前筛选内到期监控；未到期/暂停的监控会跳过并如实报告
- 后台巡查只在应用运行且开关开启时持续进行，退出后停止；降价提醒不代表扣除退订费后仍值得重订

### 真实接口诊断（开发）

默认 `swift test` 不运行真实接口探测。需要排查时显式设置 `CAR_RENTAL_LIVE_PROBE=1`、`CAR_RENTAL_PROBE_ORIGIN`、`CAR_RENTAL_PROBE_PICKUP` 和 `CAR_RENTAL_PROBE_RETURN`，运行 `swift test --filter LiveSearchDiagnosticsTests`。时间使用 `yyyy-MM-dd HH:mm`；诊断输出所选门店与返回数量，不记录 Cookie 或完整响应。

### 登录与恢复
- 登录入口始终可见，不必先遇到 401。密码和验证码在官网登录页自行填写，应用不自动下单或付款
- 神州有效确认页总额直接作为租车应付金额；费用明细只做说明，不再把服务费/整备费重复加到总额上
- 明细不全但平台返回了有效总额时，保留总额并提示明细可能未列全；未返回有效总额时继续显示已知费用
- 一嗨目前仍使用库存报价，登录成功不等于已取得完整确认价，不会把日价推算改标为实际应付
- 启动时仅补齐浏览器中缺失的有效 Cookie，不以旧快照覆盖较新会话；之后监听 Cookie 变化自动保存，正常退出前再同步，快照文件仅当前用户可读写
- 神州接口按目标域名、路径及 HTTPS 条件发送 Cookie；仅成功响应同步会话更新，拒绝认证或失败响应不会用匿名会话覆盖原值；认证请求不自动跟随重定向携带 Cookie
- 点击登录完成时若本地保存失败会提示。服务端已过期或撤销的会话不能靠保留 Cookie 恢复，仍需本人重新登录

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

界面验证可运行 `swift run CarRentalOptimizer --ui-validation`：不读取已有监控、不自动定位或巡查；不会注入模拟报价。

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
