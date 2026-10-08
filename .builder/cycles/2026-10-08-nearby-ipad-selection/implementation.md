# Implementation

新增限定时长的 P2P 设备列表扫描；Bonjour TXT 包含设备名与书名；iPhone Watch 设置提供选择页；连接时直接发送 nearby status；仅成功后保存显式选择。

保留稳定身份握手、Pro 验证及原有 LAN 回退，后者必须匹配所选 iPad。旧 LAN 学习记录不当作显式选择。支持 iPhone 和受限宽度的 iPad 容器。未增加自动选择，未移除 LAN HTTP 后端。

完整构建发现 Xcode 项目缺少 main 已有的 Nearby 源文件和测试引用，补齐 12 行文件及 target membership 引用；保留原项目的版本、签名和依赖配置。

追加（2026-10-08 第二轮）：
- 升级迁移：用户选择迁移旧关联。首次读取选择时，若只有旧的 `pagepilot_nearby_associated_target`（合法 UUID），一次性转为名为 “iPad” 的已选设备并删除旧键；之后显式选择会覆盖它。新增 2 项测试。
- iPhone 直接翻页（用户提出）：已选 iPad 时，Watch 设置的 iPad 区域显示“上一页 / 下一页”。走与 Watch 相同的中继路由（LAN 优先、P2P 回退，只到所选 iPad），请求 source 为 `iphone`。新增 3 条五语言文案。

## 架构调整：单一常连直连（2026-10-08，第三轮）

用户确认方案后，去掉跨设备 LAN 链路，统一为 Network.framework 点对点（`includePeerToPeer`）一条通道。有共同 Wi-Fi 时自动走路由器，没有时走 awdl。

- `PagePilotPeerLink.swift`
  - `PagePilotPeerHost`（iPad）：一个 NWListener 广播 `_pagepilot-peer._tcp`，TXT 带设备名和书名。保持每个 iPhone 连接常开，在进程内直接处理 status/command，不再转发给本机 HTTP 服务。监听失败时自动重启。
  - `PagePilotPeerClient`（iPhone）：对所选 iPad 维持一条常连 TCP，开启 TCP keepalive。按请求 id 配对应答。掉线和不可达各重试一次，超时不重试。连接不可用（viability）时立刻重建。
  - 常驻搜索：iOS 只在 App 保持搜索时才维持 awdl。实测停止搜索后，awdl 连接会在 1–2 次请求后静默失效。因此 iPhone 只要选定了 iPad，前台期间就一直保持搜索，进入后台时停止。
- `PagePilotPeerLinkSupport.swift`：设备身份、选择记忆（含旧 LAN 关联迁移）、多帧解码、请求/应答格式、主机校验（只接受发给本机身份且有 Pro 的请求）、错误到 Watch 错误码的映射。
- `WatchPageTurnService`：从 1817 行减到约 690 行。删除 PagePilotLANBrowser、GCDWebServer 和多路由策略。Watch 与 iPhone 直接翻页共用 `relayToSelectedIPad`，Watch 收到的应答格式和错误码不变。手表唤醒 iPhone 时用后台任务包住中继请求。
- iPad 诊断页改为显示实时状态：当前是否有 iPhone 连着。iPhone 设置显示“已连接/未连接”。
- 文案：5 种语言更新引导步骤、诊断说明和菜单路径（与界面上的“Apple Watch”入口一致）。西语里被直译成“reloj de manzana”的 Apple Watch 改回品牌名。
- 调试工具（仅 DEBUG）：
  - `-PagePilotDebugPro`：StoreKit 刷新不会撤销 Pro，保证模拟器和真机自测稳定。
  - `-PagePilotPeerSoak [-PagePilotPeerSoakCount N]`：iPhone 自动连续翻页，日志写入 Documents/peer-soak.log。
  - `scripts/peer-link-soak.sh`：一键启动自测、拷回日志并汇总。
