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
- 预览中手动保存 PNG 到 `~/Desktop/SnapNook/`

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
  截图预览数据模型，持有 `NSImage`、PNG data、截图区域和屏幕信息。
- `Sources/SnapNook/ScreenshotPreviewController.swift`
  截图后浮动预览窗口的生命周期、自动关闭、Pin、固定尺寸和屏幕定位。
- `Sources/SnapNook/ScreenshotPreviewPanel.swift`
  透明无边框、非激活的浮动预览 `NSPanel`，固定尺寸为 `300x180`。
- `Sources/SnapNook/ScreenshotPreviewView.swift`
  固定尺寸预览缩略图、hover 操作按钮和 hover 毛玻璃背景。
- `Sources/SnapNook/AlertPresenter.swift`
  失败提示。
- `Resources/Info.plist`
  App bundle 元数据。
- `scripts/build_app.sh`
  构建并组装 `.app`。

## 构建与运行

当前环境已验证可用的方式是使用 Xcode beta 的工具链，并显式指定 `DEVELOPER_DIR`：

```sh
env DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer scripts/build_app.sh
open .build/SnapNook.app
```

如果系统已正确切换 `xcode-select`，也可以直接运行：

```sh
scripts/build_app.sh
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
12. 鼠标移入预览后显示 `Copy`、`Save`、`Close`、`Pin` 操作，并显示毛玻璃/模糊背景；鼠标移出后恢复普通缩略图状态。
13. 点击 `Copy` 会复制当前截图原图到剪贴板，不能使用缩略图。
14. 点击 `Save` 会保存当前截图原始 PNG 到 `~/Desktop/SnapNook/`，命名格式为 `SnapNook-yyyyMMdd-HHmmss.png`。
15. 默认 8 秒后自动关闭预览；鼠标悬停时暂停自动关闭。
16. 点击 `Pin` 后预览不会自动关闭。
17. 多显示器下预览优先出现在截图区域所在屏幕，兜底为当前鼠标所在屏幕。

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
