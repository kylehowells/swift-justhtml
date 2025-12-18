// Node.swift - Simple DOM node for HTML parsing

import Foundation

// MARK: - Namespace

/// Namespace for HTML elements
public enum Namespace: String, Sendable {
	case html
	case svg
	case math
}

// MARK: - NodeData

/// Data payload for special node types
public enum NodeData {
	case text(String)
	case comment(String)
	case doctype(Doctype)
}

// MARK: - Doctype

/// DOCTYPE information
public struct Doctype: Sendable {
	public let name: String?
	public let publicId: String?
	public let systemId: String?
	public let forceQuirks: Bool

	public init(
		name: String? = nil, publicId: String? = nil, systemId: String? = nil, forceQuirks: Bool = false
	) {
		self.name = name
		self.publicId = publicId
		self.systemId = systemId
		self.forceQuirks = forceQuirks
	}
}

// MARK: - TagID

/// Integer tag identifier for fast comparisons
public enum TagID: UInt8, Sendable {
	// Special node types
	case document = 0
	case documentFragment = 1
	case text = 2
	case comment = 3
	case doctype = 4

	// Common HTML elements (ordered by frequency in typical HTML)
	case div = 10
	case span = 11
	case a = 12
	case p = 13
	case li = 14
	case ul = 15
	case img = 16
	case table = 17
	case tr = 18
	case td = 19
	case th = 20
	case tbody = 21
	case thead = 22
	case tfoot = 23
	case br = 24
	case input = 25
	case button = 26
	case form = 27
	case label = 28
	case select = 29
	case option = 30
	case optgroup = 31
	case textarea = 32

	// Document structure
	case html = 40
	case head = 41
	case body = 42
	case title = 43
	case meta = 44
	case link = 45
	case script = 46
	case style = 47
	case base = 48
	case noscript = 49

	// Headings
	case h1 = 50
	case h2 = 51
	case h3 = 52
	case h4 = 53
	case h5 = 54
	case h6 = 55

	// Semantic elements
	case header = 60
	case footer = 61
	case nav = 62
	case main = 63
	case article = 64
	case section = 65
	case aside = 66
	case figure = 67
	case figcaption = 68
	case address = 69
	case search = 70

	// Text formatting
	case strong = 80
	case em = 81
	case b = 82
	case i = 83
	case u = 84
	case s = 85
	case small = 86
	case mark = 87
	case del = 88
	case ins = 89
	case sub = 90
	case sup = 91
	case code = 92
	case pre = 93
	case blockquote = 94
	case q = 95
	case cite = 96
	case abbr = 97
	case dfn = 98
	case kbd = 99
	case samp = 100
	case `var` = 101
	case time = 102
	case data = 103
	case ruby = 104
	case rt = 105
	case rp = 106
	case rb = 107
	case rtc = 108

	// Lists
	case ol = 110
	case dl = 111
	case dt = 112
	case dd = 113

	// Tables
	case caption = 120
	case colgroup = 121
	case col = 122

	// Media
	case video = 130
	case audio = 131
	case source = 132
	case track = 133
	case picture = 134
	case canvas = 135
	case map = 136
	case area = 137
	case embed = 138
	case object = 139
	case param = 140
	case iframe = 141

	// Forms
	case fieldset = 150
	case legend = 151
	case datalist = 152
	case output = 153
	case progress = 154
	case meter = 155

	// Interactive
	case details = 160
	case summary = 161
	case dialog = 162
	case menu = 163

	// Obsolete but still used
	case font = 170
	case center = 171
	case big = 172
	case strike = 173
	case tt = 174
	case nobr = 175
	case marquee = 176
	case blink = 177
	case frame = 178
	case frameset = 179
	case noframes = 180
	case applet = 181
	case basefont = 182
	case bgsound = 183
	case isindex = 184
	case listing = 185
	case plaintext = 186
	case xmp = 187
	case nextid = 188
	case menuitem = 189
	case selectedcontent = 190
	case keygen = 191
	case image = 192 // Remapped to img
	case wbr = 193
	case hr = 194

	// SVG integration points
	case svg = 200
	case foreignObject = 201
	case desc = 202

	// MathML integration points
	case math = 210
	case mi = 211
	case mo = 212
	case mn = 213
	case ms = 214
	case mtext = 215
	case annotationXml = 216

	/// Template
	case template = 220

	/// Unknown/custom elements
	case unknown = 255
}

