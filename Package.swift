// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "swift-justhtml",
	platforms: [
		.macOS(.v13),
		.iOS(.v16),
		.tvOS(.v16),
		.watchOS(.v9),
		.visionOS(.v1),
	],
	products: [
		.library(
			name: "justhtml",
			targets: ["justhtml"]
		),
		.executable(
			name: "htmltool",
			targets: ["HTMLTool"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "justhtml",
			path: "Sources/swift-justhtml"
		),
		.executableTarget(
			name: "Benchmark",
			dependencies: ["justhtml"],
			path: "Benchmarks/Sources"
		),
		.executableTarget(
			name: "HTMLTool",
			dependencies: ["justhtml"],
			path: "Examples/htmltool"
		),
		.executableTarget(
			name: "HTML2MD",
			dependencies: ["justhtml"],
			path: "Examples/html2md"
		),
		.executableTarget(
			name: "ExtractLinks",
			dependencies: ["justhtml"],
			path: "Examples/extractlinks"
		),
		.executableTarget(
			name: "FetchPage",
			dependencies: ["justhtml"],
			path: "Examples/fetchpage"
		),
		.testTarget(
			name: "swift-justhtmlTests",
			dependencies: ["justhtml"],
			resources: [
				.copy("html5lib-tests"),
			]
		),
	]
)
