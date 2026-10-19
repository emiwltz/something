// something builds with the Command Line Tools alone, without Xcode. Some SwiftUI attributes are macros whose plugin
// comes only with Xcode (`@State`: "plugin for module 'SwiftUIMacros' not found"): a source that uses one builds on a
// Mac with Xcode, CI's included, and fails on a newcomer's. So every attribute in Sources/ is one of this list, and
// no source uses #Preview or #Playground. A word joins the list only after Sources/ built with it under
// DEVELOPER_DIR=/Library/Developer/CommandLineTools; @State, @Entry, @Previewable, @AppStorage, @StateObject and
// @ObservedObject stay out.
import Foundation
import Testing

@Suite struct ToolchainTests {
    static let allowed: Set<String> = [
        "Observable", "ObservationIgnored", "Bindable", "Environment", "FocusState", "MainActor", "Sendable", "escaping",
        "discardableResult", "objc", "unchecked", "available", "inline", "testable", "main", "frozen", "usableFromInline",
        "Test", "Suite", "preconcurrency", "autoclosure", "dynamicMemberLookup", "propertyWrapper", "resultBuilder",
        "ViewBuilder", "unknown",
    ]
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources")

    /// The code of `text` without its comments and string literals, where an @ is not an attribute.
    static func code(_ text: String) -> String {
        var code = "", rest = Substring(text)
        func skip(to end: String) { rest = rest.range(of: end).map { rest[$0.upperBound...] } ?? "" }
        while let first = rest.first {
            if rest.hasPrefix("//") { skip(to: "\n"); code += "\n" }
            else if rest.hasPrefix("/*") { skip(to: "*/") }
            else if first == "\"" || first == "#" && rest.dropFirst().drop(while: { $0 == "#" }).first == "\"" {
                // A literal ends at its quotes followed by as many # as it began with; an escaped quote is skipped.
                let hashes = String(rest.prefix { $0 == "#" }), quotes = rest.dropFirst(hashes.count).hasPrefix("\"\"\"") ? "\"\"\"" : "\""
                rest = rest.dropFirst(hashes.count + quotes.count)
                while !rest.isEmpty, !rest.hasPrefix(quotes + hashes) { rest = rest.dropFirst(rest.hasPrefix("\\" + hashes) ? 1 + hashes.count + 1 : 1) }
                rest = rest.dropFirst(quotes.count + hashes.count)
                code += " "
            } else { code.append(first); rest = rest.dropFirst() }
        }
        return code
    }

    /// The attribute words of `text` (`@State` gives "State"), comments and strings left out.
    static func attributes(_ text: String) -> Set<String> {
        let code = code(text)
        let found = try! NSRegularExpression(pattern: "@([A-Za-z_][A-Za-z0-9_]*)")
            .matches(in: code, range: NSRange(code.startIndex..., in: code))
        return Set(found.compactMap { Range($0.range(at: 1), in: code).map { String(code[$0]) } })
    }

    @Test func everyAttributeBuildsWithTheCommandLineTools() throws {
        let files = (FileManager.default.enumerator(atPath: sources.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".swift") }
        #expect(files.count > 20, "Sources/ was not found at \(sources.path)")
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let refused = ToolchainTests.attributes(text).subtracting(ToolchainTests.allowed)
            #expect(refused.isEmpty, "Sources/\(file) uses \(refused.sorted().map { "@" + $0 }), which the Command Line Tools may not build")
            #expect(!ToolchainTests.code(text).contains("#Preview") && !ToolchainTests.code(text).contains("#Playground"),
                    "Sources/\(file) uses #Preview or #Playground, which need Xcode")
        }
    }

    /// The scan sees an attribute in code, and none in a comment or a string, raw or on several lines.
    @Test func theScanSeesCodeOnly() {
        #expect(ToolchainTests.attributes("struct A: View { @State var n = 0 }") == ["State"])
        #expect(ToolchainTests.attributes(#"""
            // @State in a comment
            /* @Entry */ let a = "npm install @example/tool", b = #"say "@Previewable""#
            let c = """
                @media (prefers-color-scheme: dark) { }
                """
            let d = "an escaped quote \" then @AppStorage"
            @MainActor func e() {}
            """#) == ["MainActor"])
    }
}