/// Fast string-to-TagID lookup table
private let tagNameToID: [String: TagID] = [
	"#document": .document,
	"#document-fragment": .documentFragment,
	"#text": .text,
	"#comment": .comment,
	"!doctype": .doctype,
	"div": .div,
	"span": .span,
	"a": .a,
	"p": .p,
	"li": .li,
	"ul": .ul,
	"img": .img,
	"table": .table,
	"tr": .tr,
	"td": .td,
	"th": .th,
	"tbody": .tbody,
	"thead": .thead,
	"tfoot": .tfoot,
	"br": .br,
	"input": .input,
	"button": .button,
	"form": .form,
	"label": .label,
	"select": .select,
	"option": .option,
	"optgroup": .optgroup,
	"textarea": .textarea,
	"html": .html,
	"head": .head,
	"body": .body,
	"title": .title,
	"meta": .meta,
	"link": .link,
	"script": .script,
	"style": .style,
	"base": .base,
	"noscript": .noscript,
	"h1": .h1,
	"h2": .h2,
	"h3": .h3,
	"h4": .h4,
	"h5": .h5,
	"h6": .h6,
	"header": .header,
	"footer": .footer,
	"nav": .nav,
	"main": .main,
	"article": .article,
	"section": .section,
	"aside": .aside,
	"figure": .figure,
	"figcaption": .figcaption,
	"address": .address,
	"search": .search,
	"strong": .strong,
	"em": .em,
	"b": .b,
	"i": .i,
	"u": .u,
	"s": .s,
	"small": .small,
	"mark": .mark,
	"del": .del,
	"ins": .ins,
	"sub": .sub,
	"sup": .sup,
	"code": .code,
	"pre": .pre,
	"blockquote": .blockquote,
	"q": .q,
	"cite": .cite,
	"abbr": .abbr,
	"dfn": .dfn,
	"kbd": .kbd,
	"samp": .samp,
	"var": .var,
	"time": .time,
	"data": .data,
	"ruby": .ruby,
	"rt": .rt,
	"rp": .rp,
	"rb": .rb,
	"rtc": .rtc,
	"ol": .ol,
	"dl": .dl,
	"dt": .dt,
	"dd": .dd,
	"caption": .caption,
	"colgroup": .colgroup,
	"col": .col,
	"video": .video,
	"audio": .audio,
	"source": .source,
	"track": .track,
	"picture": .picture,
	"canvas": .canvas,
	"map": .map,
	"area": .area,
	"embed": .embed,
	"object": .object,
	"param": .param,
	"iframe": .iframe,
	"fieldset": .fieldset,
	"legend": .legend,
	"datalist": .datalist,
	"output": .output,
	"progress": .progress,
	"meter": .meter,
	"details": .details,
	"summary": .summary,
	"dialog": .dialog,
	"menu": .menu,
	"font": .font,
	"center": .center,
	"big": .big,
	"strike": .strike,
	"tt": .tt,
	"nobr": .nobr,
	"marquee": .marquee,
	"blink": .blink,
	"frame": .frame,
	"frameset": .frameset,
	"noframes": .noframes,
	"applet": .applet,
	"basefont": .basefont,
	"bgsound": .bgsound,
	"isindex": .isindex,
	"listing": .listing,
	"plaintext": .plaintext,
	"xmp": .xmp,
	"nextid": .nextid,
	"menuitem": .menuitem,
	"selectedcontent": .selectedcontent,
	"keygen": .keygen,
	"image": .image,
	"wbr": .wbr,
	"hr": .hr,
	"svg": .svg,
	"foreignObject": .foreignObject,
	"desc": .desc,
	"math": .math,
	"mi": .mi,
	"mo": .mo,
	"mn": .mn,
	"ms": .ms,
	"mtext": .mtext,
	"annotation-xml": .annotationXml,
	"template": .template,
]

extension TagID {
	/// Get TagID from a tag name string
	@inline(__always)
	static func from(_ name: String) -> TagID {
		return tagNameToID[name] ?? .unknown
	}
}

// MARK: - Node

/// A simple DOM node
public final class Node {
	/// Node type/name: "#document", "#document-fragment", "#text", "#comment", "!doctype", or tag name
	public let name: String

	/// Fast integer tag identifier for comparisons
	public let tagId: TagID

	/// Namespace: .html, .svg, .math, or nil for non-elements
	public let namespace: Namespace?

