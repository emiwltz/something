// What keeps a space off the network beyond the scheme's policy, the app's page around the space (Scheme.swift) and the
// navigation policy (SpaceView.swift): a content rule list, and a guard on links. They close holes the lockdown test
// found: WebKit opens a connection for <link rel="preconnect">, which no policy governs, and opens one to the server of
// a link that would open a new window (target="_blank") before the sandbox refuses the window, whether the link is in
// the document or not. A link the space's own frame would follow is refused by the app's page before any connection.
// The guard also hands each clicked link to the link sheet.
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
    /// https or mailto link is handed to the app ("link" message), which shows the link sheet; any other address
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

    /// The guard cannot see a link the page's script activates where no event reaches the window: an element not in
    /// the document, or inside a shadow root. In the page's own world, before its scripts, this makes such an
    /// activation of a link outside the space do nothing, and makes every shadow root `attachShadow` makes open, so that
    /// the guard sees a link clicked inside one (one parsed from HTML keeps its mode: README, the known gap). It keeps the functions it uses, so the page cannot change them.
    static let activationScript = """
        (function () {
          const apply = Reflect.apply, Address = URL, get = (type, key) => Object.getOwnPropertyDescriptor(type.prototype, key).get;
          const parentOf = get(Node, "parentNode"), typeOf = get(Node, "nodeType"), hostOf = get(ShadowRoot, "host");
          const baseOf = get(Node, "baseURI"), eventType = get(Event, "type");
          const matches = Element.prototype.matches, attribute = Element.prototype.getAttribute;
          const click = HTMLElement.prototype.click, dispatch = EventTarget.prototype.dispatchEvent;
          const attach = Element.prototype.attachShadow, assign = Object.assign;
          // Whether activating `node` would follow a link outside the space that the guard on the window cannot hear.
          function unseen(node) {
            let link = null, hidden = false;
            for (;;) {
              const type = apply(typeOf, node, []);
              if (!link && type === 1 && apply(matches, node, ["a[href], area[href]"])) link = node;
              const parent = apply(parentOf, node, []);
              if (parent) { node = parent; continue; }
              if (type !== 11) { hidden = hidden || type !== 9; break; }
              hidden = true;
              node = apply(hostOf, node, []);
            }
            if (!link || !hidden) return false;
            try {
              const url = new Address(apply(attribute, link, ["href"]), apply(baseOf, link, []));
              return url.protocol !== "something:" && url.protocol !== "javascript:";
            } catch (error) { return true; }
          }
          function isNode(value) { try { apply(typeOf, value, []); return true; } catch (error) { return false; } }
          HTMLElement.prototype.click = function () { if (!unseen(this)) apply(click, this, []); };
          Element.prototype.attachShadow = function (init) { return apply(attach, this, [assign({}, init, { mode: "open" })]); };
          EventTarget.prototype.dispatchEvent = function (event) {
            if (apply(eventType, event, []) === "click" && isNode(this) && unseen(this)) return false;
            return apply(dispatch, this, [event]);
          };
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
