# Results

本次验证（当前工作区改动）：

- Native macOS XCTest harness 执行 48 项测试（31 项 Nearby、17 项 LAN recovery），0 失败。测试方法来自仓库，UIKit 的 vendor ID 用临时平台适配代替；不是完整 iOS app 的 XCTest run。
- 本机 Network.framework 集成 9 项通过。新安装无选择时发现两台中继及名称/书名，没有自动保存目标；选择第二台后，status/next/prev 三个请求只到第二台，第一台收到 0 个请求。使用当前中继源文件和 HTTP 测试夹具，不是真实 Reader。
- iOS SDK typecheck 覆盖当前中继、选择页及实际修改的连接/路由方法，通过。未改动的外部 app 依赖采用临时 stubs，因此不等于完整 app build。
- 五种本地化校验和 git diff --check 通过。
- MobileBuildMCP 完整 Debug app 构建通过。首次构建发现已提交项目漏掉 Nearby 源文件及测试引用；补齐 project.pbxproj 的 12 行引用后通过，保留原版本号、签名与 Readium revision 配置。
- 独立 `PagePilot iPhone 17 Relay`（28A8B0FD-846E-469B-A6FD-F7AA6DE698C0，iOS 26.5）上运行当前 app 的 XCTest：31 项 Nearby + 17 项 LAN recovery，48 通过、0 失败、0 跳过。
- 独立模拟器成功启动，runtime UI snapshot 确认进入首页。启动参数使用现有 `-AutoDismissOnboarding` 和临时 UserDefaults argument-domain Pro 状态；这不是购买验证。组合启动及单独安装调用曾超时，后续单独 launch 成功。
- 用户告知默认 iPhone 17 正被他人使用后，所有后续运行与测试均改到上述独立模拟器。此前一次默认实例的启动不作为 UI 验证证据。

证据日志：/tmp/pagepilot-manual-p2p-policy-tests.log、/tmp/pagepilot-manual-p2p-transport.log、/tmp/pagepilot-manual-p2p-ios-service-typecheck.log。

iOS XCTest 日志：/Users/water/Library/Developer/MobileBuildMCP/workspaces/PagePilot-beebb2099dab/logs/test_sim_2026-10-08T02-51-22-811Z_pid52491_98e5e5ba.log。

结果包：/Users/water/Library/Developer/MobileBuildMCP/workspaces/PagePilot-beebb2099dab/result-bundles/test_sim_2026-10-08T02-51-22-812Z_pid52491_946aa179.xcresult。

未完成：iPhone/iPad 选择页点击流程（包括窄窗口）实测和实体 AWDL 无共同 Wi-Fi 验证。用户已明确授权 Xcode MCP，但打开项目、按路径列 scheme 及列 workspace 仍返回 `MCP tool call requires approval, but approval policy is never`。MobileBuildMCP 当前未提供 tap/swipe 等交互工具；原生 Simulator 的 CUA 绑定也不可用。不能将首页启动或逻辑测试记作选择页操作通过，不应把旧 main 的 371 项 CI 通过误记为本次改动通过。

## 选择页模拟器实测（2026-10-08，第二轮）

环境：`PagePilot iPhone 17 Relay` + `PagePilot iPad mini Relay`（均 iOS 26.5），当前工作区 Debug 构建，启动参数 `-AutoDismissOnboarding -entitlements_isPro YES`。用打包在 MobileBuildMCP 里的 AXe（`touch --down --up`）操作；`axe tap` 在该 runtime 上不生效。

