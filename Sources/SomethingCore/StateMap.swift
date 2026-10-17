// The only place the engine chooses an agent's state words. Drivers and readers report neutral facts (is a holder
// alive, is a turn open, is the agent waiting on the person); this table turns them into `state`, `waiting` and,
// for a recent write, `evidence`. One table means one meaning of "working" for every harness.
import Foundation

public enum StateMap {
    /// What the agent waits on, as far as its source can tell.
    public enum Waiting: Equatable, Sendable {
        case permission, answer, nothing
        /// The source cannot say (some harnesses seen elsewhere never write it).
        case unknown
    }

    public struct Facts: Equatable, Sendable {
        /// true: a living process holds the conversation; false: proven ended; nil: nothing proves either.
        public var alive: Bool?
        /// The proof behind `alive`, as the source names it ("child", "registry", "cwd", ...).
        public var evidence: String?
        /// true: a turn is running; false: the last turn closed; nil: no turn seen.
        public var turnOpen: Bool?
        public var waiting: Waiting = .unknown
        /// The conversation was closed normally (an end marker). Read only when `alive` is false, where it wins over
        /// a turn left open: a reader that sees the marker but cannot prove the process gone sets `alive` to false.
        public var ended = false
        /// The last turn or the process failed.
        public var failed = false
        /// The last turn was stopped before its end.
        public var aborted = false
        /// When the conversation's file was last written; nil when unknown.
        public var lastWrite: Date?

        public init(alive: Bool?, evidence: String? = nil, turnOpen: Bool? = nil, waiting: Waiting = .unknown,
                    ended: Bool = false, failed: Bool = false, aborted: Bool = false, lastWrite: Date? = nil) {
            (self.alive, self.evidence, self.turnOpen, self.waiting) = (alive, evidence, turnOpen, waiting)
            (self.ended, self.failed, self.aborted, self.lastWrite) = (ended, failed, aborted, lastWrite)
        }
    }

    public struct Result: Equatable, Sendable {
        public var state: String
        public var waiting: String?
        public var evidence: String?
    }

    /// An open turn without a living holder still counts as working when its file was written this recently.
    public static let recentWrite: TimeInterval = 120

    /// The state words for these facts at `now`. Never "idle" without a living holder, and "waiting" exactly
    /// when `waiting` is "permission" or "answer".
    public static func map(_ facts: Facts, now: Date) -> Result {
        switch facts.alive {
        case true?:
            let waiting = word(facts.waiting)
            if waiting == "permission" || waiting == "answer" { return Result(state: "waiting", waiting: waiting, evidence: facts.evidence) }
            // A waiting word other than the two is "none" or nil: the agent is not shown waiting.
            let state = facts.turnOpen == true ? "working" : facts.failed ? "error" : facts.aborted ? "interrupted" : "idle"
            return Result(state: state, waiting: waiting, evidence: facts.evidence)
        case false?:
            // A turn left open by a process that is gone did not end normally, unless the conversation says it closed.
            let state = facts.failed ? "error" : facts.ended ? "done" : facts.aborted || facts.turnOpen == true ? "interrupted" : "done"
            return Result(state: state, waiting: "none", evidence: facts.evidence)
        case nil:
            // Without a holder nobody can say the agent waits; only "none" from the source survives.
            let waiting = facts.waiting == .nothing ? "none" : nil
            if facts.turnOpen == true, let written = facts.lastWrite, now.timeIntervalSince(written) < recentWrite {
                return Result(state: "working", waiting: waiting, evidence: "recent-write")
            }
            return Result(state: "unknown", waiting: waiting, evidence: facts.evidence)
        }
    }

    static func word(_ waiting: Waiting) -> String? {
        switch waiting {
        case .permission: return "permission"
        case .answer: return "answer"
        case .nothing: return "none"
        case .unknown: return nil
        }
    }
}
