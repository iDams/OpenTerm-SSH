// swift-tools-version: 5.9
import PackageDescription
import Foundation

let coreXCFrameworkPath = "../../dist/OpenTermCore.xcframework"
let appleOpenSSLVersion = "3.6.1"
let appleLibSSHVersion = "0.11.3"

let packageRootCandidates = [
    URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("platforms/macos")
]

func resolveCoreXCFrameworkPath() -> String? {
    let candidates = [
        packageRootCandidates[0].appendingPathComponent(coreXCFrameworkPath),
        packageRootCandidates[1].appendingPathComponent("dist/OpenTermCore.xcframework"),
        packageRootCandidates[2].appendingPathComponent(coreXCFrameworkPath)
    ]

    for candidate in candidates {
        let path = candidate.standardizedFileURL.path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    return nil
}

let packageRootDirectory = packageRootCandidates.first {
    FileManager.default.fileExists(atPath: $0.appendingPathComponent("Sources").standardizedFileURL.path)
}?.standardizedFileURL.path ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
let repoRootDirectory = URL(fileURLWithPath: packageRootDirectory).deletingLastPathComponent().deletingLastPathComponent().path
let coreXCFrameworkAbsolutePath = resolveCoreXCFrameworkPath()
let appleOpenSSLLibraryDirectory = "\(repoRootDirectory)/vendor/apple/openssl/\(appleOpenSSLVersion)/macos-arm64/lib"
let appleLibSSHLibraryDirectory = "\(repoRootDirectory)/vendor/apple/libssh/\(appleLibSSHVersion)/macos-arm64/lib"

let linkerFlags = [
    "-L", appleOpenSSLLibraryDirectory,
    "-L", appleLibSSHLibraryDirectory
]

guard coreXCFrameworkAbsolutePath != nil else {
    fatalError(
        """
        Missing \(coreXCFrameworkPath).
        Generate it first with `./scripts/build_apple_xcframework.sh` or use `./scripts/build_macos_app.sh` from the repo root.
        """
    )
}

guard FileManager.default.fileExists(atPath: appleOpenSSLLibraryDirectory) else {
    fatalError(
        """
        Missing Apple OpenSSL artifacts at \(appleOpenSSLLibraryDirectory).
        Generate them first with `./scripts/build_apple_openssl.sh`.
        """
    )
}

guard FileManager.default.fileExists(atPath: appleLibSSHLibraryDirectory) else {
    fatalError(
        """
        Missing Apple libssh artifacts at \(appleLibSSHLibraryDirectory).
        Generate them first with `./scripts/build_apple_libssh.sh`.
        """
    )
}

let package = Package(
    name: "OpenTerm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenTerm", targets: ["OpenTerm"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "OpenTermCore",
            path: coreXCFrameworkPath
        ),
        .executableTarget(
            name: "OpenTerm",
            dependencies: [
                "OpenTermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("crypto"),
                .linkedLibrary("ssl"),
                .linkedLibrary("ssh"),
                .unsafeFlags(linkerFlags)
            ]
        )
    ]
)
