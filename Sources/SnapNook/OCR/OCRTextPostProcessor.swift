import Foundation

struct OCRTextPostProcessor {
    private static let codeLikeKeywords = [
        "func", "let", "var", "class", "struct", "import", "return", "if", "else",
        "for", "while", "guard", "switch", "case", "enum", "protocol", "extension"
    ]

    private static let lineReplacementMap: [(String, String)] = [
        ("——", "-"),
        ("（", "("),
        ("）", ")"),
        ("［", "["),
        ("］", "]"),
        ("【", "["),
        ("】", "]"),
        ("｛", "{"),
        ("｝", "}"),
        ("：", ":"),
        ("，", ","),
        ("。", "."),
        ("；", ";"),
        ("！", "!"),
        ("？", "?"),
        ("“", "\""),
        ("”", "\""),
        ("‘", "'"),
        ("’", "'"),
        ("、", "/"),
        ("｜", "|"),
        ("－", "-"),
        ("＝", "="),
        ("＜", "<"),
        ("＞", ">")
    ]

    private static let mixedLineReplacementMap: [Character: Character] = [
        "（": "(",
        "）": ")",
        "［": "[",
        "］": "]",
        "【": "[",
        "】": "]",
        "｛": "{",
        "｝": "}",
        "：": ":",
        "，": ",",
        "。": ".",
        "；": ";",
        "！": "!",
        "？": "?",
        "“": "\"",
        "”": "\"",
        "‘": "'",
        "’": "'",
        "、": "/",
        "｜": "|",
        "－": "-",
        "＝": "=",
        "＜": "<",
        "＞": ">"
    ]

