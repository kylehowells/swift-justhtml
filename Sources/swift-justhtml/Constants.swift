// Constants.swift - HTML parsing constants

import Foundation

/// Void elements that have no closing tag
let VOID_ELEMENTS: Set<String> = [
	"area", "base", "br", "col", "embed", "hr", "img", "input",
	"link", "meta", "param", "source", "track", "wbr",
]

/// Special elements that have special parsing rules
let SPECIAL_ELEMENTS: Set<String> = [
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
	"tr", "track", "ul", "wbr", "xmp",
]

/// Special elements with known TagID mappings.
/// Keep `SPECIAL_ELEMENTS` as the fallback for names that do not have TagID cases
/// yet, including legacy parser boundary names like `dir`, `hgroup`, and `noembed`.
let SPECIAL_ELEMENTS_ID: Set<TagID> = [
	.address, .applet, .area, .article, .aside, .base, .basefont,
	.bgsound, .blockquote, .body, .br, .button, .caption, .center,
	.col, .colgroup, .dd, .details, .div, .dl, .dt, .embed,
	.fieldset, .figcaption, .figure, .footer, .form, .frame, .frameset,
	.h1, .h2, .h3, .h4, .h5, .h6, .head, .header, .hr, .html,
	.iframe, .img, .input, .keygen, .li, .link, .listing, .main,
	.marquee, .menu, .meta, .nav, .noframes, .noscript, .object,
	.ol, .p, .param, .plaintext, .pre, .script, .search, .section,
	.select, .source, .style, .summary, .table, .tbody, .td, .template,
	.textarea, .tfoot, .th, .thead, .title, .tr, .track, .ul, .wbr, .xmp,
]

/// SVG element case adjustments
let SVG_ELEMENT_ADJUSTMENTS: [String: String] = [
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
	"textpath": "textPath",
]

/// SVG attribute case adjustments
let SVG_ATTRIBUTE_ADJUSTMENTS: [String: String] = [
	"attributename": "attributeName",
	"attributetype": "attributeType",
	"basefrequency": "baseFrequency",
	"baseprofile": "baseProfile",
	"calcmode": "calcMode",
	"clippathunits": "clipPathUnits",
	"diffuseconstant": "diffuseConstant",
	"edgemode": "edgeMode",
	"filterunits": "filterUnits",
	"glyphref": "glyphRef",
	"gradienttransform": "gradientTransform",
	"gradientunits": "gradientUnits",
	"kernelmatrix": "kernelMatrix",
	"kernelunitlength": "kernelUnitLength",
	"keypoints": "keyPoints",
	"keysplines": "keySplines",
	"keytimes": "keyTimes",
	"lengthadjust": "lengthAdjust",
	"limitingconeangle": "limitingConeAngle",
	"markerheight": "markerHeight",
	"markerunits": "markerUnits",
	"markerwidth": "markerWidth",
	"maskcontentunits": "maskContentUnits",
	"maskunits": "maskUnits",
	"numoctaves": "numOctaves",
	"pathlength": "pathLength",
	"patterncontentunits": "patternContentUnits",
	"patterntransform": "patternTransform",
	"patternunits": "patternUnits",
	"pointsatx": "pointsAtX",
	"pointsaty": "pointsAtY",
	"pointsatz": "pointsAtZ",
	"preservealpha": "preserveAlpha",
	"preserveaspectratio": "preserveAspectRatio",
	"primitiveunits": "primitiveUnits",
	"refx": "refX",
	"refy": "refY",
	"repeatcount": "repeatCount",
	"repeatdur": "repeatDur",
	"requiredextensions": "requiredExtensions",
	"requiredfeatures": "requiredFeatures",
	"specularconstant": "specularConstant",
	"specularexponent": "specularExponent",
	"spreadmethod": "spreadMethod",
	"startoffset": "startOffset",
	"stddeviation": "stdDeviation",
	"stitchtiles": "stitchTiles",
	"surfacescale": "surfaceScale",
	"systemlanguage": "systemLanguage",
	"tablevalues": "tableValues",
	"targetx": "targetX",
	"targety": "targetY",
	"textlength": "textLength",
	"viewbox": "viewBox",
	"viewtarget": "viewTarget",
	"xchannelselector": "xChannelSelector",
	"ychannelselector": "yChannelSelector",
	"zoomandpan": "zoomAndPan",
]

/// MathML attribute case adjustments
let MATHML_ATTRIBUTE_ADJUSTMENTS: [String: String] = [
	"definitionurl": "definitionURL",
]

/// Foreign attribute adjustments (for namespaced attributes)
let FOREIGN_ATTRIBUTE_ADJUSTMENTS: [String: String] = [
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
	"xmlns:xlink": "xmlns xlink",
]

/// ASCII whitespace characters
let ASCII_WHITESPACE: Set<Character> = [" ", "\t", "\n", "\r", "\u{0C}"]

/// ASCII alpha characters
let ASCII_ALPHA: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

/// ASCII alphanumeric characters
let ASCII_ALPHANUMERIC: Set<Character> = ASCII_ALPHA.union(Set("0123456789"))
