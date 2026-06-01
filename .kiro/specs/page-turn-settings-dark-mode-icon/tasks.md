# Implementation Plan

- [ ] 1. 编写 Bug Condition 探索性测试（修复前运行）
  - **Property 1: Bug Condition** - 深色模式下 watchSection 图标颜色不可见
  - **CRITICAL**: 此测试 MUST 在未修复代码上运行并 FAIL——失败即证明 Bug 存在
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: 此测试编码了期望行为——修复后通过即验证 Bug 已修复
  - **GOAL**: 暴露反例，证明 `iconColor: .black` 在深色模式下不可见
  - **Scoped PBT Approach**: 将属性测试范围限定在具体失败场景：`colorScheme == .dark` 且 `iconColor == .black`
  - 在 `.dark` colorScheme 环境下渲染 `watchSection`，断言传入 `SettingsRow` 的 `iconColor` 不为 `.black`（来自设计文档 Bug Condition：`isBugCondition(colorScheme, iconColor)` 当 `colorScheme == .dark AND iconColor == .black` 时返回 true）
  - 断言 `iconColor` 在深色背景上具有足够对比度（对比度 >= 3.0）
  - 在未修复代码上运行
  - **EXPECTED OUTCOME**: 测试 FAILS（这是正确的——证明 Bug 存在）
  - 记录反例：`watchSection` 在深色模式下传入 `iconColor: .black`，图标不可见
  - 任务完成标准：测试已编写、已运行、失败已记录
  - _Requirements: 1.1, 1.2_

- [ ] 2. 编写保留性属性测试（修复前运行）
  - **Property 2: Preservation** - 浅色模式及其他设置行行为不变
  - **IMPORTANT**: 遵循观察优先方法论
  - 观察：在未修复代码的 `.light` colorScheme 下，`watchSection` 的 `iconColor` 为 `.black`，图标在白色背景上清晰可见
  - 观察：`appearanceSection` 中语言行 `iconColor` 为 `.blue`，主题行为 `.purple`
  - 观察：`ttsSection` 中 TTS 行 `iconColor` 为 `.blue`
  - 观察：`feedbackSection` 中各行 `iconColor` 分别为 `.red`、`.yellow`、`.green`
  - 编写属性测试：对所有 `colorScheme` 值，其他设置行（语言、主题、TTS、反馈）的 `iconColor` 参数值与修复前完全相同（来自设计文档 Preservation Requirements）
  - 编写属性测试：在 `.light` colorScheme 下，`watchSection` 的图标颜色视觉效果与修复前等效（接近黑色，对比度满足要求）
  - 在未修复代码上运行
  - **EXPECTED OUTCOME**: 测试 PASSES（确认基线行为，供修复后对比）
  - 任务完成标准：测试已编写、已运行、在未修复代码上通过
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 3. 修复深色模式下翻页设置图标不可见问题

  - [ ] 3.1 将 `watchSection` 中的硬编码颜色替换为语义颜色
    - 打开 `Sources/Settings/SettingsView.swift`
    - 定位 `watchSection` computed property 中的 `SettingsRow` 调用
    - 将 `iconColor: .black` 替换为 `iconColor: .primary`
    - `.primary` 在浅色模式下解析为接近黑色，在深色模式下解析为接近白色，自动适配两种模式
    - 不修改 `SettingsRow` 组件本身的结构和渲染逻辑
    - 不修改其他任何 `SettingsRow` 或 `FeedbackRow` 的 `iconColor` 参数
    - _Bug_Condition: `isBugCondition(colorScheme, iconColor)` where `colorScheme == .dark AND iconColor == .black`_
    - _Expected_Behavior: 修复后 `watchSection` 传入 `SettingsRow` 的 `iconColor` 在任意 colorScheme 下均具有足够对比度（`iconColor != .black`，对比度 >= 3.0）_
    - _Preservation: 浅色模式下视觉效果与修复前等效；其他设置行 `iconColor` 参数不变；行标题文字和导航结构不受影响_
    - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.3_

  - [ ] 3.2 验证 Bug Condition 探索性测试现在通过
    - **Property 1: Expected Behavior** - 深色模式下图标清晰可见
    - **IMPORTANT**: 重新运行任务 1 中的同一测试——不要编写新测试
    - 任务 1 的测试编码了期望行为：`iconColor != .black` 且对比度 >= 3.0
    - 当此测试通过时，即确认期望行为已满足
    - 重新运行任务 1 中的 Bug Condition 探索性测试
    - **EXPECTED OUTCOME**: 测试 PASSES（确认 Bug 已修复）
    - _Requirements: 2.1, 2.2_

  - [ ] 3.3 验证保留性测试仍然通过
    - **Property 2: Preservation** - 浅色模式及其他行行为不变
    - **IMPORTANT**: 重新运行任务 2 中的同一测试——不要编写新测试
    - 重新运行任务 2 中的保留性属性测试
    - **EXPECTED OUTCOME**: 测试 PASSES（确认无回归）
    - 确认所有保留性测试在修复后仍然通过（无回归）
    - _Requirements: 3.1, 3.2, 3.3_

- [ ] 4. 检查点——确保所有测试通过
  - 确保 Bug Condition 探索性测试（任务 1）通过
  - 确保保留性属性测试（任务 2）通过
  - 在模拟器上切换深浅色模式，目视验证"翻页设置"行图标在两种模式下均清晰可见
  - 验证其他设置行（语言、主题、TTS、反馈）图标颜色未受影响
  - 如有疑问，请询问用户
