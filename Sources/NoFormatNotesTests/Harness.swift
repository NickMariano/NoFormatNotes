import Foundation

/// A small test harness: neither XCTest nor swift-testing ships with Command Line Tools, and this
/// project builds without Xcode. Tests run as an ordinary executable, exit 0 on success.
enum Harness {
    nonisolated(unsafe) static var currentScope = ""
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
}

func scope(_ name: String) { Harness.currentScope = name }

func expect(_ condition: Bool, _ detail: @autoclosure () -> String = "",
            file: StaticString = #file, line: UInt = #line) {
    Harness.checks += 1
    guard !condition else { return }
    let suffix = detail().isEmpty ? "" : " (\(detail()))"
    Harness.failures.append("\(Harness.currentScope)\(suffix)\n      at \(file):\(line)")
}

func run(_ cases: [@Sendable () -> Void]) -> Never {
    var names: [String] = []
    for testCase in cases {
        let before = Harness.failures.count
        testCase()
        names.append(Harness.currentScope)
        print("\(Harness.failures.count == before ? "  ok" : "FAIL")  \(Harness.currentScope)")
    }
    print("")
    if Harness.failures.isEmpty {
        print("\(names.count) tests, \(Harness.checks) checks, all passed")
        exit(0)
    }
    print("\(Harness.failures.count) failure(s):")
    Harness.failures.forEach { print("  - \($0)") }
    exit(1)
}
