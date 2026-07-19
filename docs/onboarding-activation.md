# Onboarding 激活体验设计

## 状态

已实现，待真机补充验证 Watch 翻页与 iPad 中继。

## 目标

新用户第一次打开 PagePilot 时，不再浏览纯介绍页，而是尽快完成一次核心体验：导入一本 Publication，在 Reader 中通过 Apple Watch 真实翻页。

Onboarding Activation（首次成功 Watch 翻页）是设计上的首要结果。选择 iPad Watch Control Target 后购买 Pro Access 是次要结果。本方案不新增匿名分析或第三方分析 SDK，因此不做跨用户漏斗统计。

## 非目标

- 不在 onboarding 中支持批量导入。
- 不在 onboarding 中承担完整的 Watch 排障。
- 不强迫用户完成任何步骤。
- 不为老用户自动重播新版 onboarding。
- 不提供“重新体验 onboarding / 设置引导”入口；现有“我 → Watch 设置”仍可用于日常设置和诊断。
- 不自动同步 iPhone 与 iPad 的书籍。

## 体验原则

- 首屏直接行动，不设置独立欢迎页。
- 每一步使用含义明确的次要操作，不使用贯穿全程的“稍后”。
- Watch 引导不阻塞阅读。
- iPad 在用户点击前明确标注为 Pro 功能。
- 权限只在用户表达相关意图后请求。
- 动效服务于状态变化，不增加装饰性复杂度。

## iPhone 主流程

### 1. 导入一本书

首屏同时表达产品承诺和导入动作，不再先展示欢迎轮播。

- 主标题强调结果，例如“戴着手表，也能轻松翻页”。
- 主操作为“导入一本书”。
- 次要操作为“使用样书”。
- 单次只接受一本 Publication；批量导入保留在 Bookshelf。
- 导入成功后不加入 Sample Publication。
- 取消或导入失败时停留在当前步骤，允许重试或使用样书。
- 只有用户没有成功导入自己的 Publication 时，才按需将 Sample Publication 加入 Bookshelf。

如果用户首次启动来自“文件”或分享菜单中的 EPUB/PDF，传入文件直接成为 onboarding 的导入输入。成功后继续下一步，不再打开一次文件选择器；失败则回到导入页。

### 2. 选择 Watch Control Target

页面展示两张未预选的目标卡片，要求用户主动选择：

- “这台 iPhone”：免费。
- “附近的 iPad”：点击前显示 `Pro` 标识。

次要操作为“暂时不用 Watch”。选择它后直接打开已导入的 Publication；若没有用户导入，则打开 Sample Publication。

### 3A. iPhone 目标

保存 iPhone 为 Watch Control Target，打开刚导入的 Publication 进入 Reader，然后展示首次翻页引导。

引导根据系统状态提供动作：

- 未配对 Apple Watch：说明当前无法测试，并允许跳过。
- 已配对但未安装 Watch App：引导用户在 Watch App 中安装 PagePilot，并允许跳过。
- 已安装但不可达：提示打开手表上的 PagePilot，并允许跳过。
- 可用：提示用户从 Watch 发出一次翻页操作。

Onboarding 不提供完整排障；详细诊断留在现有 Watch 设置页。

### 3B. iPad Pro 目标

点击 iPad 卡片后展示情境化 Paywall。购买组件和价格选项复用现有 Paywall，顶部内容改为 iPad Watch 控制场景，解释 Watch、iPhone 中继与 iPad Reader 的关系；其他 Pro 权益降为次要信息。

- 关闭 Paywall：返回目标选择页，不自动改选 iPhone。
- 购买成功：保存 iPad 为 Watch Control Target，展示双设备交接说明后结束 iPhone onboarding。
- 交接说明包括：在 iPad 打开 PagePilot、导入或接收书籍、打开 Reader，并按现有 Watch 设置页完成中继诊断。
- 此分支不打开 iPhone Reader，也不要求用户当场完成 Watch Setup Completion。

本地网络权限只在用户获得 Pro Access 并开始 iPad 双设备设置时请求。普通 iPhone Watch 翻页路径不触发本地网络权限。

## Reader 内首次 Watch 翻页

首次引导以底部非模态浮层出现，Reader 的触摸阅读保持可用。

