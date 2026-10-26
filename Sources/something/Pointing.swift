// What point mode asks of the page, always from something's own world (Lockdown.world), where the page's scripts can
// neither see the questions nor change the functions that answer them: the part under a point, the part before or after
// another (the keys' way), where parts are now, and a scroll the overlay hands on. A part is an element at least 40x24
// points; it is named by a path of standard tags and :nth-of-type only, never a class, an id or a custom element, so
// what something keeps of a part says nothing the page chose. Nothing runs in the page's world; but a step by keys
// scrolls its part into view, a scroll the page sees, as it sees the wheel's scroll the overlay hands on.
import CoreGraphics
import WebKit

enum Pointing {
    /// A part of the page: its path from the root, its tag, and its rectangle in the page's viewport, in points.
    struct Part: Equatable {
        let path: String, tag: String
        var rect: CGRect
        /// What the frame's pill and the composer call it.
        var kind: String { Pointing.kind(tag) }
    }

    /// The smallest part a person points at: smaller things are pointed at by the first ancestor this big.
    static let least = CGSize(width: 40, height: 24)

    /// The HTML elements a path may name (SVG's root among them). An element of any other name, a custom element above
    /// all, is never part of a path: what lies inside one is pointed at by its nearest standard ancestor.
    static let tags: [String] = """
        a abbr address article aside audio b bdi bdo blockquote body br button canvas caption cite code col colgroup data \
        datalist dd del details dfn dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header \
        hgroup hr html i iframe img input ins kbd label legend li main mark menu meter nav ol optgroup option output p \
        picture pre progress q s samp search section select small span strong sub summary sup svg table tbody td \
        textarea tfoot th thead time tr u ul var video
        """.split(separator: " ").map(String.init)

    /// The part at (x, y) of the viewport, or null over the page's background.
    static let partScript = """
        const standard = new Set(tags), root = document.documentElement;
        let node = document.elementFromPoint(x, y);
        if (!node) return null;
        const chain = [];
        for (let n = node; n; n = n.parentElement) chain.push(n);
        for (let i = chain.length - 1; i >= 0; i--) if (!standard.has(chain[i].localName)) { node = chain[i].parentElement; break; }
        while (node && node !== document.body && node !== root) {
          const box = node.getBoundingClientRect();
          if (box.width >= least[0] && box.height >= least[1]) break;
          node = node.parentElement;
        }
        if (!node || node === document.body || node === root) return null;
        return describe(node);
        """ + described

    /// The part `by` (1 or -1) after the part at `from`, in the page's order, or the first (the last) when `from` is
    /// null or gone: the parts a pointer could frame, shown ones only, scrolled into view. Past the last (the first) it
    /// goes round when `wrap`, else answers null: the keys leave the page for the comments' tray.
    static let stepScript = """
        const standard = new Set(tags), parts = [];
        const walk = (node) => {
          for (const child of node.children) {
            if (!standard.has(child.localName)) continue;
            const box = child.getBoundingClientRect();
            const shown = child.checkVisibility?.({opacityProperty: true, visibilityProperty: true}) !== false;
            if (shown && box.width >= least[0] && box.height >= least[1]) parts.push(child);
            walk(child);
          }
        };
        if (document.body) walk(document.body);
        if (!parts.length) return null;
        const at = from ? parts.indexOf(document.querySelector(from)) : -1;
        if (at >= 0 && !wrap && (at + by < 0 || at + by >= parts.length)) return null;
        const node = parts[at < 0 ? (by > 0 ? 0 : parts.length - 1) : (at + by + parts.length) % parts.length];
        node.scrollIntoView({block: "nearest", inline: "nearest", behavior: "instant"});
        return describe(node);
        """ + described

    /// Names a node by its path of tags from the root, with its tag and its rectangle: what a part is.
    private static let described = """

        function describe(node) {
          const path = [];
          for (let n = node; n !== document.documentElement; n = n.parentElement) {
            let i = 1;
            for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === n.localName) i++;
            path.unshift(`${n.localName}:nth-of-type(${i})`);
          }
          const box = node.getBoundingClientRect();
          return {path: ":root > " + path.join(" > "), tag: node.localName, rect: [box.x, box.y, box.width, box.height]};
        }
        """

    /// Where each part of `paths` is now, null for one that is gone.
    static let rectsScript = """
        return paths.map((path) => {
          const node = document.querySelector(path);
          if (!node) return null;
          const box = node.getBoundingClientRect();
          return [box.x, box.y, box.width, box.height];
        });
        """

    /// The part at `point` of `web`'s viewport (the space's frame fills the view), or nil over nothing a person can
    /// point at, or when the page cannot be asked (not loaded, or gone).
    @MainActor
    static func part(at point: CGPoint, in web: WKWebView, frame: WKFrameInfo) async -> Part? {
        await ask(partScript, ["x": point.x, "y": point.y], in: web, frame: frame)
    }

