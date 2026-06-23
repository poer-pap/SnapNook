# SnapNook AGENTS.md

## 项目简介

SnapNook 是一个使用 Swift 开发的 macOS 菜单栏截图工具。

当前阶段为 V1，目标是提供稳定的基础区域截图能力：
- 菜单栏常驻
- `Capture Area` / `Preferences` / `Quit` 菜单
- 全局快捷键
- 权限检查与系统设置引导
- 半透明全屏遮罩 + 拖拽选区
- `ESC` 取消截图
- 截图后显示左下角浮动预览
- 预览中手动复制到剪贴板
- 预览中手动保存 PNG 到用户选择的位置

## 当前技术方案

- 语言：Swift
- UI：AppKit + SwiftUI 混合
- 包管理：Swift Package Manager
- 快捷键依赖：`sindresorhus/KeyboardShortcuts`
- 应用形态：macOS 菜单栏工具，`LSUIElement = true`

## 项目结构

- `Package.swift`
  SwiftPM 包配置和依赖声明。
- `Sources/SnapNook/main.swift`
  App 入口。
- `Sources/SnapNook/AppDelegate.swift`
  应用生命周期、菜单栏和快捷键注册。
- `Sources/SnapNook/StatusItemController.swift`
  菜单栏菜单。
- `Sources/SnapNook/PreferencesWindowController.swift`
  Preferences 窗口和快捷键设置界面。
- `Sources/SnapNook/CaptureCoordinator.swift`
  截图主流程协调。
- `Sources/SnapNook/ScreenCapturePermissionService.swift`
  屏幕录制/截图权限检查和引导。
- `Sources/SnapNook/CaptureOverlayController.swift`
  截图遮罩、拖拽选区、ESC 取消。
- `Sources/SnapNook/ScreenCapturer.swift`
  实际截图。
- `Sources/SnapNook/ScreenshotWriter.swift`
  PNG 数据编码和文件保存。
- `Sources/SnapNook/ClipboardWriter.swift`
  剪贴板写入。
- `Sources/SnapNook/ScreenshotPreviewItem.swift`
  截图预览数据模型，持有 `NSImage`、PNG data、创建时间、截图区域和屏幕信息。
- `Sources/SnapNook/ScreenshotPreviewController.swift`
  截图后浮动预览窗口的生命周期、自动关闭、保存面板、固定尺寸和屏幕定位。
- `Sources/SnapNook/ScreenshotPreviewPanel.swift`
  透明无边框、非激活的浮动预览 `NSPanel`，固定尺寸为 `300x180`。
- `Sources/SnapNook/ScreenshotPreviewView.swift`
  固定尺寸预览缩略图、hover 操作按钮和 hover 毛玻璃背景。
- `Sources/SnapNook/Editor/CanvasTransform.swift`
  计算编辑画布中的 `displayedImageRect`，并负责 view/image 坐标互转。
- `Sources/SnapNook/Editor/AnnotationItem.swift`
  编辑器标注数据模型；当前支持矩形、箭头、文字和高亮，统一保存为原始图片坐标；`TextAnnotation` / `HighlightAnnotation` 使用 `rect`。
- `Sources/SnapNook/Editor/AnnotationRenderer.swift`
  标注渲染器；负责将图片坐标标注转换到当前视图坐标并绘制；`Highlight` 使用“区域外变暗、区域内挖空”的聚光灯效果。
- `Sources/SnapNook/Editor/EditorTool.swift`
  编辑器工具枚举；当前工具栏仅启用 `Select`、`Rectangle`、`Arrow`。
- `Sources/SnapNook/Editor/EditorCanvasView.swift`
  编辑器画布；显示原图，处理拖拽创建矩形/箭头/高亮、点击创建文字框、`Select` 模式下的命中检测、选中状态、二次编辑入口，以及 `Backspace` 删除选中标注。
