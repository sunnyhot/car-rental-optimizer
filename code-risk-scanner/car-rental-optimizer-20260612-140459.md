# 项目分析与静态风险检测报告

## 扫描信息

| 项目 | 值 |
|------|-----|
| 项目名称 | car-rental-optimizer |
| 扫描时间 | 2026-06-12 14:04:59 CST |
| 扫描范围 | 整个项目，重点为 SwiftUI 原生主线、Electron 遗留链路、发布脚本与 CI |
| 关联需求/方案 | 否 |
| 扫描文件数 | 80 个代码/脚本/工作流文件 |
| 是否修改源码 | 否 |

## 项目概览

这是一个 macOS 租车比价桌面应用。当前主线是 SwiftUI 原生应用，静默调用神州 H5 网关和一嗨 WebKit 前端加密 API，按真实租车价加到店路线成本做推荐排序。Electron/Vite/React 版本仍保留在仓库中，但 README 已标记为计划废弃。

主要模块：

| 模块 | 作用 | 观察 |
|------|------|------|
| `Sources/CarRentalOptimizer` | SwiftUI App、ViewModel、平台 API、定位、更新器 | 生产主线 |
| `Sources/CarRentalDomain` | 搜索请求、车型匹配、排序、推荐、证据解析 | 领域逻辑较独立，测试较完整 |
| `Tests/CarRental*` | Swift XCTest + Swift Testing | 覆盖核心排序、日期、登录态、更新器 |
| `src/`、`electron/` | Electron 历史实现 | 仍有依赖安全风险和维护成本 |
| `scripts/`、`.github/workflows` | 打包、校验、发布 | 已有验证脚本，但版本同步仍手工 |

## 验证结果

| 命令 | 结果 | 说明 |
|------|------|------|
| `swift build` | 通过 | Swift 主线可构建 |
| `swift test` | 失败 | 45 个 Swift Testing 用例中 1 个日期测试失败；XCTest 29 个通过 |
| `swift test --filter AppDateRules` | 失败 | 复现同一问题 |
| `npm test` | 通过 | 8 个 Vitest 文件、26 个用例通过 |
| `npm audit --audit-level=moderate` | 失败 | 2 个 critical 漏洞，来自 Electron 遗留依赖链 |

## 问题统计

| 等级 | 数量 | 说明 |
|------|------|------|
| 高 | 2 | 阻断/安全风险 |
| 中 | 4 | 稳定性、维护性、体验增强 |
| 低 | 2 | 长期演进与清理 |
| 总计 | 8 | |

## 高优先级问题

### 1. Swift 测试存在时间敏感失败

**位置：** `Tests/CarRentalOptimizerTests/AppDateRulesTests.swift:25`

**现象：**

`normalizedRangeKeepsReturnDateLinkedToPickupDate` 使用固定取车日 `2026-06-10`。当前日期是 `2026-06-12`，而 `AppDateRules.normalizedRange` 会把过去的取车日归一到今天，所以期望值与实际值不一致。

**影响：**

- 当前 `swift test` 非全绿，会阻断 CI 或本地发版判断。
- 这是测试脆弱性，不是平台 API 故障。

**建议：**

给 `AppDateRules` 注入可控 `today`，或在测试中使用相对未来日期，避免测试随真实日期失效。

### 2. Electron 遗留依赖有 critical 安全漏洞

**位置：** `package.json` / `package-lock.json`

**证据：**

`npm audit` 报告 `concurrently@9.2.1 -> shell-quote@1.8.3` 存在 critical 漏洞，修复建议会升级到 `concurrently@10.0.3`，属于潜在 breaking change。

**影响：**

- 虽然生产主线是 SwiftUI，但保留 Node/Electron 依赖会持续带来审计噪声和安全维护成本。
- 如果继续支持 Electron 开发入口，需要升级并验证。

**建议：**

优先完成 README 中的阶段 5：删除或隔离 Electron/Vite/React 遗留链路。若短期不能删除，则升级 `concurrently` 并跑 `npm test`、`npm run build`。

## 中优先级增强点

### 3. 平台 API 桥接可观测性不足

`LiveRentalSearchService.swift` 同时包含神州 API、WebKit 生命周期、一嗨 JavaScript 桥接和解析逻辑，文件超过 1000 行。一嗨桥接脚本是一段大型字符串，已有测试多通过字符串包含断言保护关键逻辑。

**建议：**

