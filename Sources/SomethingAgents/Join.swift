// Join: one program something launches, joined to its driver. Its lines reach the driver on the main queue, the
// driver's lines reach its input, and its end reaches the agent; the driver gets its program as a ProcessHandle, and
// what it holds is released at the end. The engine joins each launch here, and the trials join theirs the same way.
import Foundation
import SomethingCore

extension Engine {
    /// Starts `spawn` for one launch of `driving`'s kind and joins it to its driver: lines and the end come back on the
    /// main queue. `asked` says, on the main queue, whether something asked this agent to stop; `record` sees every
    /// line, in (true) and out (false), for `something try --record`. `host` and `relaunch` go to the driver through
    /// its ProcessHandle. Throws what the driver's `join` throws, as Spawn.start does, and AGENT_STOPPED when the
    /// program closed its input at once.
    static func start(_ driving: Driving, _ launch: Launch, _ spawn: Spawn, host: HostFacts = HostFacts(), relaunch: (() -> Bool)? = nil,
                      asked: @escaping (String) -> Bool, record: ((_ written: Bool, _ line: Data) -> Void)? = nil) throws -> Launched {
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
           interrupt: { [weak agent] in DispatchQueue.main.async { _ = try? agent?.interrupt() } }, host: host, relaunch: relaunch)
        spawn.kind = driving.kind
        try agent.driver.join(program)
        spawn.graceful = { agent.driver.graceful(program) }
        do { try startSpawn(launch, spawn, agent: agent, asked: asked, record: record) } catch {
            agent.driver.released()
            throw error
        }
        return agent
    }

    private static func startSpawn(_ launch: Launch, _ spawn: Spawn, agent: Launched,
                                   asked: @escaping (String) -> Bool, record: ((Bool, Data) -> Void)?) throws {
        try spawn.start(lines: { line in DispatchQueue.main.async { record?(false, line); agent.receive(line) } },
                        ended: { [weak spawn] code in
                            let errors = spawn?.errorTail ?? ""
                            agent.driver.released()
                            DispatchQueue.main.async {
                                agent.ended(code: code, errors: errors, asked: asked(launch.agent))
                            }
                        })
        try agent.begin(pid: Int(spawn.pid))
    }
}
