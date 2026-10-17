// What every agent something launches has in common: a program it owns, spoken to in JSON lines on its
// input and output, whose news is folded into one `Agent`. Each harness (Claude.swift, Codex.swift)
// says how to start it and how to read and answer it.
import Foundation

/// The person's answer to a permission request.
/// Only "once" or "deny": something never writes a lasting rule into an agent's settings.
public enum PermissionAnswer: Equatable, Sendable {
    case once
    case deny
}

open class AgentProcess {
    public private(set) var agent: Agent
    /// Called on a background queue after each change.
    public var onChange: ((Agent) -> Void)?
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var pending = Data()
    private let lock = NSLock()

    /// `removing` and `adding` change the person's environment for this program only.
    public init(agent: Agent, arguments: [String], removing: Set<String> = [], adding: [String: String] = [:]) {
        self.agent = agent
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: agent.folder)
        process.environment = ProcessInfo.processInfo.environment.filter { !removing.contains($0.key) }
            .merging(adding) { _, added in added }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    /// Starts the program. Throws a `BridgeError` when it cannot be started (not installed, for example).
    public func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.received(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let said = String(decoding: self.errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            self.update {
                $0.status = "stopped"
                $0.request = nil
                if process.terminationStatus == 127 {
                    // /usr/bin/env found no such program: say it in words a newcomer can act on.
                    $0.error = AgentProcess.notInstalled(self.program)
                } else if process.terminationStatus != 0 && $0.error == nil {
                    let line = said.split(separator: "\n").last.map(String.init)
                    $0.error = line ?? "The agent stopped (exit code \(process.terminationStatus))."
                }
            }
        }
        do {
            try process.run()
        } catch {
            throw BridgeError(AgentProcess.notInstalled(program))
        }
        started()
    }

    /// The program something runs for this agent ("claude", "codex", ...).
    public var program: String { process.arguments?.first ?? "the agent" }

    static func notInstalled(_ program: String) -> String {
        "`\(program)` is not installed, or something cannot find it in your PATH. Install it, then launch the agent again."
    }

    /// Sends a message from the person. Throws a `BridgeError` when the agent has stopped.
    open func send(_ text: String) throws {}

    /// Answers the permission request `id`. Throws a `BridgeError` when there is no such request any more.
    open func answer(_ id: String, _ answer: PermissionAnswer) throws {}

    /// Called once the program runs.
    open func started() {}

    /// Called for each JSON line the program writes.
    open func received(_ event: [String: Any]) {}

    public var isRunning: Bool { process.isRunning }

    /// Writes one JSON line on the program's input.
    public func write(_ object: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        input.fileHandleForWriting.write(data)
    }

    /// Changes what is known of the agent, then tells `onChange`.
    public func update(_ change: (inout Agent) -> Void) {
        lock.lock()
        change(&agent)
        let now = agent
        lock.unlock()
        onChange?(now)
    }

    private var asked: [String: Any] = [:]

    /// Keeps a permission request as the agent sent it, until the person answers.
    public func keep(_ request: Any, for id: String) {
        lock.lock()
        asked[id] = request
        lock.unlock()
    }

    /// The request kept for `id`, removed from the kept ones; nil when it was answered or withdrawn.
    public func take(_ id: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return asked.removeValue(forKey: id)
    }

    /// Asks the program to stop and waits for it, at most two seconds, so that quitting something
    /// leaves no agent running behind it.
    public func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(20_000) }
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pending.append(data)
        var lines: [Data] = []
        while let end = pending.firstIndex(of: 0x0A) {
            lines.append(pending[pending.startIndex..<end])
            pending.removeSubrange(pending.startIndex...end)
        }
        lock.unlock()
        for line in lines {
            if let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { received(event) }
        }
    }
}
