// Join: one program something launches, joined to its driver. Its lines reach the driver on the main queue, the
// driver's lines reach its input, and its end reaches the agent; for Claude's plan B, its permission spool too. The
// engine joins each launch here, and the trials join theirs the same way.
import Foundation
import SomethingCore

extension Engine {
    /// Starts `spawn` for one launch of `driving`'s kind and joins it to its driver: lines and the end come back on the
    /// main queue. `asked` says, on the main queue, whether something asked this agent to stop; `record` sees every
    /// line, in (true) and out (false), for `something try --record`. Throws as Spawn.start does, and AGENT_STOPPED
    /// when the program closed its input at once.
    /// With `spool`, Claude's plan B: the spool starts before the program and stops after its end.
    static func start(_ driving: Driving, _ launch: Launch, _ spawn: Spawn, spool: PermissionSpool? = nil, asked: @escaping (String) -> Bool,
                      record: ((_ written: Bool, _ line: Data) -> Void)? = nil) throws -> Launched {
        let agent = Launched(driving, launch, write: { [weak spawn] line in
            guard let spawn else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
            try spawn.write(line)
            record?(true, line)
        }, now: Engine.now)
        let program = ProcessHandle(environment: spawn.environment, write: { [weak spawn] line in
            guard let spawn, (try? spawn.write(line)) != nil else { return false }
            record?(true, line)
            return true
        }, running: { [weak spawn] in spawn?.running == true }, quit: { [weak spawn] in spawn?.closeInput() },
           interrupt: { [weak agent] in DispatchQueue.main.async { _ = try? agent?.interrupt() } })
        try agent.driver.join(program)
        spawn.graceful = { agent.driver.graceful(program) }
        if let spool {
            do { try spool.start() } catch { throw CodedError("LAUNCH_FAILED", "\(error)") }
            let claude = agent.driver as? ClaudeDriver
            claude?.hookReply = { [weak spool] uuid, decision in spool?.answer(uuid, decision) ?? .gone }
            spool.asked = { [weak claude] uuid, request in claude?.hookAsked(uuid, request) }
            spool.withdrawn = { [weak claude] uuid in claude?.hookWithdrawn(uuid) }
        }
        do { try startSpawn(launch, spawn, spool: spool, agent: agent, asked: asked, record: record) } catch {
            spool?.stop()
            throw error
        }
        return agent
    }

    private static func startSpawn(_ launch: Launch, _ spawn: Spawn, spool: PermissionSpool?, agent: Launched,
                                   asked: @escaping (String) -> Bool, record: ((Bool, Data) -> Void)?) throws {
        try spawn.start(lines: { line in DispatchQueue.main.async { record?(false, line); agent.driver.receive(line) } },
                        ended: { [weak spawn] code in
                            let errors = spawn?.errorTail ?? ""
                            spool?.stop()
                            DispatchQueue.main.async {
                                agent.ended(code: code, errors: errors, asked: asked(launch.agent))
                            }
                        })
        try agent.begin(pid: Int(spawn.pid))
    }
}
