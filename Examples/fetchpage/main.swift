// fetchpage - Fetch and query HTML from URLs
// A jsoup-style CLI tool demonstrating fetch + CSS selector queries
//
// This example replicates the jsoup Java example:
//   Document doc = Jsoup.connect("https://en.wikipedia.org/").get();
//   log(doc.title());
//   Elements newsHeadlines = doc.select("#mp-itn b a");
//   for (Element headline : newsHeadlines) {
//     log("%s\n\t%s", headline.attr("title"), headline.absUrl("href"));
//   }

import Foundation
#if canImport(FoundationNetworking)
	import FoundationNetworking
#endif
import justhtml

func printUsage() {
	let name = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "fetchpage"
	FileHandle.standardError.write(Data("""
	Usage: \(name) <url> [selector]
	
	Fetch HTML from a URL and query elements using CSS selectors.
	
	Arguments:
	  url       URL to fetch HTML from
	  selector  CSS selector to query (default: prints page title)
	
	Options:
	  -t, --title      Also print page title before results
	  -a, --attr NAME  Print attribute value instead of text
	  -h, --help       Show this help message
	
	Examples:
	  \(name) https://en.wikipedia.org/
	  \(name) https://en.wikipedia.org/ "#mp-itn b a"
	  \(name) https://en.wikipedia.org/ "#mp-itn b a" --attr title
	  \(name) https://example.com "a[href]" --attr href
	
	""".utf8))
}

/// Resolve a relative URL against a base URL
func resolveURL(_ href: String, base: URL) -> String {
	// Already absolute
	if href.hasPrefix("http://") || href.hasPrefix("https://") || href.hasPrefix("//") {
		if href.hasPrefix("//") {
			return (base.scheme ?? "https") + ":" + href
		}
		return href
	}

	// Use URL resolution
	if let resolved = URL(string: href, relativeTo: base) {
		return resolved.absoluteString
	}

	return href
}

// MARK: - FetchResult

/// Container for URL session result to avoid concurrency issues
final class FetchResult: @unchecked Sendable {
	var data: Data? = nil
	var response: URLResponse? = nil
	var error: Error? = nil
}

/// Fetch HTML content from a URL synchronously
func fetchHTML(from urlString: String) throws -> (String, URL) {
	guard let url = URL(string: urlString) else {
		throw NSError(domain: "fetchpage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
	}

	var request = URLRequest(url: url)
	request.timeoutInterval = 30

	let semaphore = DispatchSemaphore(value: 0)
	let result = FetchResult()

	let task = URLSession.shared.dataTask(with: request) { data, response, error in
		result.data = data
		result.response = response
		result.error = error
		semaphore.signal()
	}
	task.resume()
	semaphore.wait()

	if let error = result.error {
		throw error
	}

	guard let data = result.data else {
		throw NSError(domain: "fetchpage", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"])
	}

	guard let httpResponse = result.response as? HTTPURLResponse else {
		throw NSError(domain: "fetchpage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not an HTTP response"])
	}

	guard (200 ... 299).contains(httpResponse.statusCode) else {
		throw NSError(
			domain: "fetchpage", code: 3,
			userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
	}

	// Determine encoding from Content-Type header, default to UTF-8
	var encoding = String.Encoding.utf8
	if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
	   contentType.lowercased().contains("charset=iso-8859-1")
	{
		encoding = .isoLatin1
	}

	guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
		throw NSError(domain: "fetchpage", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not decode response as text"])
	}

	// Return final URL (after redirects)
	let finalURL = httpResponse.url ?? url
	return (html, finalURL)
}

/// Get the page title from a document
func getTitle(_ doc: JustHTML) -> String? {
	guard let titleElement = try? doc.query("title").first else {
		return nil
	}

	return titleElement.toText().trimmingCharacters(in: .whitespacesAndNewlines)
}

func main() throws {
	var args = Array(CommandLine.arguments.dropFirst())
	var showTitle = false
	var attrName: String?

	// Parse flags
	if args.isEmpty || args.contains("-h") || args.contains("--help") {
		printUsage()
		return
	}

	if args.contains("-t") || args.contains("--title") {
		showTitle = true
		args.removeAll { $0 == "-t" || $0 == "--title" }
	}

	if let attrIndex = args.firstIndex(of: "-a") ?? args.firstIndex(of: "--attr") {
		if attrIndex + 1 < args.count {
			attrName = args[attrIndex + 1]
			args.remove(at: attrIndex + 1)
			args.remove(at: attrIndex)
		}
		else {
			FileHandle.standardError.write(Data("Error: --attr requires an attribute name\n".utf8))
			exit(1)
		}
	}

	guard let urlString = args.first else {
		FileHandle.standardError.write(Data("Error: URL required\n".utf8))
		printUsage()
		exit(1)
	}

	let selector = args.count > 1 ? args[1] : nil

	// Fetch the page
	let (html, baseURL) = try fetchHTML(from: urlString)

	// Parse HTML
	let doc = try JustHTML(html)

	// Print title if requested or if no selector provided
	if showTitle || selector == nil {
		if let title = getTitle(doc) {
			print("Title: \(title)")
		}
	}

	// If no selector, we're done (just showing title)
	guard let selector else {
		return
	}

	// Query for elements
	let elements = try doc.query(selector)

	if elements.isEmpty {
		FileHandle.standardError.write(Data("No elements matched selector: \(selector)\n".utf8))
		return
	}

	// Print each matching element
	for element in elements {
		if let attrName {
			// Print specific attribute value (with URL resolution for href/src)
			if let value = element.attrs[attrName] {
				if attrName == "href" || attrName == "src" || attrName == "action" {
					// Resolve relative URLs like jsoup's absUrl()
					print(resolveURL(value, base: baseURL))
				}
				else {
					print(value)
				}
			}
		}
		else {
			// Print text content and href (jsoup-style output)
			let text = element.toText().trimmingCharacters(in: .whitespacesAndNewlines)
			if let href = element.attrs["href"] {
				let absURL = resolveURL(href, base: baseURL)
				if text.isEmpty {
					print(absURL)
				}
				else {
					print("\(text)")
					print("\t\(absURL)")
				}
			}
			else if let title = element.attrs["title"] {
				if text.isEmpty {
					print(title)
				}
				else {
					print("\(text) (\(title))")
				}
			}
			else {
				print(text)
			}
		}
	}
}

do {
	try main()
}
catch {
	FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
	exit(1)
}