- `Sources/SnapNook/Editor/ScreenshotEditorView.swift`
  编辑窗口根视图，组合顶部工具栏和画布区域。
- `Sources/SnapNook/Editor/EditorToolbarView.swift`
  编辑器顶部工具栏；提供工具选择、`Save as...`、`Done`。当前不显示 `Undo` / `Redo` 按钮。
- `Sources/SnapNook/Editor/UndoRedoManager.swift`
  编辑器命令式撤销/重做管理；当前用于新增和更新标注的 undo / redo。
- `Sources/SnapNook/Editor/EditedImageExporter.swift`
  导出编辑结果；输出“原图 + 当前标注”的合成 PNG。
- `Sources/SnapNook/Editor/ScreenshotEditorWindowController.swift`
  编辑窗口生命周期、工具切换、标注状态、撤销/重做和导出协调。
- `Sources/SnapNook/AlertPresenter.swift`
  失败提示。
- `Resources/Info.plist`
  App bundle 元数据。
- `scripts/build_app.sh`
  构建并组装 `.app`。

## 构建与运行

当前环境已验证可用的方式是使用 Xcode beta 的工具链，并显式指定 `DEVELOPER_DIR`：

```sh
env DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer bash scripts/build_app.sh
open .build/SnapNook.app
```

如果当前执行环境对用户目录写缓存有限制，导致 `swift build` / `build_app.sh` 报 `ModuleCache` 或 `sandbox-exec` 相关错误，可改用工作区内缓存目录：

```sh
mkdir -p .build/tmp-home .build/module-cache
env HOME=$PWD/.build/tmp-home \
  CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
  DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer \
  bash scripts/build_app.sh
open .build/SnapNook.app
```

如果系统已正确切换 `xcode-select`，也可以直接运行：

```sh
bash scripts/build_app.sh
open .build/SnapNook.app
```

## 测试重点

每次修改后至少手动验证以下流程：

