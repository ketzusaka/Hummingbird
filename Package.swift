import PackageDescription

let package = Package(
	name: "Hummingbird",
    dependencies: [
        .Package(url: "https://github.com/ketzusaka/Strand.git", majorVersion: 1, minor: 4),
        .Package(url: "https://github.com/open-swift/C7.git", majorVersion: 0, minor: 8)
    ]
)
