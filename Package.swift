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
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "swift-justhtml",
			targets: ["swift-justhtml"]
		),
		.library(
			name: "JustHTML",
			targets: ["swift-justhtml"]
		),
		.executable(
			name: "benchmark",
			targets: ["Benchmark"]
		),
		.executable(
			name: "htmltool",
			targets: ["HTMLTool"]
		),
		.executable(
			name: "html2md",
			targets: ["HTML2MD"]
		),
		.executable(
			name: "extractlinks",
			targets: ["ExtractLinks"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "swift-justhtml"
		),
		.executableTarget(
			name: "Benchmark",
			dependencies: ["swift-justhtml"],
			path: "Benchmarks/Sources"
		),
		.executableTarget(
			name: "HTMLTool",
			dependencies: ["swift-justhtml"],
			path: "Examples/htmltool"
		),
		.executableTarget(
			name: "HTML2MD",
			dependencies: ["swift-justhtml"],
			path: "Examples/html2md"
		),
		.executableTarget(
			name: "ExtractLinks",
			dependencies: ["swift-justhtml"],
			path: "Examples/extractlinks"
		),
		.testTarget(
			name: "swift-justhtmlTests",
			dependencies: ["swift-justhtml"],
			resources: [
				.copy("html5lib-tests"),
			]
		),
	]
)
