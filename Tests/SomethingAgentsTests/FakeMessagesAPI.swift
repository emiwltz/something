// A fake of Anthropic's Messages API, for the trials of Claude Code: the real `claude` program talks to it instead of a model. It
// listens on 127.0.0.1 on a port the system picks, answers POST /v1/messages as the API streams (server-sent events),
// and plays a tiny invented script chosen by keywords in the person's last message. It never reads, keeps or logs
// a request's headers (they carry the key): only the JSON body is read, and only the person's texts are kept.
// Tests/somethingTests/FakeMessagesAPI.swift is a link to this file, for the app's own trial (AssistantTrial).
import Darwin
import Foundation

final class FakeMessagesAPI {
    private(set) var port: UInt16 = 0
    private let socket: Int32
    private let lock = NSLock()
    private var texts: [String] = []
    private var efforts: [String?] = []
    private var results: [String] = []
    private var count = 0
    /// The tool calls a "run-build" message plays, one per request, in order; then a closing text. Set by the trial.
    var build: [(name: String, input: [String: Any])] = []
    /// When true, every message is refused with a 401, as the API refuses a key it does not know.
    var refusing: Bool {
        get { lock.withLock { refused } }
        set { lock.withLock { refused = newValue } }
    }
    private var refused = false
    /// How many messages are still answered 529 (overloaded), as the API answers when it is busy; Claude retries them.
    var overloading: Int {
        get { lock.withLock { overloaded } }
        set { lock.withLock { overloaded = newValue } }
    }
    private var overloaded = 0

    /// What the script answers to the person's last words; tools only on the trigger words, so nothing else runs.
    static func reply(to last: String, toolResult: String?) -> [[String: Any]] {
        if let toolResult { return [["type": "text", "text": "Invented summary: \(toolResult.prefix(40))"]] }
        let tool: (String, [String: Any])? =
            last.contains("run-sleep") ? ("Bash", ["command": "sleep 4 && touch slept.txt", "description": "Wait, then make a file"])
            : last.contains("run-echo") ? ("Bash", ["command": "touch invented.txt", "description": "Make a file"])
            : last.contains("ask-me") ? ("AskUserQuestion", ["questions": [["question": "Which colour for the invented button?", "header": "Colour",
                                                                            "options": [["label": "Blue", "description": "Calm"], ["label": "Green", "description": "Fresh"]],
                                                                            "multiSelect": false]]])
            : nil
        if let (name, input) = tool { return [["type": "text", "text": "Invented: one step first."], ["type": "tool_use", "name": name, "input": input]] }
        return [["type": "text", "text": "Invented reply number \(last.count % 7)."]]
    }

