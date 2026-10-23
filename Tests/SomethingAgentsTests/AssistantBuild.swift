// The standard build of a space by the person's assistant, for the trials of the builders: the tool
// sequence a real agent runs to make "Who is waiting for me" from a template, in each builder's tools (its shell, or
// the tools something serves over MCP), and an invented `something` program that
// answers that sequence's commands in the real one's shape, with invented text.
// Tests/somethingTests/AssistantBuild.swift is a link to this file, for the app's own trial (AssistantTrial).
import Darwin
import Foundation

enum AssistantBuild {
    /// An invented `something`: `new` writes a page with three lines to edit, the others answer in a word.
    static let program = #"""
    #!/bin/sh
    case "$1" in
      guide) echo "Invented guide: a space is one HTML file in this folder." ;;
      new) printf '%s\n' '<!doctype html>' '<script type="application/json" id="something">{"contract": 1, "title": "Invented board", "rights": ["state", "send"]}</script>' \
             '<p>One</p>' '<p>Two</p>' '<p>Three</p>' > "$2.html" && echo "Made $2.html from the template $4." ;;
      check) echo "$2: no problems." ;;
      open) echo "Opened $2." ;;
      *) echo "Invented: no command $1." >&2; exit 2 ;;
    esac
    """#

    /// This clone's own program, built by `swift build`: the one `swift test` runs beside.
    static let clonesProgram = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/something")
    /// The build identity (LC_UUID) every placed copy carries. WebKit names the folders it leaves in $TMPDIR, which
    /// cannot be deleted, after the program's name and LC_UUID, not its path (com.apple.WebKit.GPU+something-55554944<uuid>):
    /// with this one, they are made once per machine instead of once per build. Invented.
    static let fixedUUID = UUID(uuidString: "00000000-0000-4000-8000-0000736F6D65")!

    /// Copies this clone's program to a folder of its own in $TMPDIR, stamped with `fixedUUID`, and returns the copy:
    /// trials that run at once each have theirs, and share WebKit's folders. Beside it, a link to this
    /// clone's share/ and an empty Package.swift, which is how the program finds its share/ outside the .app
    /// (Resources.share). `removeProgram` removes it.
    static func placeProgram() throws -> URL {
        let folder = FileManager.default.scratch("something-test-program-")
        let program = folder.appendingPathComponent("something")
        let clone = clonesProgram.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: clonesProgram, to: program)
            try stamp(program)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("share"), withDestinationURL: clone.appendingPathComponent("share"))
            try Data().write(to: folder.appendingPathComponent("Package.swift"))
        } catch {
            removeProgram(program)
            throw error
        }
        return program
    }

    /// Writes `fixedUUID` into the LC_UUID of the thin 64-bit Mach-O program at `file`, then signs it again ad hoc,
    /// since its signature covered the old bytes. Throws when the file has no LC_UUID or codesign fails.
    static func stamp(_ file: URL) throws {
        var data = try Data(contentsOf: file)
        guard let range = uuidRange(in: data) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path]) }
        withUnsafeBytes(of: fixedUUID.uuid) { data.replaceSubrange(range, with: $0) }
        try data.write(to: file)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", file.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path]) }
    }

    /// Where the 16 bytes of LC_UUID are in a thin 64-bit Mach-O; nil when `data` is not one or has none.
    static func uuidRange(in data: Data) -> Range<Int>? {
        func word(_ offset: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) } }
        guard data.count >= 32, word(0) == 0xfeed_facf else { return nil }
        var offset = 32  // after mach_header_64
        for _ in 0..<word(16) {  // ncmds
            guard offset + 24 <= data.count else { return nil }
            if word(offset) == 0x1b { return offset + 8 ..< offset + 24 }  // LC_UUID: cmd, cmdsize, then the 16 bytes
            offset += Int(word(offset + 4))
        }
        return nil
    }

    /// Removes the copy `placeProgram` made, and the picture a check of the build outside a spaces folder left in the
    /// person's temporary folder.
    static func removeProgram(_ program: URL) {
        try? FileManager.default.removeItem(at: program.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("something-check/agents-board.png"))
    }

    /// Writes the invented program as <root>/tools/something and returns that folder's path.
    static func tools(in root: URL) throws -> String {
        let folder = root.appendingPathComponent("tools"), file = folder.appendingPathComponent("something")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try program.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return folder.path
    }

    /// The commands of the build, in order: read the guide, look, copy the template, (read and edit the page three
    /// times), check three times, then once without each of two rights.
    static let commands = ["something guide --print", "ls", "something new agents-board --from agents"]
    static let checks = ["something check agents-board", "something check agents-board", "something check agents-board",
                         "something check agents-board --refuse send", "something check agents-board --refuse state"]
    static let edits = [("<p>One</p>", "<p>Invented one</p>"), ("<p>Two</p>", "<p>Invented two</p>"), ("<p>Three</p>", "<p>Invented three</p>")]

    /// The build in Claude Code's tools, for an agent working in `folder`.
    static func steps(_ folder: String) -> [(name: String, input: [String: Any])] {
        let page = folder + "/agents-board.html"
        func bash(_ command: String) -> (name: String, input: [String: Any]) { ("Bash", ["command": command, "description": "Invented step"]) }
        return commands.map(bash) + [("Read", ["file_path": page])]
            + edits.map { ("Edit", ["file_path": page, "old_string": $0.0, "new_string": $0.1]) } + checks.map(bash)
    }

    /// The build in Codex's tools, lent something's over MCP (Codex calls them by their name in the namespace
    /// mcp__something): exec_command, where the page is read with `cat`, written with a heredoc and changed with
    /// `apply_patch`, as Codex's own models do when no patch tool is offered (the fake model is offered none).
    static func codexSteps() -> [(name: String, arguments: [String: Any])] {
        func shell(_ command: String) -> (name: String, arguments: [String: Any]) { ("exec_command", ["cmd": command]) }
        func lent(_ tool: String, _ arguments: [String: Any]) -> (name: String, arguments: [String: Any]) { ("mcp__something." + tool, arguments) }
        let patches = edits.map { "apply_patch <<'PATCH'\n*** Begin Patch\n*** Update File: agents-board.html\n@@\n-\($0.0)\n+\($0.1)\n*** End Patch\nPATCH" }
        return [lent("something_guide", [:]), shell("ls"), lent("something_new", ["name": "agents-board", "from": "agents"]), shell("cat agents-board.html"),
                shell("cat > agents-board.html <<'PAGE'\n\(page)PAGE")] + patches.map(shell) + checked.map { lent("something_check", $0) }
    }

    /// The arguments of something_check for each of `checks`.
    static var checked: [[String: Any]] {
        checks.map { check in
            let refuse = check.components(separatedBy: " --refuse ").dropFirst().map { $0 }
            return refuse.isEmpty ? ["name": "agents-board"] : ["name": "agents-board", "refuse": refuse]
        }
    }

    /// The page the invented `new` writes, which the builds through the tools something serves over MCP write over
    /// the real template's copy.
    static let page = "<!doctype html>\n<script type=\"application/json\" id=\"something\">{\"contract\": 1, \"title\": \"Invented board\", \"rights\": [\"state\", \"send\"]}</script>\n<p>One</p>\n<p>Two</p>\n<p>Three</p>\n"

    /// The build of an agent lent something's tools over MCP (Lent.swift, MCP.swift), which this clone's real program
    /// runs: the guide, a look, `new` from the real template, a read of the copy, the invented page written over it, the
    /// three edits, then the five checks. In Claude Code's tools, where a lent tool is mcp__something__<name>; or with
    /// `opencode` in OpenCode's (2.0), where a tool of an MCP server is called from its code mode, `execute`.
    static func lentSteps(_ folder: String, opencode: Bool = false) -> [(name: String, input: [String: Any])] {
        let file = folder + "/agents-board.html"
        let (path, old, new) = opencode ? ("path", "oldString", "newString") : ("file_path", "old_string", "new_string")
        let names = opencode ? ["shell", "read", "write", "edit"] : ["Bash", "Read", "Write", "Edit"]
        func lent(_ tool: String, _ input: [String: Any]) -> (name: String, input: [String: Any]) {
            let object = String(decoding: (try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self)
            return opencode ? ("execute", ["code": "return await tools.something.\(tool)(\(object))"]) : ("mcp__something__" + tool, input)
        }
        return [lent("something_guide", [:]), (names[0], ["command": "ls", "description": "Invented step"]),
                lent("something_new", ["name": "agents-board", "from": "agents"]), (names[1], [path: file]), (names[2], [path: file, "content": page])]
            + edits.map { (names[3], [path: file, old: $0.0, new: $0.1]) } + checked.map { lent("something_check", $0) }
    }

    /// The build in pi's tools, for an agent working in `folder`: something's commands in its shell (pi is lent
    /// nothing: it runs commands without asking anyway), the page read, written, then edited three times.
    static func piSteps(_ folder: String) -> [(name: String, arguments: [String: Any])] {
        let file = folder + "/agents-board.html"
        func bash(_ command: String) -> (name: String, arguments: [String: Any]) { ("bash", ["command": command]) }
        return commands.map(bash) + [("read", ["path": file]), ("write", ["path": file, "content": page])]
            + edits.map { ("edit", ["path": file, "edits": [["oldText": $0.0, "newText": $0.1]]]) } + checks.map(bash)
    }

    /// `url` with its links resolved, /private included (Foundation's own resolving drops it).
    static func real(_ url: URL) -> URL {
        guard let path = realpath(url.path, nil) else { return url }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
}
