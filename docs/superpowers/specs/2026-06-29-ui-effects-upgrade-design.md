# UI Effects Upgrade Design

## Goal

将租车比价助手整体升级为“专业高端调度台 + 适度科技感”的 macOS 原生工作台。升级应覆盖主三栏工作台、监控中心、创建监控弹窗和平台登录弹窗，让应用在视觉层次、状态反馈、动效质感和跨页面一致性上明显提升，同时保持工具型应用的扫描效率。

本次升级只改变 SwiftUI 视图层和共享设计组件，不改变平台 API、搜索排序、价格计算、监控调度、持久化格式或发布流程。

## Product Positioning

应用的核心任务仍然是帮助用户基于真实官方接口比较租车总成本。视觉设计应支持“可信、清晰、可执行”的判断过程，而不是把界面变成营销页或重装饰页面。

设计气质：

- 专业高端调度台作为基础：信息密度高、层级明确、状态可靠。
- 适度科技感作为状态层：查询、平台状态、推荐选中和监控事件有更鲜明的反馈。
- 日常使用保持安静：没有持续抢眼动画，没有大面积闪烁，没有复杂 3D 或粒子效果。

## Scope

### Included

- 主工作台外壳和顶部任务状态栏。
- 左侧查询控制台、地址和日期控件、平台状态、比较按钮。
- 中间候选方案区、加载态、空态、筛选条、结果卡片。
- 右侧推荐明细区、费用拆分、路线卡、风险提示和操作按钮。
- 监控中心的列表、健康摘要、详情、趋势图、事件和快照区域。
- 创建监控弹窗、一嗨登录弹窗、神州登录弹窗。
- 共享设计 token、表面组件、状态组件、轻量动效组件。

### Excluded

- 不新增租车平台。
- 不修改真实 API 查询、平台登录、Cookie 保存、价格监控调度逻辑。
- 不修改领域模型、排序规则、价格计算或监控存储格式。
- 不做发布版本号、签名、公证、Release 流程调整。
- 不将应用改成网页、落地页或营销型首页。

## Visual Language

### Palette

使用兼容浅色和深色模式的语义色，而不是在组件内散落 raw color。

- `CommandBlue`：主操作、API 可信状态、选中边线。
- `SignalTeal`：平台连通、路线辅助、实时数据感。
- `RouteGreen`：推荐路线、成功、降价事件。
- `AmberAlert`：登录需要、验证码、待处理和复核建议。
- `CriticalRed`：失败、阻断类问题。
- `ConsoleBase`：应用背景，浅色为冷白灰，深色为石墨黑蓝。
- `PanelSurface`：主面板和弹窗表面。
- `ElevatedSurface`：结果卡、收据卡、监控详情卡。

浅色模式应保持干净专业；深色模式允许更强的座舱感，但避免整页读成单一蓝黑主题。

### Surfaces

共享组件应从当前 `SurfaceBox` 和 `WorkbenchPanel` 扩展，而不是每个页面重写样式。

- 主面板使用轻微高光边、柔和阴影和低对比分隔线。
- 结果卡与弹窗使用更明显的 elevated surface，但圆角仍控制在 8px 左右，保持工具感。
- 选中态以边线、高光和轻微抬升表达，避免大面积实色填充。
- 风险提示使用淡琥珀背景和明确图标，不用过强警报视觉。

### Typography

保留 SwiftUI 系统字体和 SF Symbols，增强数字和价格信息的层级。

- 价格、百分比、时间等数据继续使用 monospaced digit。
- 标题和卡片主信息使用 semibold/bold，但不要在紧凑区域使用 hero-scale type。
- 长文本优先换行，避免压缩到不可读。

### Signature Element

全应用的记忆点是一条细的“状态光轨”。

- 主面板标题区和顶部任务状态栏可以使用静态光轨。
- 查询中、巡查中或登录检测中时，光轨进入短周期流动态。
- 空闲时光轨保持静止，作为层级和状态分隔，不抢注意力。
- 减少动态效果开启时，光轨只显示静态状态色。

## Architecture

### Shared Design System

`Sources/CarRentalOptimizer/WorkbenchStyle.swift` 继续作为设计系统入口，扩展以下能力：

- 语义颜色 token 和 adaptive color helper。
- 面板、卡片、弹窗、状态条和光轨组件。
- 统一的 shadow、stroke、radius、spacing 和 animation token。
- 状态 chip、metric pill、empty/loading block 的升级版本。
- `accessibilityReduceMotion` 友好的动效封装。

这些组件应保持轻量，不引入第三方依赖。

### View Ownership

视图层分工保持不变：

- `MainView.swift` 管整体 shell、顶部任务状态栏、背景。
- `SearchPanelView.swift` 管查询控制台和平台状态。
- `ResultPanelView.swift` 管候选列表、筛选和搜索状态。
- `DetailPanelView.swift` 管选中方案的决策收据。
- `MonitorCenterView.swift` 管监控中心。
- `CreateMonitorSheet.swift`、`EhiLoginSheet.swift`、`PlatformLoginSheet.swift` 管弹窗体验。

如果共享组件明显增长，应优先在 `WorkbenchStyle.swift` 内部拆成小型私有/通用 view，而不是把页面文件变成大块重复样式。

## Main Workbench Design

### Top Task Bar

顶部从普通 header 升级为任务状态栏：

