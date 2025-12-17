// htmltool - A command-line HTML parsing utility
//
// Usage:
//   cat file.html | htmltool [command] [options]
//   htmltool [command] [options] < file.html
//
// Commands:
//   text      Extract plain text from HTML (default)
//   html      Pretty-print HTML
//   markdown  Convert HTML to Markdown
//   query     Query HTML with CSS selector
//   stream    Show parsing events
//
// Options:
//   -s, --selector <sel>  CSS selector for query command
//   -c, --compact         Compact output (no pretty printing)
//   -h, --help            Show this help message

import Foundation
import swift_justhtml

// MARK: - Helpers

func printError(_ message: String) {
	FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Command

enum Command: String {
	case text
	case html
	case markdown
	case query
	case stream
	case help
}

// MARK: - Options

struct Options {
	var command: Command = .text
	var selector: String? = nil
	var compact: Bool = false
}

func parseArgs(_ args: [String]) -> Options {
	var options = Options()
	var i = 1 // Skip program name

	while i < args.count {
		let arg = args[i]

		switch arg {
			case "-h", "--help":
				options.command = .help

			case "-s", "--selector":
				i += 1
				if i < args.count {
					options.selector = args[i]
				}

			case "-c", "--compact":
				options.compact = true

			case "text", "html", "markdown", "query", "stream", "help":
				if let cmd = Command(rawValue: arg) {
					options.command = cmd
				}

			default:
				// Check if it's a command
				if let cmd = Command(rawValue: arg) {
					options.command = cmd
				}
		}

		i += 1
	}

	return options
}

func printHelp() {
	let help = """
	htmltool - A command-line HTML parsing utility
	
	Usage:
	  cat file.html | htmltool [command] [options]
	  htmltool [command] [options] < file.html
	
	Commands:
	  text      Extract plain text from HTML (default)
	  html      Pretty-print HTML
	  markdown  Convert HTML to Markdown
	  query     Query HTML with CSS selector (requires -s)
	  stream    Show parsing events
	
	Options:
	  -s, --selector <sel>  CSS selector for query command
	  -c, --compact         Compact output (no pretty printing)
	  -h, --help            Show this help message
	
	Examples:
	  cat page.html | htmltool text
	  cat page.html | htmltool query -s "a[href]"
	  cat page.html | htmltool html -c
	  cat page.html | htmltool markdown
	"""
	print(help)
}

// MARK: - Main

func main() {
	let options = parseArgs(CommandLine.arguments)

	if options.command == .help {
		printHelp()
		return
	}

	// Read HTML from stdin
	var html = ""
	while let line = readLine(strippingNewline: false) {
		html += line
	}

	if html.isEmpty {
		printError("Error: No input provided. Pipe HTML to stdin.")
		exit(1)
	}

	do {
		switch options.command {
			case .text:
				let doc = try JustHTML(html)
				print(doc.toText())

			case .html:
				let doc = try JustHTML(html)
				print(doc.toHTML(pretty: !options.compact))

			case .markdown:
				let doc = try JustHTML(html)
				print(doc.toMarkdown())

			case .query:
				guard let selector = options.selector else {
					printError("Error: query command requires -s/--selector option")
					exit(1)
				}

				let doc = try JustHTML(html)
				let nodes = try doc.query(selector)

				if nodes.isEmpty {
					printError("No matches found for selector: \(selector)")
				}
				else {
					for node in nodes {
						print(node.toHTML(pretty: !options.compact))
						if !options.compact {
							print() // Blank line between results
						}
					}
				}

			case .stream:
				for event in HTMLStream(html) {
					switch event {
						case let .start(tag, attrs):
							var attrStr = ""
							if !attrs.isEmpty {
								attrStr =
									" "
										+ attrs.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
							}
							print("START: <\(tag)\(attrStr)>")

						case let .end(tag):
							print("END: </\(tag)>")

						case let .text(content):
							let escaped = content
								.replacingOccurrences(of: "\n", with: "\\n")
								.replacingOccurrences(of: "\t", with: "\\t")
							print("TEXT: \"\(escaped)\"")

						case let .comment(content):
							print("COMMENT: <!--\(content)-->")

						case let .doctype(name, publicId, systemId):
							var doctypeStr = "<!DOCTYPE \(name ?? "")"
							if let pub = publicId {
								doctypeStr += " PUBLIC \"\(pub)\""
							}
							if let sys = systemId {
								doctypeStr += " \"\(sys)\""
							}
							doctypeStr += ">"
							print("DOCTYPE: \(doctypeStr)")
					}
				}

			case .help:
				printHelp()
		}
	}
	catch let error as SelectorError {
		printError("Selector error: \(error.message)")
		exit(1)
	}
	catch let error as StrictModeError {
		printError("Parse error: \(error.parseError.code)")
		exit(1)
	}
	catch {
		printError("Error: \(error)")
		exit(1)
	}
}

main()
