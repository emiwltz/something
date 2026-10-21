// A fake of OpenAI's Responses API, for trial T-2, and of its Chat Completions API, for trials T-3 and T-4: the real
// `codex`, `opencode` and `pi` programs talk to it instead of a model, through a model provider declared in a throwaway home. It listens
// on 127.0.0.1 on a port the system picks, answers POST /v1/responses and POST /v1/chat/completions as the APIs stream
// (server-sent events, chunked), and plays a tiny invented script chosen by keywords in the person's last message. It never reads, keeps or logs a request's headers (they carry the key): only
// the length is taken from them, and only the JSON body is read.
import Darwin
import Foundation

final class FakeResponsesAPI {
    private(set) var port: UInt16 = 0
    private let socket: Int32
    private let lock = NSLock()
    private var texts: [String] = [], models: [String?] = [], efforts: [String?] = [], outputs: [String] = [], people: [Int] = []
    private var count = 0
    /// Whether the chat completions call pi's tool (`bash`) rather than OpenCode's.
    var pi = false
    /// The tool calls a "run-build" message plays, one per request, in order; then a closing text. Set by a trial.
    var build: [(name: String, arguments: [String: Any])] = []
    /// The command pi's run-wait tool call runs: a duration no other program uses, so a trial can tell it is gone.
    static let piWait = "sleep 30.25"

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
                var one: Int32 = 1   // a client gone mid-answer (a steer, an interrupt) must not kill the tests with SIGPIPE
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { [self] in serve(client) }
            }
        }
    }

    var url: String { "http://127.0.0.1:\(port)/v1" }
    /// The person's last text in each request, in order.
    var received: [String] { lock.withLock { texts } }
    /// The model and the reasoning effort each request named.
    var modelsAsked: [String?] { lock.withLock { models } }
    var effortsAsked: [String?] { lock.withLock { efforts } }
    /// How many of the person's messages each request carried: a continued conversation carries the earlier ones.
    var messagesSent: [Int] { lock.withLock { people } }
    /// The tool outputs the program sent back to the model.
    var toolOutputs: [String] { lock.withLock { outputs } }

    /// Shut down first: on Darwin a close alone does not wake the accept() blocked in the other thread.
    func stop() {
        shutdown(socket, SHUT_RDWR)
        close(socket)
    }

    /// One step of the script: a message (slow: one word every quarter second), or a tool call.
    enum Step { case message(String, slow: Bool), call(name: String, arguments: [String: Any]) }

    /// `opencode` picks OpenCode's names for its tools, `pi` pi's.
    static func reply(to last: String, toolOutput: String?, opencode: Bool = false, pi: Bool = false) -> Step {
        if let toolOutput { return .message("Invented summary: \(toolOutput.prefix(40))", slow: false) }
        if last.contains("run-sleep") { return .message(Array(repeating: "tick", count: 40).joined(separator: " "), slow: true) }
        if pi, last.contains("run-echo") { return .call(name: "bash", arguments: ["command": "touch invented.txt"]) }
        if pi, last.contains("run-wait") { return .call(name: "bash", arguments: ["command": FakeResponsesAPI.piWait]) }
        if opencode, last.contains("run-echo") {
            return .call(name: "shell", arguments: ["command": "touch invented.txt", "description": "Invented: make a file"])
        }
        if opencode, last.contains("ask-me") {
            return .call(name: "question", arguments: ["questions": [["header": "Colour", "question": "Which colour for the invented button?",
                                                                      "options": [["label": "Blue", "description": "Calm"], ["label": "Green", "description": "Fresh"]]]]])
        }
        if last.contains("run-echo") {
            return .call(name: "exec_command", arguments: ["cmd": "touch invented.txt", "sandbox_permissions": "require_escalated",
                                                           "justification": "Invented: make a file"])
        }
        if last.contains("ask-me") {
            return .call(name: "request_user_input", arguments: ["questions": [["id": "colour", "header": "Colour", "question": "Which colour for the invented button?",
                                                                                "options": [["label": "Blue", "description": "Calm"], ["label": "Green", "description": "Fresh"]]]]])
        }
        if last.contains("need-more") {
            return .call(name: "request_permissions", arguments: ["permissions": ["network": ["enabled": true]], "reason": "Invented: reach example.com"])
        }
        return .message("Invented reply number \(last.count % 7).", slow: false)
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var data = Data()
        // Codex keeps the connection open between requests.
        while let (head, body) = FakeResponsesAPI.nextRequest(client, &data) {
            guard head.hasPrefix("POST ") else {
                guard send(client, FakeResponsesAPI.plain(#"{"models":[]}"#)) else { return }
                continue
            }
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            guard head.contains("/chat/completions") else {
                let (last, output) = FakeResponsesAPI.lastWords(json)
                let step = lock.withLock { () -> Step in
                    texts.append(last)
                    models.append(json["model"] as? String)
                    efforts.append((json["reasoning"] as? [String: Any])?["effort"] as? String)
                    if let output { outputs.append(output) }
                    people.append((json["input"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "message" && $0["role"] as? String == "user" }.count)
                    count += 1
                    return building(json) ?? FakeResponsesAPI.reply(to: last, toolOutput: output)
                }
                guard stream(client, step, number: lock.withLock { count }) else { return }
                continue
            }
            // OpenCode asks for a title with a request that offers no tool: it is answered, never counted.
            guard json["tools"] != nil else {
                guard streamChat(client, .message("Invented title", slow: false), number: 0) else { return }
                continue
            }
            let messages = json["messages"] as? [[String: Any]] ?? []
            let last = FakeResponsesAPI.text(messages.last { $0["role"] as? String == "user" }?["content"])
            let output = messages.last?["role"] as? String == "tool" ? FakeResponsesAPI.text(messages.last?["content"]) : nil
            let step = lock.withLock { () -> Step in
                texts.append(last)
                models.append(json["model"] as? String)
                efforts.append(json["reasoning_effort"] as? String)
                if let output { outputs.append(output) }
                people.append(messages.filter { $0["role"] as? String == "user" }.count)
                count += 1
                return FakeResponsesAPI.reply(to: last, toolOutput: output, opencode: !pi, pi: pi)
            }
            guard streamChat(client, step, number: lock.withLock { count }) else { return }
        }
    }

    /// Streams one response; false once the program hung up.
    private func stream(_ client: Int32, _ step: Step, number: Int) -> Bool {
        guard send(client, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n") else { return false }
        let id = "resp_fake\(number)"
        var events: [[String: Any]] = [["type": "response.created", "response": ["id": id, "status": "in_progress"]]]
        var slow = false
        switch step {
        case .message(let text, let isSlow):
            slow = isSlow
            let item = "msg_fake\(number)"
            events.append(["type": "response.output_item.added", "output_index": 0, "item": ["type": "message", "id": item, "role": "assistant", "content": []]])
            let words = text.split(separator: " ")
            for (index, word) in words.enumerated() {
                events.append(["type": "response.output_text.delta", "item_id": item, "output_index": 0, "content_index": 0,
                               "delta": word + (index < words.count - 1 ? " " : "")])
            }
            events.append(["type": "response.output_item.done", "output_index": 0,
                           "item": ["type": "message", "id": item, "role": "assistant", "content": [["type": "output_text", "text": text]]]])
        case .call(let name, let arguments):
            let arguments = String(decoding: try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), as: UTF8.self)
            events.append(["type": "response.output_item.done", "output_index": 0,
                           "item": ["type": "function_call", "id": "fc_fake\(number)", "call_id": "call_fake\(number)", "name": name, "arguments": arguments]])
        }
        events.append(["type": "response.completed", "response": ["id": id, "status": "completed", "output": [],
                                                                  "usage": ["input_tokens": 10, "input_tokens_details": ["cached_tokens": 0], "output_tokens": 5,
                                                                            "output_tokens_details": ["reasoning_tokens": 0], "total_tokens": 15]]])
        for event in events {
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: event), as: UTF8.self)
            let chunk = "event: \(event["type"]!)\ndata: \(json)\n\n"
            guard send(client, "\(String(chunk.utf8.count, radix: 16))\r\n\(chunk)\r\n") else { return false }
            if slow && event["type"] as? String == "response.output_text.delta" { usleep(250_000) }
        }
        return send(client, "0\r\n\r\n")
    }

    /// Streams one chat completion, as OpenAI-compatible providers do; false once the program hung up.
    private func streamChat(_ client: Int32, _ step: Step, number: Int) -> Bool {
        guard send(client, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n") else { return false }
        let base: [String: Any] = ["id": "chatcmpl-fake\(number)", "object": "chat.completion.chunk", "created": 1_792_272_400, "model": "fake"]
        func choice(_ delta: [String: Any], _ finish: String?) -> [String: Any] {
            base.merging(["choices": [["index": 0, "delta": delta, "finish_reason": finish.map { $0 as Any } ?? NSNull()]]]) { _, new in new }
        }
        var chunks: [(event: [String: Any], pause: Bool)] = []
        let finish: String
        switch step {
        case .message(let text, let slow):
            let words = text.split(separator: " ")
            for (index, word) in words.enumerated() {
                chunks.append((choice(["role": "assistant", "content": word + (index < words.count - 1 ? " " : "")], nil), slow))
            }
            finish = "stop"
        case .call(let name, let arguments):
            let arguments = String(decoding: try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), as: UTF8.self)
            chunks.append((choice(["role": "assistant", "tool_calls": [["index": 0, "id": "call_fake\(number)", "type": "function",
                                                                       "function": ["name": name, "arguments": arguments]]]], nil), false))
            finish = "tool_calls"
        }
        var last = choice([:], finish)
        last["usage"] = ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]
        chunks.append((last, false))
        for (event, pause) in chunks {
            let chunk = "data: \(String(decoding: try! JSONSerialization.data(withJSONObject: event), as: UTF8.self))\n\n"
            guard send(client, "\(String(chunk.utf8.count, radix: 16))\r\n\(chunk)\r\n") else { return false }
            if pause { usleep(250_000) }
        }
        let done = "data: [DONE]\n\n"
        return send(client, "\(String(done.utf8.count, radix: 16))\r\n\(done)\r\n0\r\n\r\n")
    }

    /// The next step of `build` when the conversation is a "run-build" one: the step after the tool outputs so far.
    private func building(_ body: [String: Any]) -> Step? {
        let input = body["input"] as? [[String: Any]] ?? []
        let texts = input.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }
        guard !build.isEmpty, texts.contains(where: { $0.contains("run-build") }) else { return nil }
        let done = input.filter { $0["type"] as? String == "function_call_output" }.count
        return done < build.count ? .call(name: build[done].name, arguments: build[done].arguments) : .message("Invented: the board is ready.", slow: false)
    }

    /// A chat message's text: a string, or the text parts of a list.
    static func text(_ content: Any?) -> String {
        if let text = content as? String { return text }
        return (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    /// The next request on the connection: its request line and its body; nil once the program closed it.
    private static func nextRequest(_ client: Int32, _ data: inout Data) -> (String, Data)? {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let end = data.range(of: Data("\r\n\r\n".utf8)) {
                // Only the length is taken from the headers; nothing else of them is looked at.
                let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
                let length = head.lowercased().split(separator: "\r\n").first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                if data.count - end.upperBound >= length {
                    let body = data.subdata(in: end.upperBound..<end.upperBound + length)
                    data = data.subdata(in: end.upperBound + length..<data.count)
                    return (String(head.prefix { $0 != "\r" }), body)   // the request line alone
                }
            }
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { return nil }
            data.append(contentsOf: buffer[0..<n])
        }
    }

    /// The person's last text in a request, and the output of a tool when the request ends with one.
    static func lastWords(_ body: [String: Any]) -> (String, String?) {
        let input = body["input"] as? [[String: Any]] ?? []
        let last = input.last { $0["type"] as? String == "message" && $0["role"] as? String == "user" }
        let text = (last?["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "input_text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard let final = input.last, ["function_call_output", "custom_tool_call_output"].contains(final["type"] as? String ?? "") else { return (text, nil) }
        let output = final["output"] as? String ?? (final["output"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (text, output)
    }

    static func plain(_ json: String) -> String {
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
    }

    private func send(_ client: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBufferPointer { write(client, $0.baseAddress! + done, bytes.count - done) }
            guard n > 0 else { return false }
            done += n
        }
        return true
    }
}