    /// The part `by` (1 or -1) after `from` in the page's order, scrolled into view, or the first (the last) when
    /// `from` is nil or gone; nil when the page has no part or cannot be asked, or past the last (the first) part
    /// unless `wrap`.
    @MainActor
    static func step(_ by: Int, from: Part?, wrap: Bool = true, in web: WKWebView, frame: WKFrameInfo) async -> Part? {
        await ask(stepScript, ["by": by, "from": from?.path ?? NSNull(), "wrap": wrap], in: web, frame: frame)
    }

    @MainActor
    private static func ask(_ script: String, _ arguments: [String: Any], in web: WKWebView, frame: WKFrameInfo) async -> Part? {
        let found = try? await web.callAsyncJavaScript(script, arguments: arguments.merging(["tags": tags, "least": [least.width, least.height]]) { $1 },
                                                       in: frame, contentWorld: Lockdown.world)
        guard let found = found as? [String: Any], let path = found["path"] as? String, let tag = found["tag"] as? String,
              let rect = rect(found["rect"]) else { return nil }
        return Part(path: path, tag: tag, rect: rect)
    }

    /// Where the parts of `paths` are now, in their order: nil for one the page no longer has; empty when the page
    /// cannot be asked (between two loads), so that its parts are not taken for gone.
    @MainActor
    static func rects(_ paths: [String], in web: WKWebView, frame: WKFrameInfo) async -> [CGRect?] {
        guard !paths.isEmpty,
              let list = try? await web.callAsyncJavaScript(rectsScript, arguments: ["paths": paths], in: frame, contentWorld: Lockdown.world) as? [Any],
              list.count == paths.count else { return [] }
        return list.map(rect)
    }

    /// Scrolls what is under `point` by `delta` points, as the wheel the overlay takes would have: the nearest box
    /// that scrolls that way (a page often scrolls inside one), else the page; by its own world's scrollBy, which a
    /// page cannot tell from the person's scroll.
    @MainActor
    static func scroll(by delta: CGSize, at point: CGPoint, in web: WKWebView, frame: WKFrameInfo) async {
        _ = try? await web.callAsyncJavaScript(scrollScript, arguments: ["dx": delta.width, "dy": delta.height, "x": point.x, "y": point.y],
                                               in: frame, contentWorld: Lockdown.world)
    }

    /// The wheel's scroll, from something's world: `dx`, `dy` at `x`, `y` of the viewport.
    static let scrollScript = """
        const scrolls = (node) => {
          const style = getComputedStyle(node), can = (overflow) => overflow === "auto" || overflow === "scroll";
          return (dy !== 0 && can(style.overflowY) && node.scrollHeight > node.clientHeight)
            || (dx !== 0 && can(style.overflowX) && node.scrollWidth > node.clientWidth);
        };
        let node = document.elementFromPoint(x, y);
        while (node && node !== document.body && node !== document.documentElement && !scrolls(node)) node = node.parentElement;
        (node && node !== document.body && node !== document.documentElement ? node : window).scrollBy({left: dx, top: dy, behavior: "instant"});
        return 0;
        """

    private static func rect(_ value: Any?) -> CGRect? {
        guard let box = value as? [NSNumber], box.count == 4 else { return nil }
        return CGRect(x: box[0].doubleValue, y: box[1].doubleValue, width: box[2].doubleValue, height: box[3].doubleValue)
    }

    /// A part's name in something's words, from its tag alone: the page's own words never reach something's chrome.
    static func kind(_ tag: String) -> String {
        switch tag {
        case "table", "thead", "tbody", "tfoot": "this table"
        case "tr": "this row"
        case "td", "th": "this cell"
        case "img", "picture": "this image"
        case "svg", "canvas": "this drawing"
        case "video": "this video"
        case "audio": "this player"
        case "h1", "h2", "h3", "h4", "h5", "h6", "hgroup": "this heading"
        case "p": "this paragraph"
        case "blockquote", "q": "this quote"
        case "ul", "ol", "dl", "menu": "this list"
        case "li", "dt", "dd": "this item"
        case "header": "this header"
        case "footer": "this footer"
        case "nav": "this navigation"
        case "aside": "this aside"
        case "section", "search": "this section"
        case "article": "this article"
        case "main": "the main part"
        case "form", "fieldset": "this form"
        case "button": "this button"
        case "input", "textarea", "select", "output": "this field"
        case "figure": "this figure"
        case "figcaption", "caption", "legend", "label": "this caption"
        case "a": "this link"
        case "pre", "code": "this code"
        case "details", "summary": "this disclosure"
        case "dialog": "this dialog"
        case "iframe": "this frame"
        case "progress", "meter": "this gauge"
        case "span", "b", "strong", "em", "i", "small", "mark", "time", "abbr", "cite", "s", "u", "sub", "sup": "this text"
        default: "this block"
        }
    }
}