- 左侧保留应用图标、名称和版本。
- 中间展示上次搜索、当前推荐、监控状态。
- 右侧保留监控中心入口、真实 API 状态、后台巡查状态。
- 查询中时顶部状态光轨流动，空闲时静止。
- 指标块使用统一 elevated style，保证宽屏下可扫读，小窗口下不溢出。

### Query Console

左栏变成任务配置面板：

- 行程、车辆与范围、取还规则、平台继续分组。
- 地址联想下拉使用 elevated surface 和更清晰的 hover/selection feedback。
- 日期卡保留当前双端点设计，强化 active border 和范围关系。
- 平台 toggle 显示平台状态微光边框：成功、待登录、验证码、失败、等待。
- “开始比较”按钮在查询中显示进度态，失败后仍提供清晰 retry 入口。

### Candidate Results

候选区是本次升级重点：

- 搜索加载态使用分阶段卡片，直接绑定现有 `SearchProgressPhase`。
- 结果卡升级为报价信号卡：排名、门店、平台、车型匹配、总成本、路线成本、费用完整度一屏可扫。
- 选中结果使用高光边、轻微抬升和右侧详情同步强调。
- 筛选条保持紧凑，但视觉上与结果卡区分。
- 空态继续强调“不显示推测价格”，并把平台恢复建议做成明确行动区。

### Decision Receipt

右栏升级为决策收据：

- 总成本作为视觉锚点，显示租车小计和到店成本。
- 门店事实、平台价格对比、费用拆分、路线方案、风险提醒保持分区。
- 推荐路线卡使用绿色/蓝色边线和 badge 区分。
- “监控这个方案”和“打开原始平台”保持底部行动区一致性。

## Monitor Center Design

监控中心统一成调度台子系统：

- 左侧列表保留 sidebar 效率，但列表行强化状态、下次巡查和待处理层级。
- 健康摘要使用统一 metric pill，突出总数、需处理、降价、今日巡查。
- 右侧详情使用 elevated cards：摘要、趋势图、事件、历史快照。
- 降价事件用绿色下行符号和轻微闪入；异常事件用琥珀提示。
- 趋势图保留 Swift Charts，不改变数据口径，只调整容器、图例和周边层级。

## Sheets And Login Views

创建监控和登录弹窗应与主界面共享同一套 surface、button 和 status 语言：

- 标题区明确当前任务。
- 输入/说明区保持紧凑，不出现营销式说明文。
- 主操作按钮使用 `CommandBlue`，次要操作使用 bordered style。
- 登录状态、失败和恢复建议使用统一 status row。
- 弹窗尺寸应稳定，不因状态文案变化产生明显跳动。

## Motion And Effects

所有动效以状态变化为触发：

- 查询开始：顶部光轨流动，比较按钮进入 loading state。
- 搜索阶段变化：加载卡片文案和图标平滑切换。
- 结果出现：候选卡片短距离淡入上移，列表项错峰 30-50ms。
- 选中方案：结果卡高光，详情总价轻微 scale/opacity 强调。
- 平台状态变化：chip 边线和图标状态变化，必要时短促高亮。
- 监控事件：降价或异常事件闪入，但不持续循环。

动效约束：

- 优先使用 opacity、scale、offset，避免布局抖动。
- 常规 micro-interaction 控制在 150-300ms。
- 不让动画阻塞点击、滚动或输入。
- 接入 `Environment(\.accessibilityReduceMotion)`；减少动态时保留颜色和状态变化，去掉位移、脉冲和错峰。

## Accessibility

- 图标按钮必须保留 label、help 或 accessibility label。
- 交互目标保持 macOS 桌面应用可点击尺寸，紧凑但不难点。
- 状态不能只靠颜色传达，必须有图标或文字。
- 深浅模式下正文对比度应保持可读。
- 键盘焦点和系统控件行为不应被自定义样式破坏。
- 文本在最小窗口尺寸下不能互相遮挡；价格和长门店名允许 line limit 和 scale factor，但核心信息必须可读。

## Error Handling And Empty States

错误和空态文案继续围绕“真实报价优先”：

- 无结果时不暗示系统会生成推测价格。
- 平台失败、登录、验证码和不可用状态继续来自现有 typed status。
- 恢复建议要具体：重试、登录、调整条件、放宽筛选。
- 保留历史结果时必须明确标记为上次成功结果。

## Testing And Verification

### Automated Checks

- `swift build`：确认 SwiftUI 视图编译。
- `swift test`：确认领域逻辑、ViewModel 和现有回归测试未受影响。

### Visual Checks

如果本机 app bundle 可构建：

- 运行 `scripts/build-app.sh`。
- 使用 `scripts/verify-launch.sh build/租车比价助手.app` 做启动验证。
- 视觉检查主工作台、监控中心和主要弹窗。

重点检查：

- 浅色/深色模式均可读。
- 最小窗口尺寸下无文本重叠。
- 查询中、无结果、有结果、选中结果、监控详情、登录弹窗状态都能正常显示。
- 减少动态效果开启时不出现持续运动。

## Rollout Notes

本次变化是 UI-only，可以作为一次单独视觉升级发布。若实现过程中发现页面文件过大，应优先抽共享视图，但只抽与本次 UI 升级直接相关的组件，不做无关重构。

## Non-Goals

- 不设计移动端界面。
- 不引入第三方 UI 框架。
- 不新增图像资产或外部网络资源。
- 不改变应用信息架构之外的业务流程。
- 不做版本发布、tag、上传 Release 或安装包分发。
