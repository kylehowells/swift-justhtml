// extractlinks - Extract all links from HTML
// A minimal CLI tool demonstrating CSS selector queries

import Foundation
import justhtml

func printUsage() {
	let name = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "extractlinks"
	FileHandle.standardError.write(Data("""
	Usage: \(name) [options] [file]
	
	Extract all links from an HTML file.
	
	Arguments:
	  file    HTML file to process (reads from stdin if omitted)
	
	Options:
	  -u, --urls-only    Only print URLs, not link text
	  -h, --help         Show this help message
	
	Examples:
	  \(name) page.html
	  curl -s https://example.com | \(name)
	  \(name) --urls-only page.html
	
	""".utf8))
}

func main() throws {
	var args = Array(CommandLine.arguments.dropFirst())
	var urlsOnly = false

	// Parse flags
	if args.contains("-h") || args.contains("--help") {
		printUsage()
		return
	}

	if args.contains("-u") || args.contains("--urls-only") {
		urlsOnly = true
		args.removeAll { $0 == "-u" || $0 == "--urls-only" }
	}

	// Read HTML from file or stdin
	let html: String
	if let filename = args.first {
		html = try String(contentsOfFile: filename, encoding: .utf8)
	}
	else {
		html = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
	}

	// Parse HTML
	let doc = try JustHTML(html)

	// Find all anchor tags with href attribute
	let links = try doc.query("a[href]")

	// Print each link
	for link in links {
		let href = link.attrs["href"] ?? ""
		let text = link.text.trimmingCharacters(in: .whitespacesAndNewlines)

		if urlsOnly {
			print(href)
		}
		else {
			if text.isEmpty {
				print(href)
			}
			else {
				print("\(text) -> \(href)")
			}
		}
	}
}

do {
	try main()
}
catch {
	FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
	exit(1)
}