- 前进、后退或表冠操作均可；只要 Watch 命令让 Reader 的 Reading Position 真实变化，即完成 Watch Setup Completion。
- 成功后提供轻触感反馈，短暂显示“连接成功，可以开始阅读”，随后自动淡出。
- 不增加额外完成按钮。
- 始终提供“暂时跳过”。
- 约 10 秒没有收到成功翻页时，浮层自动收起为轻量“试试 Watch 翻页”入口。
- 超时不是失败，不弹错误框。
- 完成后，所有 onboarding Watch 提示永久消失。

如果用户跳过 Watch 设置，完整 onboarding 不再自动出现。Reader 中保留可恢复的轻量入口；用户主动关闭该入口后不再自动打扰，仍可通过现有“我 → Watch 设置”操作。

## iPad 首次启动

iPad 不显示 iPhone 上的控制目标选择，因为 Apple Watch 与 iPhone 配对。

流程为：导入一本 Publication 或使用 Sample Publication → 打开 Reader → 可跳过地说明“若要用 Watch 控制此 iPad，请在已配对的 iPhone 上完成 Pro 中继设置”。iPad 首次启动不直接要求操作 Watch。

## 跳过与关闭

移除全局“稍后”按钮，使用与当前任务对应的次要操作：

- 导入页：“使用样书”。
- 控制目标页：“暂时不用 Watch”。
- Reader 引导：“暂时跳过”。

这些操作都继续把用户带向阅读。明确关闭整个 onboarding 时，流程结束，不再强制恢复。

## 中断恢复

系统文件选择、购买确认、切换后台或进程终止不应让用户从头开始。持久化最少必要状态：

- 已成功导入的 Book 标识；
- 已选择的 Watch Control Target；
- onboarding 是否由用户明确结束；
- Watch Setup Completion 是否已完成。

非主动中断后，从最近一个未完成步骤恢复。用户明确跳过或关闭后，不恢复完整 onboarding。

## 视觉与动效

沿用 PagePilot“静谧、流畅、领航、纯粹”的设计语言，只实现三处关键动效：

1. 导入成功后，书封从导入卡片自然过渡到 Reader。
2. 等待 Watch 操作时，手表或翻页方向使用低频呼吸提示。
3. 首次真实 Watch 翻页成功时，使用轻触感与短暂蓝绿光晕。

不使用粒子、3D 设备模型或长篇启动动画。开启“减少动态效果”时，用简短淡入淡出或静态状态替代位移、缩放和持续呼吸动画。

## 交付切片

### 1. 核心激活

单本导入、Sample Publication 兜底、iPhone 控制目标、打开 Reader、真实 Watch 翻页引导。

### 2. Pro 分支

iPad 目标、情境化 Paywall、购买后交接页、按需本地网络权限。

### 3. 体验收尾

断点恢复、外部文件接管、三处关键动效、减少动态效果、VoiceOver、Dynamic Type 和中英文文案。

## 验收标准

- 新安装的 iPhone 首屏可直接导入一本书或使用样书，没有独立欢迎轮播。
- 成功导入用户书籍后，Bookshelf 不自动出现 Sample Publication。
- 首次外部文件打开不会与 onboarding 产生重复弹层或重复选择。
- iPhone 与 iPad 控制目标均不预选；iPad 在点击前明确显示 Pro。
- 关闭 iPad Paywall 后返回目标选择；购买成功后进入交接说明并保存 iPad 目标。
- iPhone 目标会打开选定 Publication，并在 Reader 内显示非阻塞 Watch 引导。
- 只有真实 Watch 命令造成 Reading Position 变化时才记录 Watch Setup Completion。
- Watch 引导可跳过，10 秒无操作后自动收起，成功后永久消失。
- 流程被系统中断后能从最近未完成步骤恢复；主动结束后不重播。
- 老用户升级后不会被强制展示新版 onboarding，也没有重播入口。
- iPhone 主路径不会提前触发本地网络权限。
- 关键界面在浅色、深色、Dynamic Type、VoiceOver 和“减少动态效果”下可用。
- 界面流程可在 `platform=iOS Simulator,name=iPhone 17` 验证；Watch 翻页和 iPad 中继需使用真机补充验收。
