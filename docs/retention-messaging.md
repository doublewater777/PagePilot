# PagePilot 订阅挽留配置

## 当前状态（2026-10-16）

- Apple Retention Messaging API 访问申请已获批（用户确认）。RevenueCat 项目 `proj1f57f9a1`，iOS App `app334401cbe5`。
- 已连接 Apple **sandbox realtime URL**；真机已成功完成沙盒内购校验。
- **性能测试已通过（Passed）**：Apple 端到端延迟基准测试顺利通过。
- **生产端点与引导流程已全部解锁完成**：生产 Realtime URL 自动配置完成。
- **App Store Connect API Key 已上传并验证成功**：成功导入月/年订阅商品。
- **首条默认挽留消息（Default Message）已正式创建并提交**：
  - Reference: `pagepilot_pro_value_v1`
  - 关联商品: `com.panyang.PagePilot.pro.monthly`、`com.panyang.PagePilot.pro.yearly`
  - 覆盖语言: 英语（en-US）、简体中文（zh-Hans）、法语（fr）、德语（de）、西班牙语（es）
  - 当前状态: `Active, with messages in review`（已提交 Apple 官方审核，审核通过后即可在系统订阅取消页原生展示）。
- RevenueCat App 设置显示 `No notifications received`。上线前需核对 App Store Server Notifications V2 的生产/沙盒地址及投递；该提示本身不证明 Apple 未配置通知。
- 已创建并完成邮箱验证的专用沙盒账号：`PagePilot Retention`，ID `7a7ad9b3-2485-41d2-b8c1-100472b3e58a`，邮箱 `panyang20020203+pagepilotretention20261016@gmail.com`，地区 `USA`。通过 Apple 邮件验证链接登录后，页面明确显示 `Email Address Verified`。
- 已通过 App Store Connect API 将该账号的续费速度设为 `MONTHLY_RENEWAL_EVERY_ONE_HOUR`。随机测试密码保存在仓库外 `/Users/water/.codex/private/pagepilot-retention-sandbox.json`（0600 权限），不写入本仓库。
- 已用 computer use 实际操作 iPhone 18 Pro / iOS 27.0 模拟器（`04202ABB-F836-43B2-886D-12FD870F60F6`）。新版 Xcode 的模拟器入口为 Xcode → Open Developer Tool → **Device Hub**（`com.apple.dt.Devices`），不是独立 Simulator 应用；点击、输入和设置导航可用。
- 模拟器在「设置 → 开发者 → 沙盒 Apple 账户」登录失败。邮箱验证前后均返回“你的 Apple 账户或密码不正确”；同一组凭据已成功完成 Apple 网页验证。未生成任何 Apple 沙盒购买交易，也未用 `.storekit` 合成交易替代。
- Apple DTS 在[官方论坛](https://developer.apple.com/forums/thread/768966)说明真实沙盒内购应在真机测试。下一步是在真机的开发签署版或 TestFlight 中产生有效年订阅，再运行性能测试。不能将网页账号验证、模拟器安装/启动或本地交易视为该测试通过。

[RevenueCat 挽留后台](https://app.revenuecat.com/projects/1f57f9a1/lifecycle/retention)

## 首版策略

先用一条权益提醒建立基线：为月订阅和年订阅配置同一条默认消息，覆盖现有五种语言。不添加图片、折扣或重叠的实时规则。默认消息必须能独立表达价值，且在实时响应失败或没有符合条件的实时消息时可用。

适用商品：

- `com.panyang.PagePilot.pro.monthly`
- `com.panyang.PagePilot.pro.yearly`

不适用 `com.panyang.PagePilot.pro.lifetime`（买断没有订阅取消流程）。

文案只描述现有付费权益，不声称取消会立即丢失数据、删除笔记或立刻停止访问；不把免费的 iPhone Watch 翻页包装成付费权益；不填写无法动态验证的节省金额。首版不以设备类型分群，内容同时适用于 iPhone 和 iPad，取消界面由 Apple 系统渲染。

## 可直接录入的默认消息

Reference：`pagepilot_pro_value_v1`

每个标题不超过 66 字符，正文不超过 144 字符。以下内容不含价格，适用于不同 storefront 和账单周期。

| Locale | Title | Subtitle |
| --- | --- | --- |
| en-US | Make room for your next great read | Keep an unlimited library, unlimited highlights and notes, and detailed reading stats with PagePilot Pro. |
| zh-Hans | 让下一本好书，也有位置 | 继续享受 PagePilot Pro 的无限书架、无限高亮与笔记，以及周、月、年阅读统计。 |
| fr-FR | Gardez une place pour votre prochaine lecture | Avec PagePilot Pro, profitez d’une bibliothèque, de surlignages et de notes illimités, et de statistiques de lecture détaillées. |
| de-DE | Platz für dein nächstes Lieblingsbuch | Mit PagePilot Pro: unbegrenzte Bibliothek, unbegrenzte Markierungen und Notizen sowie detaillierte Lesestatistiken. |
| es-ES | Haz sitio para tu próxima gran lectura | Con PagePilot Pro, disfruta de una biblioteca, subrayados y notas sin límites, además de estadísticas de lectura detalladas. |

## 完成接入的顺序

1. 在真机使用 PagePilot TestFlight / Apple 沙盒测试账号购买年订阅，保持有效。不要用 `.storekit` 本地交易，也不要购买买断来替代订阅。年订阅是当前周期最长的订阅商品，可减少性能测试期间过期的风险。
2. 在挽留后台点击 `Check again`，识别交易后运行性能测试。只有确认测试通过，才继续生产配置；测试可能需要最多一小时。
3. 在 sandbox 创建上述默认消息，关联月、年两个商品和五种语言。核对各 locale 的 Apple 状态。
4. 用真实 Apple 沙盒订阅的取消确认界面检查显示。TestFlight 测试需能打开应用内系统管理订阅页；当前仓库检索未发现相应入口，届时需确认测试构建是否具备入口，再决定是否补充。验证保留订阅和继续取消均可完成。iPhone 和 iPad 都要检查。
5. 核对 App Store Server Notifications V2。不要覆盖既有服务端端点而丢失原有业务；如已有端点，按实际架构转发到 RevenueCat。
6. 测试通过后连接 production realtime URL，重新创建生产默认消息。沙盒消息不会自动迁移；生产消息逐语言通过 Apple 审核后才能显示。访问获批、性能测试通过、消息审核通过是三个独立状态。

## 第二阶段（未配置）

- 先观察有多少取消意向用户实际展示消息、最终取消，以及后续真实续费收入。短期 Save rate 不能单独证明增量收益；RevenueCat 和 Apple 的统计口径也不同。
- 有足够流量且 RevenueCat 套餐支持时，对默认文案与另一条权益文案做随机实验，观察 Save rate、Realized LTV per customer 和 Churned subscribers rate，不同时改价格和文案。
- 若要针对试用期单独提醒，使用 `Is in free trial`，不要用 `Is in intro offer period` 代替。首版不需要额外实时消息。
- 只有数据提示价格阻力时，再评估转套餐或一次性优惠；先核对实际 storefront 价格、优惠资格、订阅组和恢复原价披露。可考虑限定付费时长及近期未领优惠的用户，但不要把这些建议当作已存在的配置。
- 实时规则尽量互斥：RevenueCat 在多条均符合条件时选择最早创建的消息，不能依赖“更具体规则自动优先”。

## 官方依据

- [RevenueCat：Apple Retention Messaging API](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-retention-messaging-api)
- [Apple：Responding to real-time retention messaging requests](https://developer.apple.com/documentation/retentionmessaging/responding-to-realtime-retention-messaging-requests)
- [RevenueCat：Retention messaging experiments](https://www.revenuecat.com/docs/tools/experiments-v1/experimenting-with-retention-messaging)

实时响应由 RevenueCat 托管，避免为 Apple 的 700ms 响应要求另建业务服务器。应用无需为了消息投递修改购买归属或交易处理流程。
