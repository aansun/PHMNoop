// swift-tools-version:5.9
import PackageDescription

// StressSim — a synthetic-data harness that lays the two stress readings side by side.
//
// It invents three days and nights of heart rate, R-R and motion from a KNOWN stress profile (calm day, a stressful day with a
// workout, a poor-sleep day), runs the app's existing stress reading (`DaytimeStress`, with its nightly proxy) and the WHOOP-reference
// reading (`WhoopStress`) over them, and prints how each follows the truth. No health data is read or written.
//
// What it can show: how each method behaves (noise, exercise, categories, calibration sensitivity). What it cannot: how accurate
// either is on a real person, because the generator is this file's own model. Treat it as a behaviour test, not a validation.
let package = Package(
    name: "stresssim",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../Packages/StrandAnalytics"),
        .package(path: "../../Packages/WhoopProtocol"),
    ],
    targets: [
        .executableTarget(name: "stresssim", dependencies: ["StrandAnalytics", "WhoopProtocol"]),
    ]
)