1. App 启动后只显示菜单栏图标/标题，不显示 Dock 主窗口。
2. 菜单包含 `Capture Area`、`Preferences`、`Quit`。
3. `Preferences` 中可设置全局快捷键，默认值为 `Option + Shift + S`。
4. 无权限时，触发截图会弹出授权提示，并能打开系统设置。
5. 有权限时，触发截图会进入半透明遮罩模式。
6. 拖拽选区后会完成截图。
7. `ESC` 能取消截图。
8. 截图完成后会在目标屏幕 visibleFrame 左下角显示浮动预览，距离左边和底部约 24 px。
9. 浮动预览窗口尺寸固定为 `300x180`，不能跟随截图原图尺寸变化。
10. 浮动预览默认显示截图缩略图，不抢主窗口焦点，不显示 Dock 图标。
11. 缩略图必须在固定预览区域内按比例完整显示，不能拉伸变形；超宽图、超高图、小图都要正确显示。
12. 鼠标移入预览后显示 `Copy`、`Save`、`Close` 操作，并显示毛玻璃/模糊背景；鼠标移出后恢复普通缩略图状态。
13. 点击 `Close` 后立即关闭当前浮动预览，不保存图片，不复制图片，不弹确认框。
14. 点击 `Copy` 会复制当前截图原图到剪贴板，不能使用缩略图；复制成功后浮动预览关闭，且不会自动保存文件。
15. 点击 `Save` 会弹出 macOS 原生 `NSSavePanel`，默认文件名为 `SnapNook-yyyyMMdd-HHmmss.png`，用户可修改文件名和目录；确认保存后才写入原始 PNG 数据，取消时预览保持显示。
16. 默认 8 秒后自动关闭预览；鼠标悬停时暂停自动关闭。
17. 多显示器下预览优先出现在截图区域所在屏幕，兜底为当前鼠标所在屏幕。
18. 浮动预览左下角 `Edit` 可以打开编辑窗口，并显示截图原图。
19. 编辑窗口选择 `Rectangle` 工具后，鼠标在图片区域内任意方向拖拽可创建矩形；拖拽过程有实时预览，宽或高小于 `5 px` 时忽略。
20. 编辑窗口选择 `Arrow` 工具后，鼠标在图片区域内拖拽可创建箭头；拖拽过程有实时预览，长度小于 `8 px` 时忽略。
21. 编辑窗口缩放后，已有矩形和箭头标注必须继续和图片内容对齐，不能漂移。
22. 画出新的 `Rectangle` 或 `Arrow` 后，编辑器会自动回到 `Select`；新标注应立即可被再次点击选中并进入二次编辑。
23. `Select` 工具下，点击已有 `Rectangle` 或 `Arrow` 必须选中该标注；点击空白区域时取消当前选中。
24. `Rectangle` 选中后必须显示高亮边框和 `8` 个控制点；点击矩形内部可以进入移动，点击控制点可以进入调整大小。
25. `Arrow` 选中后必须显示起点/终点控制点；点击箭头线段可以进入移动，点击起点或终点可以进入方向/长度编辑。
26. `Undo` / `Redo` 需要覆盖新增和更新标注操作；拖拽过程中不要逐帧入栈，只在 `mouseUp` 时记录一次操作。
27. 编辑窗口 `Save as...` 导出的是“原图 + 当前 annotations”的合成 PNG，导出尺寸必须等于原始截图尺寸，且不能包含选中框、控制点或辅助虚线。
28. 编辑窗口选择 `Text` 工具后，点击图片区域应创建默认文字框并立即进入编辑；空文本点击外部后取消，不生成 annotation；有内容时点击外部后保存。
29. `TextAnnotation` 选中后必须可移动、可通过 `8` 个控制点调整大小；双击文字框应再次进入编辑；导出时只导出文字内容，不导出编辑态边框和控制点。
30. 编辑窗口选择 `Highlight` 工具后，拖拽创建的区域应表现为聚光灯效果：区域内保持原图，区域外统一变暗；选中后必须支持移动和 `8` 个控制点缩放。
31. `Select` 工具下选中任意 `Rectangle` / `Arrow` / `Text` / `Highlight` 后，按 `Backspace` 应删除该标注；若当前正在编辑文字，则 `Backspace` 只能删除文本内容，不能误删整个标注。

## V1 范围边界

当前不要实现以下功能：
- OCR
- 标注
- 录屏
- 滚动截图
- 云同步
- 登录
- 自动更新
- 编辑器

除非有明确需求，不要提前为这些功能铺设抽象层。

## V2 阶段 2 范围

当前已实现并允许继续维护的编辑能力仅包括：
- 矩形标注
- 箭头标注
- 文字标注
- 高亮标注
- `Select` 模式下的标注命中检测与选中
- 矩形的二次编辑入口：移动、控制点缩放
- 箭头的二次编辑入口：整体移动、起点/终点调整
- 文字框的创建、再次编辑、移动、控制点缩放
- 高亮框的移动、控制点缩放、聚光灯渲染
- `CanvasTransform` 坐标转换
- `Backspace` 删除选中标注
- 命令式 `Undo` / `Redo` 数据结构仍可保留，但当前工具栏不显示对应按钮
- 编辑后 `Save as...` 导出合成图

当前不要实现以下编辑能力：
- 模糊
- 马赛克
- 裁剪
- OCR
- 复杂图层面板

阶段 2 的实现约束：
- 标注数据必须保存为原始图片坐标，不要保存窗口坐标。
- 鼠标事件和 hit testing 使用 view coordinate；判断命中前先通过 `CanvasTransform` 将标注转换到 view coordinate。
- 控制点大小、命中容错范围使用固定 view 像素值，不跟随图片缩放。
- 预览渲染必须通过坐标转换叠加在原图之上，不要直接修改 `originalImage`。
- `TextAnnotation` 必须保存 `rect`，不要只保存 `origin`。
- `HighlightAnnotation` 必须导出聚光灯效果，即区域外变暗、区域内保持原图。
- 选中框、控制点、辅助虚线只允许在编辑器预览中显示，不能参与导出。
- 导出时必须基于原始截图尺寸重绘标注，保证导出结果和编辑器预览一致。
- 当前已知稳定策略是：新标注创建完成后自动切回 `Select`，降低“二次点击无效”风险。

