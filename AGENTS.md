# SnapNook Agent Guide

This file contains stable working rules for AI coding agents in this repository.
Keep detailed project background, current tasks, test checklists, and troubleshooting notes in `docs/`.

## Project

SnapNook is a native macOS menu bar screenshot utility written in Swift.

Supported areas:

- Area screenshot capture
- Floating screenshot preview
- Screenshot editor
- Local OCR through `Capture Text`
- Preferences for global shortcuts

The app runs as a menu bar utility with `LSUIElement = true`. It should not show a Dock icon or a normal main window during regular use.

## Reference Documents

- `docs/PROJECT_NOTES.md`: long-term project background, architecture, module map, and design constraints.
- `docs/TASKS.md`: current implementation scope, phase boundaries, and work rules.
- `docs/TESTING.md`: manual verification checklist.
- `docs/TROUBLESHOOTING.md`: crash analysis, build issues, and AppKit lifecycle notes.

Read the relevant document before changing related code.

## Tech Stack

- Language: Swift
- UI: AppKit + SwiftUI
- Package manager: Swift Package Manager
- Shortcut dependency: `sindresorhus/KeyboardShortcuts`
- OCR: Apple Vision `VNRecognizeTextRequest`
- Minimum platform: macOS 13

## Build

Preferred verified command:

```sh
env DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer bash scripts/build_app.sh
```

If the build fails because of user-directory cache or module-cache restrictions, use workspace-local caches:

```sh
mkdir -p .build/tmp-home .build/module-cache
env HOME=$PWD/.build/tmp-home \
  CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
  DEVELOPER_DIR=/Users/loners/Downloads/Xcode-beta.app/Contents/Developer \
  bash scripts/build_app.sh
```

`scripts/build_app.sh` must keep SwiftPM resource bundles in `.app/Contents/Resources`, especially `KeyboardShortcuts_KeyboardShortcuts.bundle`.

## Development Rules

- Think before coding. State assumptions when a request is ambiguous.
- Stop and ask when the requirement has multiple plausible meanings that would change the implementation.
- Keep changes surgical and directly tied to the current request.
- Do not refactor unrelated code.
- Prefer fixing the existing implementation over rewriting it.
- Do not add dependencies unless explicitly needed and justified.
- Do not add extra UI, onboarding, notifications, background services, persistence, or future-feature scaffolding without explicit request.
- Preserve existing AppKit activation and window lifecycle behavior.
- If a change touches capture, OCR, preview, editor rendering, or export, build the app and manually verify the affected flow.

## Product Boundaries

Allowed to maintain and improve:

- `Capture Area`
- `Capture Text`
- Floating preview
- Manual copy and save
- Screenshot editor annotations
- Existing editor crop behavior
- OCR flow
- Preferences and shortcuts
- Build and packaging scripts

Do not implement unless explicitly requested:

- Screen recording
- Scrolling screenshot
- Cloud sync
- Login or account system
- Auto update
- OCR history
- OCR translation
- Complex layer panel

## AppKit Rules

- Capture overlay windows must remain non-activating.
- Do not call `NSApp.activate(ignoringOtherApps:)`, `makeMain()`, or similar activation APIs when starting screenshot or OCR selection.
- Overlay windows may become key and set the content view as first responder, but SnapNook must not become the foreground active app.
- Hide the overlay before capturing the selected region.
- Do not synchronously close overlay windows and release controller-owned arrays from mouse event callbacks.
- Use strong controller ownership for `NSPanel`, `NSWindow`, `NSHostingView`, and preview controllers.
- Avoid `[unowned self]` in lifecycle code. Prefer `[weak self]` with safe unwrapping.
- Guard all close, cleanup, completion, timer, delayed callback, and delegate paths against double execution.

## Editor Rules

- Store annotations in original image coordinates, not window or view coordinates.
- Use `CanvasTransform` when converting between image and view coordinates.
- Keep handle sizes and hit-test tolerances fixed in view pixels.
- Render previews by overlaying annotations; do not mutate `originalImage`.
- Export from the original screenshot size unless an active crop is applied.
- Do not export selection boxes, handles, or helper lines.
- `Blur` and `Mosaic` must affect only their own rect.
- `Highlight` export must keep the selected region unchanged and darken the outside region.
- Undo and redo should record completed operations, not every drag frame.

## OCR Rules

`Capture Text` is not a normal screenshot flow.

It must:

- Use a distinct OCR selection mode.
- Hide the overlay before capturing the selected region.
- OCR the original selected screenshot region.
- Recognize `zh-Hans` and `en-US`.
- Copy only non-empty recognized text to the clipboard.
- Preserve existing clipboard contents when no text is recognized.
- Show lightweight HUD messages for recognizing, copied, no text, and failure states.

It must not:

- Show the floating preview.
- Open the editor.
- Open a save panel.
- Save an image.
- Copy an image.
- Overwrite the clipboard with empty text.