- 发现：列表同时显示 iPad 模拟器（设备名）和本机遗留的 manual-transport 夹具（“Study iPad · Dune”），搜索中按钮禁用、显示进度。证据 `evidence/sel2.png`。
- 选择成功：点击 iPad mini 后约 1 秒自动返回，设置行显示所选设备名；iPad 诊断页显示“已收到 iPhone 的测试访问”。再次进入时所选设备带勾。证据 `evidence/reenter.png`。
- 失败与重试：先结束 iPad app 再点击，所有行禁用且显示 spinner，约 5 秒后显示连接失败文案，原选择保留。证据 `evidence/fail.png`。重启 iPad app 后不重新搜索直接点击，连接成功并返回。
- iPad 布局：选择页只在 iPhone 出现（MeView 按 idiom 分支）；iPad 显示的是诊断页，其新文案渲染正常。
- 测试环境假象：模拟器里 StoreKit 刷新出“无 Pro”后会调用 disableIPadRelay，参数域的 Pro 值不会让中继重新启动，需进入 iPad 诊断页才会重启。真实 Pro 用户不会遇到。

仍未完成：实体设备在不同 Wi-Fi 或无路由下的 AWDL 验证。
- 第二轮追加：Nearby/LAN recovery/LAN pairing 共 57 项 iOS XCTest 通过（含 2 项迁移测试）。模拟器中 iPhone 直接翻页：iPad 未打开书时显示失败文案；打开测试 EPUB 后，下一页 ×3、上一页 ×1 分别得到 1→3→5→7→5 / 10（横屏双页），每次点击只翻一次。
- 已在实体 iPhone 16 Pro（iOS 27.0.1）和 iPad 6th gen（iOS 17.7.11）上安装 Debug 构建并带 Pro 参数启动，待用户操作无共同 Wi-Fi 的实测。

## 第三轮：常连直连架构

- 单元测试 15 项和集成测试 6 项。集成测试在同一进程里起 host 和 client，走真实 Network.framework，覆盖连接复用（只建 1 条连接）、只发给所选 iPad、找不到时报 notFound、无 Pro 时拒绝、iPad 重启后自动重连。连续 5 轮共 30 次全部通过。
- 完整 iOS 测试 348 项，0 失败。其中一项检查源码文本的 LiveActivity 测试，已按 handleCommand(origin:) 的新写法更新。
- 模拟器端到端（AXe 驱动）连续 3 轮通过：列表显示设备名和书名，选择后显示“已连接”，可连续翻页，iPad 应用重启后自动恢复。
- 真机（iPhone 16 Pro iOS 27.0.1 + iPad 第 6 代 iOS 17.7.11，iPhone 用数据线连 Mac）：
  - 停止搜索的旧实现：iPhone 没连 Wi-Fi 网络时，43 次中 16 次失败。日志显示连接走 awdl0，搜索停止后连接静默失效。
  - 常驻搜索之后：没连 Wi-Fi 网络时 73/73 成功，通常 10–50ms；全程含 Wi-Fi 连上/断开切换共 112 次，失败 1 次，失败出在断网那一刻的旧连接上。
  - 加 viability 处理后：86/86 成功，覆盖连上 Wi-Fi（切到 en0）和断开 Wi-Fi（2.2s 内回到 awdl0，补发的那次被 iPad 去重，没有重复翻页）。
  - `scripts/peer-link-soak.sh <iPhone> 10`：真机全程无人操作，10/10 通过。
- 已确认的限制：两台设备的 Wi-Fi 开关都必须打开，awdl 依赖 Wi-Fi 硬件。iPad 应用需要在前台。iPhone 在后台时，链路会在下一次手表指令到来时重建。“手表唤醒后台 iPhone”这条路径已在模拟器上验证（见下），真机加真手表还没验证过。
- 手表链路（模拟器）：手表模拟器 Series 11 与 iPhone 17 Relay 配对，iPad mini Relay 打开书。用 `scripts/watch-relay-sim-e2e.sh` 测三种情况：iPhone 应用在前台、在后台、被关掉后由手表冷启动。每种情况都是手表点下一页、再点上一页，iPad 1/10 → 3/10 → 1/10，连续 2 轮全部通过，手表上正确显示书名和进度。三台模拟器共用 Mac 的网络，所以这项不验证 awdl，awdl 由 peer-link-soak 在真机上覆盖。
