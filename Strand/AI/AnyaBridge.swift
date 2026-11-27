import Foundation

/// Test wiring for a debug build in the Simulator: `--anya-bridge http://127.0.0.1:8787` sends the Anthropic provider to the bridge on this
/// Mac (`Tools/anya-bridge/bridge.py`), which answers through the `claude` command. It exists in no other build, and it accepts only an
/// address on the machine itself, so nothing can be pointed elsewhere with it. While it is on, no key is needed and data access counts as
/// given for that launch: what the Simulator holds is demo data. Neither choice is saved.
enum AnyaBridge {
    static var url: URL? {
        #if DEBUG && targetEnvironment(simulator)
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--anya-bridge"), i + 1 < args.count, let url = URL(string: args[i + 1]),
              url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") else { return nil }
        return url
        #else
        return nil
        #endif
    }

    static var isActive: Bool { url != nil }
}
