// The standard build of a space by the person's assistant (plan A.2 #6), for the trials of Claude Code and Codex: the
// tool sequence a real agent runs to make "Who is waiting for me" from a template, and an invented `something`
// program that answers that sequence's commands in the real one's shape, with invented text.
// Tests/somethingTests/AssistantBuild.swift is a link to this file, for the app's own trial (AssistantTrial).
import Darwin
import Foundation

enum AssistantBuild {
    /// An invented `something`: `new` writes a page with three lines to edit, the others answer in a word. `check`
    /// runs the real program instead when SOMETHING_TRIAL_PROGRAM names it (Codex's trial, to see it in the sandbox).
    static let program = #"""
    #!/bin/sh
    case "$1" in
      guide) echo "Invented guide: a space is one HTML file in this folder." ;;
      new) printf '%s\n' '<!doctype html>' '<script type="application/json" id="something">{"contract": 1, "title": "Invented board", "rights": ["state", "send"]}</script>' \
             '<p>One</p>' '<p>Two</p>' '<p>Three</p>' > "$2.html" && echo "Made $2.html from the template $4." ;;
      check) if [ -n "$SOMETHING_TRIAL_PROGRAM" ]; then exec "$SOMETHING_TRIAL_PROGRAM" "$@"; fi; echo "$2: no problems." ;;
      open) echo "Opened $2." ;;
      *) echo "Invented: no command $1." >&2; exit 2 ;;
    esac
    """#

    /// This clone's own program, built by `swift build`: the one `swift test` runs beside.
    static let clonesProgram = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/debug/something")
    /// Where a test runs the real program from (plan A.4): WebKit keeps a folder per program path that cannot be
    /// deleted, so every clone uses this one path, and its folder is made once per machine.
    static let fixedProgram = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("something-test-program/something")

    /// Copies this clone's program to `fixedProgram` and returns that path. Beside it, a link to this clone's share/
    /// and an empty Package.swift, which is how the program finds its share/ outside the .app (Resources.share).
    static func placeProgram() throws -> String {
        removeProgram()
        let folder = fixedProgram.deletingLastPathComponent(), clone = clonesProgram.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: clonesProgram, to: fixedProgram)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("share"), withDestinationURL: clone.appendingPathComponent("share"))
        try Data().write(to: folder.appendingPathComponent("Package.swift"))
        return fixedProgram.path
    }

    /// Removes the copy and the picture its `check` of the build left in the person's temporary folder.
    static func removeProgram() {
        try? FileManager.default.removeItem(at: fixedProgram.deletingLastPathComponent())
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

    /// The build in Codex's tools: exec_command, where the page is read with `cat` and changed with `apply_patch`, as
    /// Codex's own models do when no patch tool is offered (the fake model is offered none); and the check something
    /// lends it, something_check, since `something check` cannot load a page in Codex's sandbox. `something` is called
    /// by its path in `tools`: Codex runs each command in a login shell, whose PATH puts the system's folders first,
    /// where an installed something may be. Codex asks by sandbox, not by command, so the path changes nothing it decides.
    static func codexSteps(tools: String) -> [(name: String, arguments: [String: Any])] {
        let patches = edits.map { "apply_patch <<'PATCH'\n*** Begin Patch\n*** Update File: agents-board.html\n@@\n-\($0.0)\n+\($0.1)\n*** End Patch\nPATCH" }
        let named = (commands + ["cat agents-board.html"] + patches).map { $0.hasPrefix("something ") ? tools + "/" + $0 : $0 }
        let lent = checks.map { check -> [String: Any] in
            let refuse = check.components(separatedBy: " --refuse ").dropFirst().map { $0 }
            return refuse.isEmpty ? ["name": "agents-board"] : ["name": "agents-board", "refuse": refuse]
        }
        return named.map { ("exec_command", ["cmd": $0]) } + lent.map { ("something_check", $0) }
    }

    /// How many tools the build runs.
    static var count: Int { steps("/").count }

    /// `url` with its links resolved, /private included (Foundation's own resolving drops it).
    static func real(_ url: URL) -> URL {
        guard let path = realpath(url.path, nil) else { return url }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
}