## 修改约束

- 保持外科手术式修改，只改和当前需求直接相关的代码。
- 沿用当前按功能拆文件的结构，不要把逻辑重新塞回单文件。
- 优先先修复、先验证，再考虑扩展。
- 如果引入新能力，先确认它属于 V1 范围。
- 不要擅自加入额外 UI、引导页、通知系统或后台服务。

## 崩溃排查与窗口生命周期注意事项

- macOS 崩溃优先查看完整 `.ips`：
  - 常见位置：`~/Library/Logs/DiagnosticReports/`。
  - 如果找不到，继续查：`~/Library/Logs/DiagnosticReports/Retired/`。
  - 必须核对 `.ips` 中的 `slice_uuid` 和当前 `.build/SnapNook.app/Contents/MacOS/SnapNook` 的 `dwarfdump --uuid` 是否一致，避免分析旧版本崩溃。
- 对 `objc_release` / `EXC_BAD_ACCESS` 崩溃，不要只看崩溃栈顶；需要结合 unified log 判断最后进入的业务阶段：
  ```sh
  /usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.ethan.snapnook" OR process == "SnapNook"'
  ```
- 当前已知风险点是 AppKit 窗口释放时机：
  - `CaptureOverlayController` 管理的 overlay window 不要在 mouse event 回调中同步 `close()` 并立即释放数组。
  - 选区完成时应先 `orderOut(nil)` 隐藏遮罩，避免截图拍到遮罩。
  - 截图/取消流程结束后再 cleanup；cleanup 中延后一轮主循环关闭窗口。
  - overlay window 必须设置 `isReleasedWhenClosed = false`，由 controller 明确持有和释放。
- 所有 close / cleanup / completion 路径必须有状态保护，避免重复关闭同一个 window：
  - controller 级别保护 cleanup。
  - window 级别保护 close。
  - view 级别保护 completion。
- 如果新增 `NSPanel`、`NSWindow`、`NSHostingView` 或 preview 类 controller：
  - 不要只用局部变量创建 window/panel，必须由 controller 强引用。
  - 避免 `[unowned self]`；优先使用 `[weak self]` 并安全解包。
  - 检查 `DispatchQueue.main.asyncAfter`、`Timer`、SwiftUI `onDisappear` / `onHover`、`NSWindowDelegate` 回调是否访问已释放对象。
  - `ESC` 取消、截图完成、关闭按钮、自动消失等路径不能重复触发 close/dismiss。
- 调试窗口生命周期时，可以给关键 controller / window / view 临时加入 `deinit { print(...) }`，确认释放时机；问题确认后再决定是否保留。

## 已知注意点

- 单显示器稳定性优先，多显示器支持当前为尽量兼容。
- 截图权限和系统版本行为可能因 macOS 版本变化而不同，改动前先确认实际 API 表现。
- 当前构建依赖本机可用的 Xcode/Swift 工具链；如果 `swift build` 异常，先排查 `DEVELOPER_DIR` 或 `xcode-select`。
- 浮动预览定位必须基于 `NSScreen.visibleFrame` 计算，不能写死屏幕坐标，也不能复用上一次显示位置。
- 浮动预览窗口尺寸当前固定为 `300x180`；不要使用截图原图尺寸驱动 `NSPanel` / `NSWindow` 大小。
- 预览图只允许作为缩略图展示；复制和保存必须继续使用原图与原始 PNG 数据。
- 当前版本截图完成后只显示浮动预览，不自动保存到桌面或其他目录；是否保存仅由用户点击 `Save` 决定。
