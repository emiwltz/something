// What the code of every agent extension (Sources/Agent*) respects, by a scan of its text, comments and strings left
// out (ToolchainTests.code). A driver or a reader runs inside the app, and a trap there takes the whole app down, so
// none of the ways to trap on purpose: force unwrap, `as!`, `try!`, `fatalError`, `precondition` (architecture 2.3;
// the conformance suite feeds them damaged input, which finds the others, an index out of range among them). And it
// stays portable (architecture 5.3): no extension imports Darwin or calls what only Darwin has (Foundation re-exports
// it on the Mac, so the import alone proves little), the host imports it only in its platform files (the process
// table, the spawner, file stamps and the test guard), and an extension guesses no home folder: its agent's folders
// come from the environment it is given, and the host's from the app's Places.
import Foundation
import Testing

@Suite struct ExtensionRulesTests {
    static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources")
    /// The host's files that may import Darwin.
    static let platform: Set = ["Processes.swift", "Spawn.swift", "Tail.swift", "TestRunGuard.swift"]

    /// The Swift files of each target folder of Sources/ whose name passes `which`, by target/file, with their text.
    static func files(_ which: (String) -> Bool) throws -> [(name: String, text: String)] {
        try FileManager.default.contentsOfDirectory(atPath: sources.path).filter(which).sorted().flatMap { target in
            try FileManager.default.contentsOfDirectory(atPath: sources.appendingPathComponent(target).path).filter { $0.hasSuffix(".swift") }.sorted()
                .map { ("\(target)/\($0)", try String(contentsOf: sources.appendingPathComponent("\(target)/\($0)"), encoding: .utf8)) }
        }
    }

    /// The lines of `text` that can trap, by number: a `!` that unwraps (after a name, `)` or `]`, and not `!=`),
    /// `fatalError`, `precondition` and `preconditionFailure`. `as!` and `try!` are the same `!`.
    static func traps(_ text: String) -> [Int] {
        lines(text, #"[A-Za-z0-9_)\]]!(?!=)|\bfatalError\b|\bprecondition(Failure)?\b"#)
    }

    /// The lines of `text`'s code that match `pattern`, by number.
    static func lines(_ text: String, _ pattern: String) -> [Int] {
        ToolchainTests.code(text).components(separatedBy: "\n").enumerated().compactMap { number, line in
            line.range(of: pattern, options: .regularExpression) == nil ? nil : number + 1
        }
    }

    /// The modules `text` imports, by their top name: `@preconcurrency import Darwin`, `import Darwin.C` and
    /// `import struct Darwin.stat` all import Darwin.
    static func imports(_ text: String) -> Set<String> {
        let kinds: Set<Substring> = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]
        return Set(ToolchainTests.code(text).components(separatedBy: "\n").compactMap { line in
            let words = line.split(separator: " ").drop { $0.hasPrefix("@") }
            guard words.first == "import", let name = words.dropFirst().first(where: { !kinds.contains($0) }) else { return nil }
            return name.split(separator: ".").first.map(String.init)
        })
    }

    /// What only Darwin has, which an extension reaches through Foundation without importing Darwin.
    static let darwinOnly = #"\b(sysctl\w*|proc_\w+|libproc|kqueue|kevent|getpid|mach_\w+)\b"#

    @Test func noExtensionCanTrap() throws {
        let files = try ExtensionRulesTests.files { $0.hasPrefix("Agent") }
        #expect(files.count >= 10, "Sources/Agent* was not found at \(ExtensionRulesTests.sources.path)")
        for file in files {
            let lines = ExtensionRulesTests.traps(file.text)
            #expect(lines.isEmpty, "Sources/\(file.name) can trap at line \(lines.map(String.init).joined(separator: ", ")): an extension never unwraps by force")
        }
    }

    @Test func theScanSeesTrapsInCodeOnly() {
        #expect(ExtensionRulesTests.traps("let a = b!\nlet c = d as! Int\nlet e = try! f()\nfatalError(\"no\")\nlet g = h![0]\nlet i = j()!\nprecondition(k)\npreconditionFailure()") == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(ExtensionRulesTests.traps(#"""
            // b! in a comment
            if !done, a != b, !(c ?? false) { }
            let text = "Hello! as! try!", raw = #"x!"#
            let k = l?.m ?? n
            """#).isEmpty)
    }

    @Test func darwinStaysInThePlatformFiles() throws {
        for file in try ExtensionRulesTests.files({ $0.hasPrefix("Agent") || $0 == "SomethingAgents" }) {
            guard !(file.name.hasPrefix("SomethingAgents/") && ExtensionRulesTests.platform.contains((file.name as NSString).lastPathComponent)) else { continue }
            #expect(ExtensionRulesTests.imports(file.text).isDisjoint(with: ["Darwin", "Glibc"]),
                    "Sources/\(file.name) imports Darwin: a port would have to rewrite it. Use Foundation, or a helper of the host's platform files.")
            let lines = ExtensionRulesTests.lines(file.text, ExtensionRulesTests.darwinOnly)
            #expect(lines.isEmpty, "Sources/\(file.name) calls what only Darwin has at line \(lines.map(String.init).joined(separator: ", ")): leave it to the host's platform files.")
        }
    }

    @Test func theScanSeesEveryWayToImportDarwin() {
        #expect(ExtensionRulesTests.imports("@preconcurrency import Darwin\nimport Darwin.C\nimport struct Glibc.stat\nimport Foundation") == ["Darwin", "Glibc", "Foundation"])
        #expect(ExtensionRulesTests.lines("let a = getpid()\nlet b = ProcessInfo.processInfo.processIdentifier\nsysctlbyname(c)\n// getpid()", ExtensionRulesTests.darwinOnly) == [1, 3])
    }

    /// No extension guesses a home folder, nor a folder of the person's Library: its folders come from the environment
    /// or from the host. Strings are scanned too ("Library/"), comments not.
    @Test func anExtensionGuessesNoHome() throws {
        for file in try ExtensionRulesTests.files({ $0.hasPrefix("Agent") }) {
            let code = ToolchainTests.code(file.text)
            let guesses = ["NSHomeDirectory", "homeDirectoryForCurrentUser", "applicationSupportDirectory", "urls(for:"].filter(code.contains)
            let library = file.text.components(separatedBy: "\n").contains { $0.contains("Library/") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(guesses.isEmpty && !library, "Sources/\(file.name) guesses a folder of the person (\(guesses.joined(separator: ", "))\(library ? " Library/" : "")); take it from the environment the reader or the launch is given.")
        }
    }
}
