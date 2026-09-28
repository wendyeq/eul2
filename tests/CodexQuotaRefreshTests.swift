import Darwin
import Foundation

@main enum CodexQuotaRefreshTests {
    static func main() {
        let resets = Date(timeIntervalSince1970: 1_700_000_000)
        let windowStart = resets.addingTimeInterval(-300 * 60)
        let now = resets.addingTimeInterval(-100 * 60)
        let oneMinuteLater = now.addingTimeInterval(QuotaCountdown.displayTick)
        assert(QuotaCountdown.displayTick == 60)
        assert(QuotaCountdown.text(resetsAt: resets, now: now) == "剩 1h 40m")
        assert(QuotaCountdown.text(resetsAt: resets, now: oneMinuteLater) == "剩 1h 39m")
        let elapsedNow = QuotaWindowElapsed.percent(start: windowStart, end: resets, now: now)!
        let elapsedLater = QuotaWindowElapsed.percent(start: windowStart, end: resets, now: oneMinuteLater)!
        assert(elapsedLater > elapsedNow)
        assert(abs((elapsedLater - elapsedNow) - (100.0 / 300.0)) < 0.0001)

        setenv("CODEX_FAKE_MODE", "burst", 1)
        let burstStarted = Date()
        let burst = CodexQuotaClient.fetchSync(requestTimeout: 2)
        let burstElapsed = Date().timeIntervalSince(burstStarted)
        assert(burst.kind == .ready, "burst kind \(burst.kind)")
        assert(burst.meters.count == 1)
        assert(burst.meters[0].labelKey == "quota.codex.primary")
        assert(burst.meters[0].usedPercent == 100)
        assert(burst.meters[0].resetsAt?.timeIntervalSince1970 == 1_700_000_000)
        assert(burstElapsed < 3, "same-read 5h window took \(burstElapsed)s")

        setenv("CODEX_FAKE_MODE", "silent", 1)
        let silentStarted = Date()
        let silent = CodexQuotaClient.fetchSync(requestTimeout: 0.4)
        let silentElapsed = Date().timeIntervalSince(silentStarted)
        assert(silent.kind == .failed && silent.meters.isEmpty, "silent kind \(silent.kind)")
        assert(silentElapsed < 3, "silent codex blocked refresh for \(silentElapsed)s")
    }
}