	/// Parent node (weak to avoid cycles)
	public weak var parent: Node? = nil

	/// Child nodes
	public private(set) var children: [Node] = []

	/// Attributes (empty for non-elements)
	public var attrs: [String: String]

	/// Data for text/comment/doctype nodes
	public var data: NodeData? = nil

	/// Template content (for <template> elements)
	public var templateContent: Node? = nil

	public init(
		name: String, namespace: Namespace? = nil, attrs: [String: String] = [:], data: NodeData? = nil
	) {
		self.name = name
		self.tagId = TagID.from(name)
		self.attrs = attrs
		self.data = data

		// Determine namespace
		if name.hasPrefix("#") || name == "!doctype" {
			self.namespace = nil
		}
		else {
			self.namespace = namespace ?? .html
		}

		// Create template content for template elements
		if self.tagId == .template, namespace == nil || namespace == .html {
			self.templateContent = Node(name: "#document-fragment")
		}
	}

	// MARK: - DOM Manipulation

	public func appendChild(_ node: Node) {
		self.children.append(node)
		node.parent = self
	}

	public func removeChild(_ node: Node) {
		if let idx = children.firstIndex(where: { $0 === node }) {
			self.children.remove(at: idx)
			node.parent = nil
		}
	}

	public func insertBefore(_ node: Node, reference: Node?) {
		guard let reference = reference else {
			self.appendChild(node)
			return
		}

		if let idx = children.firstIndex(where: { $0 === reference }) {
			self.children.insert(node, at: idx)
			node.parent = self
		}
	}

	public func replaceChild(_ newNode: Node, oldNode: Node) -> Node? {
		if let idx = children.firstIndex(where: { $0 === oldNode }) {
			self.children[idx] = newNode
			oldNode.parent = nil
			newNode.parent = self
			return oldNode
		}
		return nil
	}

	public func cloneNode(deep: Bool = false) -> Node {
		let clone = Node(name: name, namespace: namespace, attrs: attrs, data: data)
		if let templateContent = templateContent {
			clone.templateContent = templateContent.cloneNode(deep: deep)
		}
		if deep {
			for child in self.children {
				clone.appendChild(child.cloneNode(deep: true))
			}
		}
		return clone
	}

	// MARK: - Properties

	public var hasChildNodes: Bool {
		!self.children.isEmpty
	}

	/// Direct text content of this node only (for #text nodes)
	public var text: String {
		if case let .text(s) = data {
			return s
		}
		return ""
	}

	// MARK: - Serialization

	/// Extract all text content
	/// - Parameters:
	///   - separator: String to insert between text parts (default: "" to preserve original spacing)
	///   - strip: If true, trim whitespace from each text node (default: false to preserve spacing)
	///   - collapseWhitespace: If true, collapse runs of whitespace to single spaces (default: true)
	/// - Returns: Plain text content of the node
	public func toText(separator: String = "", strip: Bool = false, collapseWhitespace: Bool = true) -> String {
		var parts: [String] = []
		self.collectText(into: &parts, strip: strip)
		var result = parts.joined(separator: separator)
		if collapseWhitespace {
			// Collapse runs of whitespace to single spaces
			result = result.replacingOccurrences(
				of: "\\s+",
				with: " ",
				options: .regularExpression
			).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return result
	}

	private func collectText(into parts: inout [String], strip: Bool) {
		if case let .text(s) = data {
			let text = strip ? s.trimmingCharacters(in: .whitespacesAndNewlines) : s
			if !text.isEmpty {
				parts.append(text)
			}
			return
		}

		for child in self.children {
			child.collectText(into: &parts, strip: strip)
		}
		// Note: templateContent is intentionally NOT included
		// Template contents are inert and should not be part of text extraction
	}

	/// Serialize to HTML
	public func toHTML(pretty: Bool = true, indentSize: Int = 2) -> String {
		return Serialize.toHTML(self, pretty: pretty, indentSize: indentSize)
	}

	/// Serialize to html5lib test format
	public func toTestFormat() -> String {
		return Serialize.toTestFormat(self)
	}

	/// Serialize to Markdown (GitHub-Flavored Markdown subset)
	public func toMarkdown() -> String {
		return Serialize.toMarkdown(self)
	}

	/// Query using CSS selector
	public func query(_ selector: String) throws -> [Node] {
		return try justhtml.query(self, selector: selector)
	}
}
