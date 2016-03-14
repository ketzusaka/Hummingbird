import PackageDescription

let package = Package(
	name: "Hummingbird",
    dependencies: [
        .Package(url: "https://github.com/ketzusaka/Strand", majorVersion: 1)
    ]
)

// with the new swiftpm we have to force it to create a static lib so that we can use it
// from xcode. this will become unnecessary once official xcode+swiftpm support is done.
// watch progress: https://github.com/apple/swift-package-manager/compare/xcodeproj?expand=1
// Thanks to czechboy0 & the Vapor project for this

let lib = Product(name: "Hummingbird", type: .Library(.Dynamic), modules: "Hummingbird")
products.append(lib)
