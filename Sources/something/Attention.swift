// The signs of a request outside the window: the Dock's badge counts every request waiting; while something is in
// the background, its icon bounces once per new request and, only if the person turned on "Notify me when a request
// waits", a notification of the Mac says who waits and in which space. It never carries the command: that stays in
// the panel, where the person decides. A click on the notification is Show Request. A space a build made while
// something was in the background is said the same way, and its click opens it. The Dock and the notifications are
// seams, so that a test bounces nothing and never reaches the notification center.
import AppKit
import SomethingCore
import UserNotifications

/// The Dock and whether the app is in front: NSApp, or a test's fake.
protocol DockLike: AnyObject {
    var isActive: Bool { get }
    func showBadge(_ label: String?)
    func bounceOnce()
}

extension NSApplication: DockLike {
    func showBadge(_ label: String?) { dockTile.badgeLabel = label }
    func bounceOnce() { requestUserAttention(.informationalRequest) }
}

/// Where notifications go: the Mac's notification center, or a test's fake. `id` is the request's.
protocol Notifier: AnyObject {
    func post(_ id: String, title: String, body: String)
    func withdraw(_ ids: [String])
}

final class Attention {
    let dock: DockLike
    /// nil when this process has no bundle to post as (`swift run`, the tests).
    let notifier: Notifier?
    /// Whether the person turned notifications on; read at each new request.
    var notify: () -> Bool = { false }
    private var seen: Set<String> = []
    private var badge: String?

    init(dock: DockLike, notifier: Notifier?) {
        (self.dock, self.notifier) = (dock, notifier)
    }

    /// Follows the requests waiting, oldest first: the badge says their number, and each one new since the last call
    /// bounces the icon once and may be notified, only while the app is in the background. A request that left
    /// takes its notification with it.
    func follow(_ waiting: [Request], who: (Request) -> Asker) {
        let label = waiting.isEmpty ? nil : String(waiting.count)
        if label != badge {
            badge = label
            dock.showBadge(label)
        }
        let ids = Set(waiting.map(\.id)), new = waiting.filter { !seen.contains($0.id) }, gone = seen.subtracting(ids)
        seen = ids
        if !gone.isEmpty { notifier?.withdraw(gone.sorted()) }
        guard !dock.isActive else { return }
        for request in new {
            dock.bounceOnce()
            if notify(), let notifier {
                let (title, body) = Self.banner(request, who: who(request))
                notifier.post(request.id, title: title, body: body)
            }
        }
    }

    /// Says that the space `name`, titled `title`, a build made, is ready: a notification only while something is in
    /// the background and the person turned them on (in front, the window's toast says it).
    func ready(_ name: String, title: String) {
        guard !dock.isActive, notify(), let notifier else { return }
        notifier.post(Self.readyPrefix + name, title: "\(title) is ready", body: "Your assistant built it. Click to open it.")
    }

    /// The notification of a space said ready is named after it, apart from a request's.
    static let readyPrefix = "ready:"
    static func readySpace(_ id: String) -> String? { id.hasPrefix(readyPrefix) ? String(id.dropFirst(readyPrefix.count)) : nil }

    /// The notification's words: who waits, then the space and what it wants, never the command.
    static func banner(_ request: Request, who: Asker) -> (title: String, body: String) {
        let what = request.kind == "question" ? "asks you a question" : "wants to \(Words.wants(request.tool))"
        return ("\(who.program) is waiting for you", who.space.map { "\($0) · \(what)" } ?? what.prefix(1).uppercased() + what.dropFirst())
    }
}

/// The Mac's notification center, asked for permission at the first notification. It can only be reached from an
/// app bundle: elsewhere UNUserNotificationCenter stops the process, so `make` returns nil there.
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    /// Hears a click on the notification of this id.
    let clicked: (String) -> Void

    private init(clicked: @escaping (String) -> Void) {
        self.clicked = clicked
    }

    /// The notifier of `bundle`, which hears the clicks (`clicked`, on the main queue); nil when `bundle` is not an
    /// app with an identifier.
    static func make(bundle: Bundle = .main, clicked: @escaping (String) -> Void) -> SystemNotifier? {
        guard bundle.bundleURL.pathExtension == "app", bundle.bundleIdentifier != nil else { return nil }
        let notifier = SystemNotifier(clicked: clicked)
        UNUserNotificationCenter.current().delegate = notifier
        return notifier
    }

    func post(_ id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        (content.title, content.body) = (title, body)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted { center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        }
    }

    func withdraw(_ ids: [String]) { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids) }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async { self.clicked(id) }
        done()
    }

    /// In front, the panel is enough: no banner over it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([])
    }
}
