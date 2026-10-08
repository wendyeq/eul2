import Darwin
import Foundation

// App-only helpers; the production sampling and ownership code stays unchanged.
func Print(_: Any...) {}
extension String {
    func localized() -> String { self }
}

@main
enum AppleSiliconIOReportMemoryTests {
    static func peakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            fatalError("getrusage failed")
        }
        return Int64(usage.ru_maxrss)
    }

    static func main() {
        let report = AppleSiliconIOReport.shared
        for _ in 0..<10 {
            autoreleasepool { report.refreshIfNeeded() }
        }
        guard report.isReady else {
            fputs("FAIL: IOReport unavailable; run on Apple Silicon with hardware access\n", stderr)
            exit(2)
        }
        let before = peakResidentBytes()
        for _ in 0..<200 {
            autoreleasepool { report.refreshIfNeeded() }
        }
        let growth = peakResidentBytes() - before
        print(String(format: "200 hardware refreshes: peak RSS growth %.2f MiB", Double(growth) / 1_048_576))
        // The old ownership declarations leaked ~33 MiB per 100 refreshes.
        // Leave room for allocator warmup, but reject linear sample accumulation.
        guard growth < 8 * 1_048_576 else {
            fputs("FAIL: hardware sampling retained more than 8 MiB\n", stderr)
            exit(1)
        }
        print("PASS: IOReport sampling memory stays bounded")
    }
}
