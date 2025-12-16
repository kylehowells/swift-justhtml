// Constants.swift - HTML parsing constants

import Foundation

/// Void elements that have no closing tag
public let VOID_ELEMENTS: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
]

/// Raw text elements (contents not parsed as HTML)
public let RAW_TEXT_ELEMENTS: Set<String> = [
    "script", "style"
]

/// Escapable raw text elements
public let ESCAPABLE_RAW_TEXT_ELEMENTS: Set<String> = [
    "textarea", "title"
]

/// Formatting elements for the adoption agency algorithm
public let FORMATTING_ELEMENTS: Set<String> = [
    "a", "b", "big", "code", "em", "font", "i", "nobr",
    "s", "small", "strike", "strong", "tt", "u"
]

/// Special elements that have special parsing rules
public let SPECIAL_ELEMENTS: Set<String> = [
    "address", "applet", "area", "article", "aside", "base", "basefont",
    "bgsound", "blockquote", "body", "br", "button", "caption", "center",
    "col", "colgroup", "dd", "details", "dir", "div", "dl", "dt", "embed",
    "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
    "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr",
    "html", "iframe", "img", "input", "keygen", "li", "link", "listing",
    "main", "marquee", "menu", "meta", "nav", "noembed", "noframes",
    "noscript", "object", "ol", "p", "param", "plaintext", "pre", "script",
    "search", "section", "select", "source", "style", "summary", "table",
    "tbody", "td", "template", "textarea", "tfoot", "th", "thead", "title",
    "tr", "track", "ul", "wbr", "xmp"
]

/// Elements that imply closing a <p> element
public let P_CLOSING_ELEMENTS: Set<String> = [
    "address", "article", "aside", "blockquote", "center", "details",
    "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure",
    "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
    "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "search",
    "section", "table", "ul"
]

/// Scope elements for checking element scope
public let SCOPE_ELEMENTS: Set<String> = [
    "applet", "caption", "html", "table", "td", "th", "marquee", "object", "template"
]

/// List item scope elements
public let LIST_ITEM_SCOPE_ELEMENTS: Set<String> = SCOPE_ELEMENTS.union(["ol", "ul"])

/// Button scope elements
public let BUTTON_SCOPE_ELEMENTS: Set<String> = SCOPE_ELEMENTS.union(["button"])

/// Table scope elements
public let TABLE_SCOPE_ELEMENTS: Set<String> = ["html", "table", "template"]

/// Select scope elements
public let SELECT_SCOPE_ELEMENTS: Set<String> = [] // optgroup and option are NOT scope markers

/// Elements that are implicitly closed by certain other elements
public let IMPLIED_END_TAGS: Set<String> = [
    "dd", "dt", "li", "optgroup", "option", "p", "rb", "rp", "rt", "rtc"
]

/// Thoroughly implied end tags (includes more elements)
public let THOROUGHLY_IMPLIED_END_TAGS: Set<String> = IMPLIED_END_TAGS.union([
    "caption", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"
])

/// SVG element case adjustments
public let SVG_ELEMENT_ADJUSTMENTS: [String: String] = [
    "altglyph": "altGlyph",
    "altglyphdef": "altGlyphDef",
    "altglyphitem": "altGlyphItem",
    "animatecolor": "animateColor",
    "animatemotion": "animateMotion",
    "animatetransform": "animateTransform",
    "clippath": "clipPath",
    "feblend": "feBlend",
    "fecolormatrix": "feColorMatrix",
    "fecomponenttransfer": "feComponentTransfer",
    "fecomposite": "feComposite",
    "feconvolvematrix": "feConvolveMatrix",
    "fediffuselighting": "feDiffuseLighting",
    "fedisplacementmap": "feDisplacementMap",
    "fedistantlight": "feDistantLight",
    "fedropshadow": "feDropShadow",
    "feflood": "feFlood",
    "fefunca": "feFuncA",
    "fefuncb": "feFuncB",
    "fefuncg": "feFuncG",
    "fefuncr": "feFuncR",
    "fegaussianblur": "feGaussianBlur",
    "feimage": "feImage",
    "femerge": "feMerge",
    "femergenode": "feMergeNode",
    "femorphology": "feMorphology",
    "feoffset": "feOffset",
    "fepointlight": "fePointLight",
    "fespecularlighting": "feSpecularLighting",
    "fespotlight": "feSpotLight",
    "fetile": "feTile",
    "feturbulence": "feTurbulence",
    "foreignobject": "foreignObject",
    "glyphref": "glyphRef",
    "lineargradient": "linearGradient",
    "radialgradient": "radialGradient",
    "textpath": "textPath"
]

/// Foreign attribute adjustments (for namespaced attributes)
public let FOREIGN_ATTRIBUTE_ADJUSTMENTS: [String: String] = [
    "xlink:actuate": "xlink actuate",
    "xlink:arcrole": "xlink arcrole",
    "xlink:href": "xlink href",
    "xlink:role": "xlink role",
    "xlink:show": "xlink show",
    "xlink:title": "xlink title",
    "xlink:type": "xlink type",
    "xml:lang": "xml lang",
    "xml:space": "xml space",
    "xmlns": "xmlns",
    "xmlns:xlink": "xmlns xlink"
]

/// ASCII whitespace characters
public let ASCII_WHITESPACE: Set<Character> = [" ", "\t", "\n", "\r", "\u{0C}"]

/// ASCII alpha characters
public let ASCII_ALPHA: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

/// ASCII alphanumeric characters
public let ASCII_ALPHANUMERIC: Set<Character> = ASCII_ALPHA.union(Set("0123456789"))
