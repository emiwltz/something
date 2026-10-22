// MCP.swift: something's MCP server, line by line, with an invented program in place of something's own: what it
// answers to the few methods it serves, and that a call goes through the same checks as every lent tool.
import Foundation
import Testing
@testable import SomethingAgents

@Suite struct MCPTests {
    /// A Lent of every tool whose commands answer at once with their words, and the words each call ran.
    final class Ran: @unchecked Sendable { var words: [[String]] = [] }

    static func server(_ ran: Ran, ok: Bool = true) -> Lent {
        Lent(tools: LentTool.all, run: { words in
            ran.words.append(words)
            return Lent.Reply(ok: ok, text: "Invented: " + words.joined(separator: " "))
        }, refused: { _, _ in }, hop: { $0(); $1() })
    }

    static func answer(_ lent: Lent, _ message: [String: Any]) -> [String: Any]? {
        let line = try! JSONSerialization.data(withJSONObject: message)
        return lent.answer(line, version: "9.9.9").map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    }

    @Test func itServesTheToolsAndNothingElse() throws {
        let ran = Ran(), lent = Self.server(ran)
        let started = try #require(Self.answer(lent, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                      "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "invented"]]]))
        #expect(started["jsonrpc"] as? String == "2.0" && started["id"] as? Int == 1)
        let result = try #require(started["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26", "the client's own version")
        #expect(result["serverInfo"] as? [String: String] == ["name": "something", "version": "9.9.9"])
        #expect((result["capabilities"] as? [String: Any])?.keys.sorted() == ["tools"])
        #expect(Self.answer(lent, ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil, "a notification gets no answer")
        #expect(Self.answer(lent, ["jsonrpc": "2.0", "id": "p", "method": "ping"])?["result"] as? [String: Any] != nil)
        let listed = try #require((Self.answer(lent, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(listed.map { $0["name"] as? String } == ["something_guide", "something_new", "something_check"])
        #expect(listed.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" && $0["description"] is String })
        let other = try #require(Self.answer(lent, ["jsonrpc": "2.0", "id": 3, "method": "resources/list"])?["error"] as? [String: Any])
        #expect(other["code"] as? Int == -32601)
        let garbage = try #require(lent.answer(Data("not json".utf8), version: "9.9.9"))
        #expect(((try JSONSerialization.jsonObject(with: garbage)) as? [String: Any])?["error"] != nil)
        #expect(ran.words.isEmpty, "nothing ran")
    }

    /// A call runs the command its arguments make, and its reply is the content; wrong arguments and unknown tools run
    /// nothing and are errors; a command that failed is one too.
    @Test func aCallRunsTheLentCommand() throws {
        let ran = Ran(), lent = Self.server(ran)
        func call(_ name: String, _ arguments: [String: Any], in lent: Lent? = nil) throws -> (text: String, error: Bool) {
            let result = try #require(Self.answer(lent ?? Self.server(ran), ["jsonrpc": "2.0", "id": 7, "method": "tools/call",
                                                                             "params": ["name": name, "arguments": arguments]])?["result"] as? [String: Any])
            let content = try #require(result["content"] as? [[String: Any]])
            #expect(content.count == 1 && content[0]["type"] as? String == "text")
            return (content[0]["text"] as? String ?? "", result["isError"] as? Bool ?? true)
        }
        #expect(try call("something_guide", [:], in: lent) == ("Invented: guide --print", false))
        #expect(try call("something_new", ["name": "board", "from": "agents"], in: lent) == ("Invented: new board --from agents", false))
        #expect(try call("something_new", ["name": "board"], in: lent) == ("Invented: new board", false))
        #expect(try call("something_check", ["name": "board", "refuse": ["send"]], in: lent) == ("Invented: check board --refuse send", false))
        #expect(ran.words == [["guide", "--print"], ["new", "board", "--from", "agents"], ["new", "board"], ["check", "board", "--refuse", "send"]])
        for (name, arguments) in [("something_new", ["name": "../board"]), ("something_new", ["name": "board", "from": "--folder"]), ("something_new", ["name": "-x"]), ("something_check", ["name": "--json"]),
                                  ("something_new", ["name": "board", "from": 3]), ("something_check", ["name": "board", "refuse": ["--state"]]),
                                  ("something_open", ["name": "board"])] as [(String, [String: Any])] {
            #expect(try call(name, arguments, in: lent).error, "\(name) \(arguments)")
        }
        #expect(ran.words.count == 4, "nothing more ran")
        #expect(try call("something_new", ["name": "board"], in: Self.server(ran, ok: false)).error, "a command that failed")
    }

    /// The name an agent gives a lent tool: its own, or as a tool of the MCP server "something" in Claude Code and in
    /// OpenCode (a tool, or from its code mode); the command something runs for its arguments, nil when they are wrong.
    @Test func aLentToolIsKnownByEachAgentsName() {
        for name in ["something_check", "mcp__something__something_check", "something_something_check", "something.something_check"] {
            #expect(Lent.called(name, ["name": "board"])?.name == "something_check", "\(name)")
            #expect(Lent.called(name, ["name": "board"])?.command == "something check board", "\(name)")
        }
        #expect(Lent.called("something_new", ["name": "board", "from": "pet"])?.command == "something new board --from pet")
        #expect(Lent.called("mcp__something__something_guide", nil)?.command == "something guide --print")
        #expect(Lent.called("something_check", ["name": "/tmp/board"])?.name == "something_check")
        #expect(Lent.called("something_check", ["name": "/tmp/board"])?.command == nil)
        for name in ["something_open", "mcp__other__something_check", "Bash", "check"] { #expect(Lent.called(name, ["name": "board"]) == nil, "\(name)") }
    }
}