    static func process(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                guard !line.isEmpty else { return line }
                if isCodeLikeLine(line) {
                    return normalizeCodeLikeLine(line)
                }
                return normalizeMixedLanguageLine(line)
            }
            .joined(separator: "\n")
    }

    private static func isCodeLikeLine(_ line: String) -> Bool {
        let lowered = line.lowercased()

        if codeLikeKeywords.contains(where: { lowered.contains($0) }) {
            return true
        }

        let codeIndicators = [
            "->", "=>", "::", "http", "https", "/", "\\", "()", "[]", "{}",
            "（", "）", "［", "］", "｛", "｝"
        ]
        if codeIndicators.contains(where: { line.contains($0) }) {
            return true
        }

        if line.range(of: #"[A-Za-z_][A-Za-z0-9_]*[\.\(（\[]+"#, options: .regularExpression) != nil {
            return true
        }

        if line.range(of: #"\b[a-z]+[A-Z][A-Za-z0-9]*\b"#, options: .regularExpression) != nil {
            return true
        }

        if line.range(of: #"\b[A-Za-z0-9]+_[A-Za-z0-9_]+\b"#, options: .regularExpression) != nil {
            return true
        }

        let chars = Array(line)
        guard !chars.isEmpty else { return false }

        let asciiLikeCount = chars.filter { isLatinDigitOrCodeChar($0) }.count
        let ratio = Double(asciiLikeCount) / Double(chars.count)
        let containsCJK = chars.contains { $0.isCJKUnifiedIdeograph }
        return !containsCJK && ratio >= 0.6 && asciiLikeCount >= 4
    }

    private static func normalizeCodeLikeLine(_ line: String) -> String {
        var normalized = line
        for (fullWidth, halfWidth) in lineReplacementMap {
            normalized = normalized.replacingOccurrences(of: fullWidth, with: halfWidth)
        }
        return normalized
    }

    private static func normalizeMixedLanguageLine(_ line: String) -> String {
        let chars = Array(line)
        guard !chars.isEmpty else { return line }

        var result = ""
        result.reserveCapacity(line.count)

        for index in chars.indices {
            let char = chars[index]

            if char == "—", index + 1 < chars.count, chars[index + 1] == "—",
               hasLatinOrDigitNearby(chars, index: index, range: 2) ||
               hasLatinOrDigitNearby(chars, index: index + 1, range: 2) {
                result.append("-")
                continue
            }

            guard let replacement = mixedLineReplacementMap[char] else {
                if index > 0, chars[index - 1] == "—", char == "—",
                   hasLatinOrDigitNearby(chars, index: index, range: 2) {
                    continue
                }
                result.append(char)
                continue
            }

            if shouldReplace(char: char, in: chars, at: index) {
                result.append(replacement)
            } else {
                result.append(char)
            }
        }

        return result
    }

    private static func shouldReplace(char: Character, in chars: [Character], at index: Int) -> Bool {
        switch char {
        case "（", "）", "［", "］", "【", "】", "｛", "｝":
            return hasLatinOrDigitNearby(chars, index: index)
        case "：":
            return hasCodeSignalOnEitherSide(chars, index: index)
        case "，", "。", "；", "！", "？", "｜", "－", "＝", "＜", "＞":
            return hasLatinOrDigitNearby(chars, index: index, range: 2)
        case "“", "”", "‘", "’":
            return quotedContentLooksCode(in: chars, at: index)
        case "、":
            return hasSlashContext(in: chars, at: index)
        default:
            return false
        }
    }

    private static func quotedContentLooksCode(in chars: [Character], at index: Int) -> Bool {
        let windowStart = max(0, index - 12)
        let windowEnd = min(chars.count - 1, index + 12)
        let window = chars[windowStart...windowEnd]
        let snippet = String(window)

        if snippet.range(of: #"[A-Za-z0-9_/\.\-]+"#, options: .regularExpression) != nil {
            return true
        }

        return hasLatinOrDigitNearby(chars, index: index, range: 6)
    }

    private static func hasSlashContext(in chars: [Character], at index: Int) -> Bool {
        if hasLatinOrDigitNearby(chars, index: index, range: 2) {
            return true
        }

        let prev = previousMeaningfulCharacter(in: chars, before: index)
        let next = nextMeaningfulCharacter(in: chars, after: index)
        return prev == ":" || prev == "." || next == "." || next == "/"
    }

    private static func hasCodeSignalOnEitherSide(_ chars: [Character], index: Int) -> Bool {
        let prev = previousMeaningfulCharacter(in: chars, before: index)
        let next = nextMeaningfulCharacter(in: chars, after: index)

        if let prev, isLatinDigitOrCodeChar(prev) {
            return true
        }

        if let next, next == "/" || next == "\\" {
            return true
        }

        return false
    }

    private static func previousMeaningfulCharacter(in chars: [Character], before index: Int) -> Character? {
        guard index > 0 else { return nil }
        for previousIndex in stride(from: index - 1, through: 0, by: -1) {
            let char = chars[previousIndex]
            if !char.isWhitespace {
                return char
            }
        }
        return nil
    }

    private static func nextMeaningfulCharacter(in chars: [Character], after index: Int) -> Character? {
        guard index + 1 < chars.count else { return nil }
        for nextIndex in (index + 1)..<chars.count {
            let char = chars[nextIndex]
            if !char.isWhitespace {
                return char
            }
        }
        return nil
    }

    private static func hasLatinOrDigitNearby(_ chars: [Character], index: Int, range: Int = 3) -> Bool {
        let start = max(0, index - range)
        let end = min(chars.count - 1, index + range)

        for nearbyIndex in start...end where nearbyIndex != index {
            if isLatinDigitOrCodeChar(chars[nearbyIndex]) {
                return true
            }
        }

        return false
    }

    private static func isLatinDigitOrCodeChar(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "_./\\-:=<>[]{}()\"'`$".contains(char))
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    var isASCII: Bool {
        unicodeScalars.allSatisfy(\.isASCII)
    }

    var isLetter: Bool {
        unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    var isNumber: Bool {
        unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    var isCJKUnifiedIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
