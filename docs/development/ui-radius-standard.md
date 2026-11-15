# 圆角规范（UI corner-radius standard）

全站所有页面的圆角只有一个标准值，且只有一个来源。

## 单一标准值

- 标准圆角：**20px**。
- 唯一来源：`shared/lib/ui/shape.dart` 中的 `AppCorner.standard`。
- `AppRadius.standard`（`BorderRadius`）与 `AppShape.standard`（`RoundedSuperellipseBorder`）都由它派生，禁止在其它地方重复定义数字。

调整全站圆角时，只需改 `AppCorner.standard` 一处。

## 使用方式

| 场景 | 用法 |
| --- | --- |
| 需要 `double` 半径 | `AppCorner.standard` |
| 需要 `BorderRadius` | `AppRadius.standard` |
| 需要 `ShapeBorder`（`shape:` / `customBorder:`） | `AppShape.standard` |
| 仅顶部圆角（如底部弹层） | `AppShape.top(AppCorner.standard)` |
| 分组列表首/尾行圆角 | `AppRadius.vertical(top:/bottom: AppCorner.standard)` |

主题层（卡片、弹窗、底部弹层、SnackBar、Chip、PopupMenu、输入框、FAB、导航指示器、进度条、各类按钮）统一在 `AppShapeThemeExt.withAppShapes` 中按标准值配置，页面无需重复设置。

## 唯一例外：直角

`AppCorner.none` / `AppRadius.none` / `AppShape.none`（值为 `0`）仅用于**结构性直角**：

- 贴合屏幕边缘的侧边面板（`side_sheet`）；
- 分组列表中间行的内侧边（只让首/尾行圆角）。

除此之外不得使用 `0`。

## 禁止事项

- 在页面或组件里直接写数字圆角，例如 `BorderRadius.circular(12)`、`AppShape.all(10)`。
- 使用 `CircleBorder`、`StadiumBorder`、`RoundedRectangleBorder` 等“另一套”形状。
- 另建圆角常量类或分散的 `*Corner` 配置（旧 `DashboardCorner`、`dashboardCardRadius` 已移除）。

## 不属于 UI 圆角配置的几何

以下为渲染引擎或图画内部的**算法几何**，保持其按尺寸计算的值，不要改成标准值：`goo.dart`、`liquid_glass*.dart` 的 `shortestSide/2` 收敛、`icons/glyph.dart` 与 `icons/caption_icon.dart` 的字形路径、`widgets/appearance/mini_screen_painter.dart` 的圆点、`desktop_window_preview.dart` 按 `* u` 缩放的窗口缩略图。
