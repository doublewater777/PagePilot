# PagePilot Design System (设计系统)

这是基于 PagePilot 的四个核心设计关键词（**静谧、流畅、领航、纯粹**）所建立的视觉与交互规范。项目中的所有 UI 组件、色彩和字体均需遵循此规范，以保持品牌的一致性与高感知品质。

---

## 1. 色彩规范 (Color Palette)

色彩是传递情绪的第一媒介。PagePilot 采用低噪点、具备“呼吸感”的色彩搭配，辅助以科技感的微渐变色。

### 1.1 品牌色与渐变
*   **PagePilot Blue (领航蓝)**: `#386EF2` (RGB: 56, 110, 242)
    *   *语义*：代表专业、冷静与领航控制（Watch 翻页）。
*   **PagePilot Teal (流畅绿)**: `#299E94` (RGB: 41, 158, 148)
    *   *语义*：代表心流、成长（阅读时长积累）。
*   **领航渐变色 (Accent Gradient)**: 从 `PagePilot Blue` 到 `PagePilot Teal` 呈 135 度渐变。
    *   *应用*：Pro Paywall 按钮、已解锁状态、主要统计进度条。

### 1.2 系统背景与卡片色
为了达到“静谧”与“纯粹”的效果，背景不采用高亮刺眼的纯白或死黑，而是使用温和的中间色。

| 模式 | 系统背景 (System Background) | 卡片/容器背景 (Card Background) | 主要文字 (Primary Text) | 次要文字 (Secondary Text) |
| :--- | :--- | :--- | :--- | :--- |
| **浅色模式 (Light)** | `#F6F8FC` (淡蓝灰) | `#FFFFFF` (纯白) | `#1C1E21` | `#606873` |
| **深色模式 (Dark)** | `#0F1013` (暗夜黑) | `#1A1C20` (深灰卡片) | `#F5F6F8` | `#8A95A5` |
| **纸张模式 (Sepia)** | `#F4ECD8` (沙暖色) | `#EADFCA` (暖调卡片) | `#433422` | `#7C6955` |

---

## 2. 字体与排版规范 (Typography)

排版系统需确保阅读的舒适性，以及统计界面的精细感。

### 2.1 字体族定义
*   **界面与数据字体 (UI & Stats)**: SF Pro Display / SF Pro Text（系统默认），英文字符推荐 Outfit（若支持自定义导入）。
*   **正文阅读字体 (Reader Body)**: System Serif（如 Georgia, 宋体 / 仿宋），强调沉浸式阅读，突出书香的典雅。

### 2.2 字号与字重层级

| 层级 | 字号 (Size) | 字重 (Weight) | 应用场景 |
| :--- | :--- | :--- | :--- |
| **Display Title** | `30pt` | Bold / Heavy | 首页/统计大标题 (如“阅读统计”) |
| **Stat Number** | `40pt` | Bold | 核心数据展示 (如阅读时长数字，使用等宽数字 `.monospacedDigit()`) |
| **Section Header** | `18pt` | Bold | 卡片/模块标题 (如“成就勋章”、“图书排行”) |
| **Card Body** | `13pt / 14pt` | Medium / Regular | 卡片主要文本、描述、列表标题 |
| **Caption** | `10pt / 11pt` | Regular | 辅助描述、副标题、进度数值 |

---

## 3. 形状与层级规范 (Shapes & Elevation)

设计应当呈现轻量“悬浮层级（Elevation）”，利用毛玻璃与圆角打造现代感。

*   **大容器与卡片圆角 (Major Card)**: `16pt` 连续圆角 (`.continuous`)。
*   **按钮与操作圆角 (Button)**: `12pt` / `14pt` 连续圆角。
*   **功能图标背景 (Icon Container)**: `14pt` 连续圆角 或 `Circle`（圆形）。
*   **卡片阴影 (Shadows)**:
    *   浅色模式：`Color.black.opacity(0.04)`, `radius: 12`, `y: 6`。
    *   深色模式：不使用阴影，使用淡色细描边（`Color.white.opacity(0.06)`, `lineWidth: 1`）来划分边界。

---

## 4. 动效与微交互 (Motion & Haptics)

流畅是体验的灵魂，动效应当遵循物理世界的阻尼和惯性。

*   **UI 状态切换 (UI Transitions)**:
    *   使用弹性动画：`withAnimation(.spring(response: 0.35, dampingFraction: 0.8))`。
    *   *禁用* 生硬的线性（Linear）或突然出现消失的渐变。
*   **Watch 控制反馈 (Haptic Feedback)**:
    *   Watch 端翻页指令发送成功：低功耗“轻度”触觉反馈。
    *   iPhone/iPad 接收并成功翻页：`UIImpactFeedbackGenerator(style: .light)`。
*   **数据打卡达成 (Success)**:
    *   每日目标完成或解锁勋章：`UIImpactFeedbackGenerator(style: .medium)` 配合爆炸性的微粒子扩散动效。
