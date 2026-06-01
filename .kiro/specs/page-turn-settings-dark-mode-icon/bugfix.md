# Bugfix Requirements Document

## Introduction

在设置页面（`SettingsView`）中，"翻页设置"（Watch 翻页控制）列表行前面的图标颜色被硬编码为 `.black`。在浅色模式下显示正常，但在深色模式（Dark Mode）下，黑色图标及其背景色与深色系统背景几乎融为一体，导致图标不可见或极难辨认，影响用户体验。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 用户在深色模式下打开设置页面 THEN 系统将"翻页设置"行的图标（`applewatch` SF Symbol）以黑色渲染，图标在深色背景上几乎不可见

1.2 WHEN 用户在深色模式下打开设置页面 THEN 系统将"翻页设置"行图标的背景圆角矩形以黑色（opacity 0.15）渲染，背景色与深色系统背景几乎无法区分

### Expected Behavior (Correct)

2.1 WHEN 用户在深色模式下打开设置页面 THEN 系统 SHALL 以能在深色背景上清晰可见的颜色渲染"翻页设置"行的图标

2.2 WHEN 用户在深色模式下打开设置页面 THEN 系统 SHALL 以能在深色背景上清晰可见的颜色渲染"翻页设置"行图标的背景圆角矩形

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 用户在浅色模式下打开设置页面 THEN 系统 SHALL CONTINUE TO 以黑色（或视觉等效颜色）正常渲染"翻页设置"行的图标及其背景

3.2 WHEN 用户在任意主题模式下打开设置页面 THEN 系统 SHALL CONTINUE TO 正常渲染其他设置行（语言、主题、TTS、反馈等）的图标颜色，不受本次修改影响

3.3 WHEN 用户在任意主题模式下打开设置页面 THEN 系统 SHALL CONTINUE TO 正常显示"翻页设置"行的文字标题和导航箭头
