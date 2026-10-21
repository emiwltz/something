// Join: one program something launches, joined to its driver. Its lines reach the driver on the main queue, the
// driver's lines reach its input, and its end reaches the agent; for Claude's plan B, its permission spool too. The
// engine joins each launch here, and the trials join theirs the same way.
import Foundation
import SomethingCore

extension Engine {
    /// Starts `spawn` for one launch and joins it to its driver: lines and the end come back on the main queue.
    /// `asked` says, on the main queue, whether something asked this agent to stop; `record` sees every line, in
    /// (true) and out (false), for `something try --record`. Throws as Spawn.start does, and AGENT_STOPPED when the
    /// program closed its input at once.
    /// With `spool`, Claude's plan B: the spool starts before the program and stops after its end.
    static func start(_ type: any Driver.Type, _ launch: Launch, _ spawn: Spawn, spool: PermissionSpool? = nil, asked: @escaping (String) -> Bool,
                      record: ((_ written: Bool, _ line: Data) -> Void)? = nil) throws -> Launched {
        let agent = Launched(type, launch, write: { [weak spawn] line in
            guard let spawn else { throw CodedError("AGENT_STOPPED", "The agent has ended; launch or resume it to go on.") }
            try spawn.write(line)
            record?(true, line)
        }, now: Engine.now)
        // A Codex or an OpenCode that cannot open its conversation is told to end.
        (agent.driver as? CodexDriver)?.quit = { [weak spawn] in spawn?.closeInput() }
        if let opencode = agent.driver as? ACPDriver {
            opencode.quit = { [weak spawn] in spawn?.closeInput() }
            opencode.take(spawn.environment)
            // OpenCode's graceful step is an interrupt and its answer, within Spawn's 3 s; the input is closed after.
            spawn.graceful = { [weak spawn, weak opencode] in
                DispatchQueue.main.async { _ = try? agent.interrupt() }
                while spawn?.running == true, opencode?.prompting == true { usleep(20_000) }
            }
        } else {
            let goodbye = agent.driver.goodbye
            spawn.graceful = { [weak spawn] in
                guard let spawn, let goodbye, (try? spawn.write(goodbye)) != nil else { return }
                record?(true, goodbye)
                // Spawn gives this step 3 s at most: the program's own exit is waited for within them.
                while spawn.running { usleep(20_000) }
            }
        }
        if let spool {
            do { try spool.start() } catch { throw CodedError("LAUNCH_FAILED", "\(error)") }
            let claude = agent.driver as? ClaudeDriver
            claude?.hookReply = { [weak spool] uuid, decision in spool?.answer(uuid, decision) ?? .gone }
            spool.asked = { [weak claude] uuid, request in claude?.hookAsked(uuid, request) }
            spool.withdrawn = { [weak claude] uuid in claude?.hookWithdrawn(uuid) }
        }
        do { try startSpawn(type, launch, spawn, spool: spool, agent: agent, asked: asked, record: record) } catch {
            spool?.stop()
            throw error
        }
        return agent
    }

    private static func startSpawn(_ type: any Driver.Type, _ launch: Launch, _ spawn: Spawn, spool: PermissionSpool?, agent: Launched,
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
