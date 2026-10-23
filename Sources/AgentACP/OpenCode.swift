// OpenCode: what something knows of it. It is driven over the Agent Client Protocol (ACPDriver, with the profile
// here) and read from its database (OpenCodeReader). What it does its own way is here too: the last model it used,
// and the claim a run leaves on a conversation in its database.
import Foundation
import SomethingAgents
import SomethingCore

extension AgentDescriptor {
    /// Modes (2.0.20): a mode is an agent; build and plan ask as the person's settings say, and only `--auto`, which
    /// something never passes, asks less. As a builder, it is lent something's commands over MCP.
    package static let opencode = AgentDescriptor(
        kind: "opencode", name: "OpenCode", install: "brew install opencode", homeFolders: [".opencode/bin"],
        asksAsMuch: ["build", "plan"], driving: ACPProfile.opencode.driving, reader: { OpenCodeReader(environment: $0) },
        builder: Builder(lent: LentTool.all), tools: ACPProfile.tools)
}

extension ACPProfile {
    /// `opencode acp`: each launch its own private server, holding one session in OpenCode's shared database. Its
    /// modes are its agents: build and plan come with it, and others the person wrote show in `options.mode` once
    /// OpenCode lists them. A sub-agent's updates carry a `_meta` key of its own, and its question tool cannot be
    /// shown over ACP (OpenCodeTrial.swift). From its code mode (`execute`) it calls other tools, MCP servers' among them.
    static let opencode = ACPProfile(
        kind: "opencode", name: "OpenCode", tested: "2.0.20", arguments: ["acp"], signIn: "opencode auth login",
        modes: [Option(value: "build", label: "Build"), Option(value: "plan", label: "Plan")], listsMoreModes: true,
        childKey: "opencode/child-session", questionTool: "question", notFoundWords: ["session not found", "does not belong to cwd"],
        innerCalls: { update in
            let calls = ((update["rawOutput"] as? [String: Any])?["metadata"] as? [String: Any])?["toolCalls"] as? [[String: Any]] ?? []
            return calls.map { ($0["tool"] as? String ?? "", $0["input"]) }
        },
        lastModel: { OpenCode.recentModel($0) },
        leftRunning: { session, environment in
            guard let database = OpenCode.database(environment), OpenCode.claimed(session, in: database) == true else { return nil }
            return OpenCode.claimLeft(session)
        })
}

/// OpenCode's own files, read only.
enum OpenCode {
    /// The sentence for a conversation OpenCode left marked as running.
    static func claimLeft(_ session: String) -> String {
        "OpenCode ended during a turn and left its conversation \(session) marked as running: the next time OpenCode's background service starts, it may continue that turn by itself. Open the conversation in OpenCode to finish or stop it."
    }

    /// OpenCode's last-used model, "provider/model", from `recent` in its state file model.json
    /// ($XDG_STATE_HOME/opencode, else ~/.local/state/opencode), the one its terminal app starts with; nil when the
    /// file or that key cannot be read. Over ACP OpenCode ignores it and picks a model of its own, maybe one of a
    /// provider the person never signed in to, so a new conversation that names no model takes this one instead.
    static func recentModel(_ environment: [String: String]) -> String? {
        guard let state = environment["XDG_STATE_HOME"].flatMap({ $0.hasPrefix("/") ? $0 : nil }) ?? environment["HOME"].map({ "\($0)/.local/state" }),
              let data = FileManager.default.contents(atPath: "\(state)/opencode/model.json"),
              let first = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["recent"] as? [Any],
              let last = first.first as? [String: Any],
              let provider = last["providerID"] as? String, let model = last["modelID"] as? String, !provider.isEmpty, !model.isEmpty else { return nil }
        return "\(provider)/\(model)"
    }

    /// Where OpenCode keeps its sessions for the environment it runs in: $OPENCODE_DB, else opencode.db in its data
    /// folder. A channel other than the default one names its own file, which something does not guess.
    static func database(_ environment: [String: String]) -> String? {
        if let path = environment["OPENCODE_DB"], path.hasPrefix("/") { return path }
        guard let data = environment["XDG_DATA_HOME"].flatMap({ $0.hasPrefix("/") ? $0 : nil }) ?? environment["HOME"].map({ "\($0)/.local/share" }) else { return nil }
        return "\(data)/opencode/opencode.db"
    }

    /// Whether OpenCode's database marks `session` as running (`time_suspended` set: the claim a run takes and
    /// releases at its end); nil when the database, its shape or the session cannot be read. Read only, never written.
    static func claimed(_ session: String, in path: String) -> Bool? {
        let whitelist: [String: Set<String>] = ["session_v2": ["id", "time_suspended"]]
        guard let db = try? SQLiteRO(path, whitelist: whitelist), (try? db.guarded()) == true,
              let row = (try? db.rows("SELECT time_suspended IS NOT NULL AS claimed FROM session_v2 WHERE id = ?", [session]))?.first else { return nil }
        return row["claimed"] as? Int64 == 1
    }
}
