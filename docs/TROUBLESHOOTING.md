# 排障指南

本文档记录 SnapNook 常见构建、崩溃和 AppKit 生命周期问题的排查入口。

## 构建失败

推荐先使用明确的 Xcode beta 工具链：

```sh
env DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer bash scripts/build_app.sh
```

如果 `swift build` 或 `build_app.sh` 报 `ModuleCache`、`sandbox-exec`、用户目录缓存权限等问题，改用工作区内缓存：

```sh
mkdir -p .build/tmp-home .build/module-cache
env HOME=$PWD/.build/tmp-home \
  CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
  DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer \
  bash scripts/build_app.sh
```

如果系统已正确切换 `xcode-select`，也可以尝试：

```sh
bash scripts/build_app.sh
```

## Preferences 打开崩溃

`KeyboardShortcuts.Recorder` 依赖 SwiftPM 资源 bundle 中的本地化字符串。

检查 `.app` 内是否存在资源 bundle：

```sh
find .build/SnapNook.app/Contents/Resources -maxdepth 1 -name '*KeyboardShortcuts*.bundle' -print
```

如果缺失，重点检查 `scripts/build_app.sh` 是否把 SwiftPM 依赖生成的 `*.bundle` 复制到了 `.app/Contents/Resources`。

缺失时的典型表现是打开 `Preferences` 创建 recorder 时因为 `Bundle.module` 找不到资源而触发 `EXC_BREAKPOINT` / `SIGTRAP`。

## 崩溃报告

macOS 崩溃优先查看完整 `.ips`，不要只看短栈。

常见位置：

```sh
ls -lt ~/Library/Logs/DiagnosticReports/ | head
ls -lt ~/Library/Logs/DiagnosticReports/Retired/ | head
```

必须核对 `.ips` 中的 `slice_uuid` 和当前二进制 UUID 是否一致，避免分析旧版本崩溃：

```sh
dwarfdump --uuid .build/SnapNook.app/Contents/MacOS/SnapNook
```

对 `objc_release` / `EXC_BAD_ACCESS` 崩溃，不要只看崩溃栈顶。结合 unified log 判断最后进入的业务阶段：

```sh
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.ethan.snapnook" OR process == "SnapNook"'
```

## Overlay 生命周期

当前已知风险点是 AppKit 窗口释放时机。

排查或修改 overlay 时检查：

- `CaptureOverlayController` 的框选窗口必须保持非激活。
- 不要在开始截图或 OCR 时调用 `NSApp.activate(ignoringOtherApps:)`、`makeMain()` 或其他会切走当前前台应用焦点的 API。
- 截图和 `Capture Text` 都必须支持在其他 App 的下拉菜单、弹出菜单等临时 UI 展开时触发。
- 启动 overlay 不能导致这些临时 UI 因失焦而消失。
- overlay 可以成为 key window，并让 content view 成为 first responder，以接收拖拽和 `ESC`。
- overlay 不能把 SnapNook 激活为前台应用。
- 不要在 mouse event 回调中同步 `close()` 并立即释放窗口数组。
- 选区完成时应先 `orderOut(nil)` 隐藏遮罩，避免截图拍到遮罩。
- 截图、OCR 或取消流程结束后再 cleanup。
- cleanup 中关闭窗口应延后一轮主循环。
- overlay window 必须设置 `isReleasedWhenClosed = false`。
- controller 必须明确持有 overlay window。

## 关闭和释放保护

所有 close、cleanup、completion 路径都需要状态保护，避免重复关闭同一个 window：

- controller 级别保护 cleanup。
- window 级别保护 close。
- view 级别保护 completion。

如果新增 `NSPanel`、`NSWindow`、`NSHostingView` 或 preview 类 controller：

- 不要只用局部变量创建 window 或 panel。
- 必须由 controller 强引用窗口对象。
- 避免 `[unowned self]`。
- 优先使用 `[weak self]` 并安全解包。
- 检查 `DispatchQueue.main.asyncAfter`、`Timer`、SwiftUI `onDisappear` / `onHover`、`NSWindowDelegate` 回调是否访问已释放对象。
- `ESC` 取消、截图完成、关闭按钮、自动消失等路径不能重复触发 close 或 dismiss。

调试窗口生命周期时，可以给关键 controller、window 或 view 临时加入：

```swift
deinit {
    print("deinit \(Self.self)")
}
```

问题确认后再决定是否保留。

## 常见行为约束

- 单显示器稳定性优先，多显示器支持当前为尽量兼容。
- 截图权限和系统版本行为可能因 macOS 版本变化而不同，改动前先确认实际 API 表现。
- 浮动预览定位必须基于 `NSScreen.visibleFrame`。
- 浮动预览窗口尺寸固定为 `300x180`。
- 预览图只允许作为缩略图展示。
- 复制和保存必须继续使用原图与原始 PNG 数据。
- 当前版本截图完成后只显示浮动预览，不自动保存到桌面或其他目录。
