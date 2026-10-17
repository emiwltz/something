// What keeps a space off the network beyond the scheme's policy (Scheme.swift) and the navigation policy
// (SpaceWindow.swift): a content rule list, and a guard on links. Both close holes the lockdown test found: WebKit opens
// a connection for <link rel="preconnect">, which no policy governs, and opens one to a clicked link's server before it
// asks the navigation policy where it may go.
import Foundation
import SomethingCore
import WebKit

enum Lockdown {
    /// Blocks every load that is not the space's own (something:), inline (data:, blob:) or an empty frame (about:).
    /// A url-filter takes no alternation, so each allowed scheme is a rule of its own.
    static let rules = """
        [{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^something:"}, "action": {"type": "ignore-previous-rules"}},
         {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
         {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
         {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}]
        """

    /// The world the link guard runs in: something's own, which the page's scripts cannot see or change.
    static let world = WKContentWorld.world(name: "something")

    /// Catches a click on a link before WebKit follows it, so WebKit never connects to the link's server: an http,
    /// https or mailto link is handed to the app ("link" message), which shows the link window; any other address
    /// outside the space is dropped. Listening on the window, in the capture phase, from the document's start, it
    /// hears the click before any listener of the page can stop it.
    static let guardScript = """
        (function () {
          for (const type of ["click", "auxclick"]) {
            addEventListener(type, function (event) {
              const link = event.composedPath().find((node) => node instanceof Element && node.matches("a, area"));
              const href = link && (link.getAttribute("href") ?? link.getAttributeNS("http://www.w3.org/1999/xlink", "href"));
              if (href === null || href === undefined) return;
              let url;
              try { url = new URL(href, document.baseURI); } catch (error) { return; }
              if (url.protocol === "something:" || url.protocol === "javascript:") return;
              event.preventDefault();
              if (["http:", "https:", "mailto:"].includes(url.protocol)) webkit.messageHandlers.link.postMessage(url.href);
            }, true);
          }
        })();
        """

    private static var compiled: WKContentRuleList?

    /// The rule list, compiled once per run into a folder of the temporary directory. Throws a `SpaceError` when
    /// WebKit cannot compile it: then no space may open.
    @MainActor
    static func ruleList() async throws -> WKContentRuleList {
        if let compiled { return compiled }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("something-rules")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let list = try await WKContentRuleListStore(url: folder)?
                .compileContentRuleList(forIdentifier: "lockdown", encodedContentRuleList: rules) else { throw SpaceError("no list") }
            compiled = list
            return list
        } catch {
            throw SpaceError("something cannot close the network of its windows (\(error.localizedDescription)), so it opens no space.")
        }
    }
}
