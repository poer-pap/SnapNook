import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self(
        "captureArea",
        default: .init(.s, modifiers: [.option, .shift])
    )

    static let captureText = Self("captureText")
}
