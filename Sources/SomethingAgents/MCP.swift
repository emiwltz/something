// MCP: `something mcp`, the tools something lends (Lent.swift) served over the Model Context Protocol, one JSON-RPC
// message per line on standard input and output. An agent that takes MCP servers at launch starts it itself (Claude
// Code through --mcp-config, an ACP agent through session/new), as a program of its own, outside the sandbox of its
// commands. It serves only tools: initialize, ping, tools/list and tools/call, each call run as Lent runs it, with the
// same argument checks, one at a time.
import Foundation

extension Lent {
    /// Serves LentTool.all, run by `program` in `environment`, until the agent closes standard input.
    public static func serve(program: String, environment: [String: String], version: String) {
        let lent = Lent(tools: LentTool.all, run: Lent.program(program, environment: environment), refused: { _, _ in }, hop: { $0(); $1() })
        while let line = readLine() {
            if let answer = lent.answer(Data(line.utf8), version: version) { FileHandle.standardOutput.write(answer + Data("\n".utf8)) }
        }
    }

    /// The line that answers the agent's line `line`; nil for a notification, or a response, which ask for none. A
    /// call's tool runs before this returns: `hop` must run its work at once (`serve`'s does).
    package func answer(_ line: Data, version: String) -> Data? {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return Lent.frame(["id": NSNull(), "error": ["code": -32700, "message": "something's MCP server reads one JSON object per line."]])
        }
        guard let id = message["id"], let method = message["method"] as? String else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            // The client's version is answered as it gave it: what tools use is the same in every version so far.
            return Lent.frame(["id": id, "result": ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                                                    "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "something", "version": version]]])
        case "ping": return Lent.frame(["id": id, "result": [String: Any]()])
        case "tools/list":
            return Lent.frame(["id": id, "result": ["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }]])
        case "tools/call":
            var reply = Reply(ok: false, text: "something did not run \(params["name"] as? String ?? "the tool").")
            call(params["name"] as? String ?? "", params["arguments"]) { reply = $0 }
            return Lent.frame(["id": id, "result": ["content": [["type": "text", "text": reply.text]], "isError": !reply.ok]])
        default:
            return Lent.frame(["id": id, "error": ["code": -32601, "message": "something's MCP server does not handle \(method)."]])
        }
    }

    private static func frame(_ object: [String: Any]) -> Data { Data(json(object.merging(["jsonrpc": "2.0"]) { old, _ in old }).utf8) }
}
