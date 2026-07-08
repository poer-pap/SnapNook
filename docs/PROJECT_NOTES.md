# 项目长期背景

SnapNook 是一个使用 Swift 开发的原生 macOS 菜单栏截图工具。应用以菜单栏常驻为核心，不应在常规使用中显示 Dock 图标或普通主窗口。

当前项目已覆盖四个主要产品区域：

- 基础区域截图
- 截图后浮动预览
- 截图编辑器
- `Capture Text` 本地 OCR
- V4 `Scrolling Capture` 滚动截屏 MVP

## 技术方案

- 语言：Swift
- UI：AppKit + SwiftUI 混合架构
- 包管理：Swift Package Manager
- 快捷键依赖：`sindresorhus/KeyboardShortcuts`
- OCR：Apple Vision `VNRecognizeTextRequest`
- 应用形态：macOS 菜单栏工具，`LSUIElement = true`
- 最低平台：macOS 13

## 代码结构

- `Package.swift`
  SwiftPM 包配置和依赖声明。
- `Sources/SnapNook/main.swift`
  App 入口。
- `Sources/SnapNook/AppDelegate.swift`
  应用生命周期、菜单栏初始化和快捷键注册。
- `Sources/SnapNook/KeyboardShortcuts+Names.swift`
  全局快捷键名称与默认值。
- `Sources/SnapNook/StatusItemController.swift`
  菜单栏菜单。
- `Sources/SnapNook/PreferencesWindowController.swift`
  Preferences 窗口和快捷键设置界面。
- `Sources/SnapNook/CaptureCoordinator.swift`
  截图和 OCR 主流程协调。
- `Sources/SnapNook/ScreenCapturePermissionService.swift`
  屏幕录制/截图权限检查和系统设置引导。
- `Sources/SnapNook/CaptureOverlayController.swift`
  全屏框选 overlay、拖拽选区和 `ESC` 取消。
- `Sources/SnapNook/ScreenCapturer.swift`
  实际屏幕截取，包括普通区域截图和滚动截屏使用的 below-window 捕获辅助。
- `Sources/SnapNook/ScrollingCapture/`
  V4 滚动截屏模块，包含选择框 overlay、捕获控制器、实时预览面板和长图拼接器。
- `Sources/SnapNook/ScreenshotWriter.swift`
  PNG 数据编码和文件保存。
- `Sources/SnapNook/ClipboardWriter.swift`
  图片和纯文本剪贴板写入。
- `Sources/SnapNook/OCRService.swift`
  本地 OCR 服务。
- `Sources/SnapNook/OCR/OCRTextPostProcessor.swift`
  OCR 结果后处理。
- `Sources/SnapNook/ToastController.swift`
  轻量 HUD 提示。
- `Sources/SnapNook/ScreenshotPreviewItem.swift`
  截图预览数据模型。
- `Sources/SnapNook/ScreenshotPreviewController.swift`
  浮动预览窗口生命周期、自动关闭、保存面板和屏幕定位。
- `Sources/SnapNook/ScreenshotPreviewPanel.swift`
  透明无边框、非激活浮动预览 `NSPanel`。
- `Sources/SnapNook/ScreenshotPreviewView.swift`
  固定尺寸预览缩略图、hover 操作按钮和 hover 背景。
- `Sources/SnapNook/Editor/`
  编辑器画布、工具栏、标注模型、渲染、导出、图片效果、裁剪状态和 undo/redo。
- `Resources/Info.plist`
  App bundle 元数据。
- `scripts/build_app.sh`
  构建并组装 `.build/SnapNook.app`。
- `Tests/SnapNookTests/OCRTextPostProcessorTests.swift`
  OCR 文本后处理测试。

## 截图流程

`Capture Area` 是普通截图流程：

1. 检查截图权限。
2. 显示非激活全屏 overlay。
3. 用户拖拽选区。
4. 隐藏 overlay 后截取选区原图。
5. 显示左下角浮动预览。
6. 用户可手动复制、保存、关闭或进入编辑器。

截图完成后不自动保存到桌面或其他目录。保存只由用户点击预览中的 `Save` 触发。

## 滚动截屏流程

`Scrolling Capture` 是独立于普通区域截图和 OCR 的 V4 功能：

1. 检查截图权限。
2. 在当前鼠标所在屏幕显示滚动截屏选择框。
3. 开始前选择框可移动、可通过边框和控制点调整大小。
4. 点击 `Start Capture` 后固定选区，滚轮事件继续传递给底层网页或文档。
5. 以低频连续捕获选区内容，并用 `ScrollingStitcher` 合成长图。
6. 右侧显示长图缩略预览和当前高度，不显示帧数。
7. 点击 `Done` 后复用现有浮动预览，用户可继续 `Copy`、`Save` 或 `Edit`。
8. 点击 `Cancel` 或按 `ESC` 时清理临时状态，不保存、不复制、不显示浮动预览。

当前 V4.0 仍是 MVP：主要支持手动向下滚动，不做自动滚动；对虚拟列表、视频、动画、动态加载区域或滚动过快场景，拼接可能不稳定。后续目标是接入 ScreenCaptureKit 连续捕获主路径。

## OCR 流程

`Capture Text` 是独立 OCR 流程，不是普通截图：

1. 检查截图权限。
2. 进入独立文字框选模式。
3. 隐藏 overlay 后截取选区原图。
4. 使用 Vision 执行本地 OCR。
5. 非空识别结果自动复制为纯文本。
6. 使用 HUD 提示识别中、成功、空结果或失败。

OCR 空结果不能覆盖已有剪贴板内容。OCR 流程不能显示浮动预览、打开编辑器、打开保存面板或保存图片。

## 编辑器设计

编辑器当前围绕“原图 + 标注 + 可选裁剪”工作：

- 标注数据保存为原始图片坐标。
- 鼠标事件和命中检测使用 view coordinate。
- 坐标转换统一通过 `CanvasTransform` 完成。
- 预览渲染通过坐标转换叠加在原图之上，不直接修改 `originalImage`。
- 导出时基于原始截图尺寸重绘；如果存在 active crop，则导出裁剪区域。
- 选中框、控制点和辅助线只允许出现在编辑器预览中，不能参与导出。

当前编辑器工具包括：

- `Select`
- `Rectangle`
- `Arrow`
- `Text`
- `Highlight`
- `Blur`
- `Mosaic`
- `Crop`

`Highlight` 导出为聚光灯效果：选中区域保持原图，区域外变暗。
`Blur` 和 `Mosaic` 只允许在各自 rect 内生效，区域外保持原图。

## 构建约束

推荐构建命令：

```sh
env DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer bash scripts/build_app.sh
```

如果当前执行环境对用户目录写缓存有限制，导致 `swift build` 或 `build_app.sh` 报 `ModuleCache`、`sandbox-exec` 等错误，可改用工作区内缓存目录：

```sh
mkdir -p .build/tmp-home .build/module-cache
env HOME=$PWD/.build/tmp-home \
  CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
  DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer \
  bash scripts/build_app.sh
```

如果系统已正确切换 `xcode-select`，也可以直接运行：

```sh
bash scripts/build_app.sh
```

`KeyboardShortcuts.Recorder` 依赖 SwiftPM 资源 bundle 中的本地化字符串。`scripts/build_app.sh` 打包 `.app` 时必须保留 `KeyboardShortcuts_KeyboardShortcuts.bundle`，否则打开 `Preferences` 时可能因为 `Bundle.module` 找不到资源而崩溃。