    init() throws {
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0   // the system picks a free port
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, size) == 0 && getsockname(socket, $0, &size) == 0 }
        }
        guard bound, listen(socket, 16) == 0 else { throw CocoaError(.fileWriteUnknown) }
        port = UInt16(bigEndian: address.sin_port)
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(socket, nil, nil)
                guard client >= 0 else { return }   // closed by stop()
                var one: Int32 = 1   // a client gone mid-answer must not kill the tests with SIGPIPE
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { [self] in serve(client) }
            }
        }
    }

    var url: String { "http://127.0.0.1:\(port)" }

    /// The person's texts, in the order the program sent them to the model (each request's last one).
    var received: [String] { lock.withLock { texts } }

    /// The tool results the program sent the model (their text is the invented script's, or an invented answer).
    var toolResults: [String] { lock.withLock { results } }

    /// The effort each request asked of the model, where the program put one.
    var effortsAsked: [String?] { lock.withLock { efforts } }

    func stop() { close(socket) }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var bodyStart: Int?
        var length = 0
        while true {
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { return }
            data.append(contentsOf: buffer[0..<n])
            if bodyStart == nil, let end = data.range(of: Data("\r\n\r\n".utf8)) {
                bodyStart = end.upperBound
                // Only the length is taken from the headers; nothing else of them is looked at.
                let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).lowercased()
                length = head.split(separator: "\r\n").first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
            }
            if let start = bodyStart, data.count - start >= length { break }
        }
        let firstLine = String(decoding: data.prefix(80), as: UTF8.self)
        let body = (try? JSONSerialization.jsonObject(with: data[bodyStart!...])) as? [String: Any] ?? [:]
        guard firstLine.hasPrefix("POST /v1/messages") && !firstLine.hasPrefix("POST /v1/messages/count_tokens") else {
            let answer = firstLine.hasPrefix("POST /v1/messages/count_tokens") ? #"{"input_tokens":12}"# : #"{"type":"error","error":{"type":"not_found_error","message":"Not in this fake."}}"#
            let status = firstLine.hasPrefix("POST /v1/messages/count_tokens") ? "200 OK" : "404 Not Found"
            return send(client, "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(answer.utf8.count)\r\nConnection: close\r\n\r\n\(answer)")
        }
        if refusing {
            let answer = #"{"type":"error","error":{"type":"authentication_error","message":"Invented: this key is not known."}}"#
            return send(client, "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: \(answer.utf8.count)\r\nConnection: close\r\n\r\n\(answer)")
        }
        if lock.withLock({ () -> Bool in overloaded -= 1; return overloaded >= 0 }) {
            let answer = #"{"type":"error","error":{"type":"overloaded_error","message":"Invented: overloaded."}}"#
            return send(client, "HTTP/1.1 529 Overloaded\r\nContent-Type: application/json\r\nContent-Length: \(answer.utf8.count)\r\nConnection: close\r\n\r\n\(answer)")
        }
        let (last, toolResult) = FakeMessagesAPI.lastWords(body)
        let blocks = lock.withLock { () -> [[String: Any]] in
            texts.append(last)
            efforts.append(FakeMessagesAPI.effort(body))
            if let toolResult { results.append(toolResult) }
            count += 1
            return building(body) ?? FakeMessagesAPI.reply(to: last, toolResult: toolResult)
        }
        let model = body["model"] as? String ?? "claude-example"
        if body["stream"] as? Bool != true {
            let message: [String: Any] = ["id": "msg_fake\(count)", "type": "message", "role": "assistant", "model": model,
                                          "content": blocks.map { $0["type"] as? String == "tool_use" ? $0.merging(["id": "toolu_fake\(count)"]) { a, _ in a } : $0 },
                                          "stop_reason": blocks.contains { $0["type"] as? String == "tool_use" } ? "tool_use" : "end_turn",
                                          "stop_sequence": NSNull(), "usage": ["input_tokens": 12, "output_tokens": 6]]
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: message), as: UTF8.self)
            return send(client, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)")
        }
        send(client, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
        event(client, "message_start", ["type": "message_start", "message": ["id": "msg_fake\(count)", "type": "message", "role": "assistant", "model": model,
                                                                             "content": [], "stop_reason": NSNull(), "stop_sequence": NSNull(),
                                                                             "usage": ["input_tokens": 12, "output_tokens": 1]]])
        for (index, block) in blocks.enumerated() {
            if block["type"] as? String == "tool_use" {
                event(client, "content_block_start", ["type": "content_block_start", "index": index,
                                                       "content_block": ["type": "tool_use", "id": "toolu_fake\(count)", "name": block["name"]!, "input": [String: Any]()]])
                let json = String(decoding: try! JSONSerialization.data(withJSONObject: block["input"]!), as: UTF8.self)
                event(client, "content_block_delta", ["type": "content_block_delta", "index": index, "delta": ["type": "input_json_delta", "partial_json": json]])
            } else {
                event(client, "content_block_start", ["type": "content_block_start", "index": index, "content_block": ["type": "text", "text": ""]])
                event(client, "content_block_delta", ["type": "content_block_delta", "index": index, "delta": ["type": "text_delta", "text": block["text"]!]])
            }
            event(client, "content_block_stop", ["type": "content_block_stop", "index": index])
        }
        let stop = blocks.contains { $0["type"] as? String == "tool_use" } ? "tool_use" : "end_turn"
        event(client, "message_delta", ["type": "message_delta", "delta": ["stop_reason": stop, "stop_sequence": NSNull()], "usage": ["output_tokens": 6]])
        event(client, "message_stop", ["type": "message_stop"])
    }

    /// The next step of `build` when the conversation is a "run-build" one: the step after the tool results so far.
    private func building(_ body: [String: Any]) -> [[String: Any]]? {
        let messages = body["messages"] as? [[String: Any]] ?? []
        let blocks = messages.filter { $0["role"] as? String == "user" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        let texts = messages.compactMap { $0["content"] as? String } + blocks.compactMap { $0["text"] as? String }
        guard !build.isEmpty, texts.contains(where: { $0.contains("run-build") }) else { return nil }
        let done = blocks.filter { $0["type"] as? String == "tool_result" }.count
        guard done < build.count else { return [["type": "text", "text": "Invented: the board is ready."]] }
        return [["type": "text", "text": "Invented: step \(done + 1)."], ["type": "tool_use", "name": build[done].name, "input": build[done].input]]
    }

    /// The person's last text in a request, and the text of a tool result when the last message carries one.
    static func lastWords(_ body: [String: Any]) -> (String, String?) {
        // The program may end the list with a message of its own (a "system" one carrying the effort).
        guard let last = (body["messages"] as? [[String: Any]])?.last(where: { $0["role"] as? String == "user" }) else { return ("", nil) }
        if let text = last["content"] as? String { return (text, nil) }
        let blocks = last["content"] as? [[String: Any]] ?? []
        let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        let result = blocks.first { $0["type"] as? String == "tool_result" }.map { block -> String in
            if let text = block["content"] as? String { return text }
            return (block["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return (texts.joined(separator: "\n"), result)
    }

    /// The effort in a request: in its output_config, or in that of its last message.
    static func effort(_ body: [String: Any]) -> String? {
        let messages = body["messages"] as? [[String: Any]] ?? []
        return ((body["output_config"] as? [String: Any])?["effort"] ?? (messages.last?["output_config"] as? [String: Any])?["effort"]) as? String
    }

    private func event(_ client: Int32, _ name: String, _ data: [String: Any]) {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: data), as: UTF8.self)
        send(client, "event: \(name)\ndata: \(json)\n\n")
    }

    private func send(_ client: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBufferPointer { write(client, $0.baseAddress! + done, bytes.count - done) }
            guard n > 0 else { return }
            done += n
        }
    }
}
