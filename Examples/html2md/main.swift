// html2md - Convert HTML to Markdown
// A minimal CLI tool demonstrating the toMarkdown() API

import Foundation
import swift_justhtml

func printUsage() {
	let name = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "html2md"
	FileHandle.standardError.write(Data("""
	Usage: \(name) [file]
	
	Convert HTML to Markdown.
	
	Arguments:
	  file    HTML file to convert (reads from stdin if omitted)
	
	Examples:
	  \(name) page.html
	  curl -s https://example.com | \(name)
	  echo '<p>Hello <strong>World</strong></p>' | \(name)
	
	""".utf8))
}

func main() throws {
	let args = Array(CommandLine.arguments.dropFirst())

	// Check for help flag
	if args.contains("-h") || args.contains("--help") {
		printUsage()
		return
	}

	// Read HTML from file or stdin
	let html: String
	if let filename = args.first {
		html = try String(contentsOfFile: filename, encoding: .utf8)
	}
	else {
		html = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
	}

	// Parse and convert to Markdown
	let doc = try JustHTML(html)
	let markdown = doc.toMarkdown()

	print(markdown)
}

do {
	try main()
}
catch {
	FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
	exit(1)
}