- 将一嗨桥接脚本拆为独立资源或生成器，并把关键解析函数提取为可单测的 JS fixture。
- 为神州和一嗨保存脱敏的失败响应 shape、接口阶段、门店数、车型数，用于定位平台字段变动。
- 增加平台接口 contract fixture 测试，覆盖“城市列表、门店列表、库存报价、价格字段缺失、401、验证码”等分层场景。

### 4. 发布链路仍依赖多处手工同步

版本号需要同时维护 `AppInfo.swift`、`native/Info.plist`、`appcast/appcast.xml` 文档/占位信息。Release workflow 能打包 ZIP，但 appcast 目前仍是 placeholder，自定义更新器依赖 GitHub Release 约定命名。

**建议：**

- 增加 `scripts/bump-version`，统一写入 `AppInfo.swift`、`Info.plist`、变更日志和 tag 校验。
- CI 增加版本一致性检查：tag、AppInfo、Info.plist、ZIP asset 名称必须一致。
- 正式分发前补 Developer ID 签名、公证与 Gatekeeper 验证矩阵。

### 5. 真实价格完整度和解释性还可增强

当前一嗨和神州候选都用 `.partialPrice` 提醒，服务费、保险、异店还车费多为 0。这样能避免伪造价格，但用户可能难以判断“总成本”可信边界。

**建议：**

- 把价格来源拆成“平台明确返回”和“未识别/未包含”，在 UI 里逐项展示。
- 增加可复核字段：原始车型 ID、门店 ID、报价时间、平台返回字段名。
- 对 incomplete quote 降低排序置信度，或增加“需复核优先级”标记。

### 6. UI/UX 可强化错误恢复和进度解释

三栏工作台结构清晰，已有 loading、empty、平台状态和登录入口。但长耗时平台查询只显示统一“正在比较”，失败后多为状态文本。

**建议：**

- 加入分阶段进度：定位/解析城市/读取门店/读取库存/计算路线。
- 对平台失败提供明确恢复动作：重试单个平台、登录一嗨、刷新登录页、调整时间/半径。
- 为结果列表增加排序/筛选控件：按总成本、租车价、距离、平台、完整度切换。
- 补充 VoiceOver 标签和键盘操作路径，尤其是平台切换、结果选择、日期弹层。

## 低优先级增强点

### 7. 城市和地址归一化目前偏硬编码

`LocationServices.swift` 中维护了英文到中文的地点替换和城市别名列表，当前覆盖北京等高频场景，但全国城市扩展会不断增加手工维护。

**建议：**

将城市别名、平台城市映射、英文地名修正迁到数据文件或平台城市表，并增加 fixtures。

### 8. Electron 历史代码会稀释工程焦点

README 已说明 Electron 计划废弃，但仓库仍保留 `src/`、`electron/`、`package.json`、`node_modules`。这会让新贡献者难以判断主线，也引入安全审计成本。

**建议：**

如果不再需要 Electron 入口，删除 Node 依赖和历史 UI，仅保留迁移参考文档；如果仍需留档，移动到 `legacy/electron/` 并从默认 CI、安全审计中剥离。

## 扫描检测项清单

| 检测项 | 结果 |
|--------|------|
| 构建可用性 | Swift build 通过 |
| 单元测试 | Swift 有 1 个时间敏感失败；Node 测试通过 |
| 依赖漏洞 | Node/Electron 遗留链路有 critical audit issue |
| 硬编码敏感信息 | 未发现明显 API key/password/secret |
| 强制解包/强制转换 | 生产 Swift 未发现明显 `try!`、`as!`；WKNavigationDelegate 使用隐式解包属于框架签名惯例 |
| 资源释放 | Ehi session observer 有 deinit 移除；CLLocation continuation 有超时与清理 |
| UI 可访问性 | 部分控件有 label/help，但结果选择和平台切换仍可补强 |

## 建议执行顺序

1. 修复 `AppDateRulesTests` 的时间敏感失败，让 `swift test` 恢复全绿。
2. 删除或隔离 Electron 遗留链路；短期至少处理 `npm audit` critical 漏洞。
3. 拆分 `LiveRentalSearchService.swift`，把一嗨桥接脚本和平台解析做成可观测、可 fixture 测试的模块。
4. 自动化版本同步和 release 校验，为签名/公证做准备。
5. 增强 UI 中的平台阶段进度、单平台重试、结果筛选和价格可信度解释。

---

*报告生成时间：2026-06-12 14:04:59 CST*  
*扫描方式：本地静态阅读 + 构建/测试/audit 命令验证*
