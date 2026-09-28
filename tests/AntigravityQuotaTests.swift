import Foundation

@main enum AntigravityQuotaTests {
    static func main() {
        let plain = Data(#"{"token":{"refresh_token":"fixture-refresh","access_token":"ignored"},"id_token":"fixture-id"}"#.utf8)
        assert(AntigravityQuotaClient.stored(plain)?.refresh == "fixture-refresh")
        assert(AntigravityQuotaClient.stored(Data(("go-keyring-base64:" + plain.base64EncodedString()).utf8))?.id == "fixture-id")
        var d = AntigravityQuotaClient.Dependencies()
        d.home = "/fixture"
        d.command = { _, _ in "" }
        d.exists = { _ in false }
        d.read = { path in assert(path.hasSuffix("jetski-standalone-oauth-token")); return plain }
        d.http = { _ in fatalError("No live HTTP allowed") }
        assert(AntigravityQuotaClient.credential(d)?.refresh == "fixture-refresh")
        d.read = { _ in nil }
        assert(AntigravityQuotaClient.fetchSync(d).kind == .unsigned)
        d.command = { executable, _ in executable.hasSuffix("security") ? String(data: plain, encoding: .utf8)! : "" }
        d.read = { _ in fatalError("Keychain must stop fallback") }
        for (code, body) in [(401, "{}"), (400, #"{"error":"invalid_grant"}"#), (500, "{}")] {
            d.http = { _ in (code, Data(body.utf8)) }
            assert(AntigravityQuotaClient.fetchSync(d).kind == (code == 500 ? .failed : .unsigned))
        }
        var calls = 0
        d.http = { req in
            calls += 1
            if calls == 1 { return (200, Data(#"{"access_token":"fixture-access"}"#.utf8)) }
            assert(req.url!.path.hasSuffix("loadCodeAssist"))
            return (200, Data("{}".utf8))
        }
        assert(AntigravityQuotaClient.fetchSync(d).kind == .failed && calls == 2)
        assert(AntigravityQuotaClient.projectID(["response": ["project": ["id": "p"]]]) == "p")
        let root: [String: Any] = ["response": ["groups": [
            ["displayName": "Claude GPT", "buckets": [["bucketId": "weekly", "remainingFraction": 0.5], ["id": "session", "remainingFraction": 2.0]]],
            ["name": "Gemini", "buckets": [["window": "weekly", "remainingFraction": -1.0], ["bucketId": "5-hour", "remainingFraction": 0.25, "resetTime": "2026-06-01T12:00:00.123Z"], ["bucketId": "session", "remaining": ["remainingFraction": 0.0]], ["bucketId": "weekly", "remainingFraction": Double.nan], ["bucketId": "weekly", "remainingFraction": Double.infinity], ["displayName": "weekly", "remainingFraction": 0.0]]],
        ]]]
        let snapshot = AntigravityQuotaClient.parse(root)
        assert(snapshot.meters.map(\.id) == ["gemini_5h", "gemini_weekly", "claude_gpt_5h", "claude_gpt_weekly"])
        assert(snapshot.meters.map(\.usedPercent) == [75, 100, 0, 50])
        assert(snapshot.meters[0].resetsAt!.timeIntervalSince(snapshot.meters[0].windowStart!) == 18000)
        assert(snapshot.meters[1].resetsAt == nil)
        assert(AntigravityQuotaClient.rfc3339("1700000000") == nil)
        assert(AntigravityQuotaClient.rfc3339("2026-06-01T12:00:00Z") != nil)
        func field(_ n: UInt8, _ data: Data) -> Data {
            assert(data.count < 128)
            return Data([n << 3 | 2, UInt8(data.count)]) + data
        }
        let info = field(3, Data("legacy-refresh".utf8)) + field(5, Data("legacy-id".utf8))
        let row = field(1, Data(info.base64EncodedString().utf8))
        let entry = field(1, Data("oauthTokenInfoSentinelKey".utf8)) + field(2, row)
        let topic = field(1, entry)
        assert(AntigravityQuotaClient.legacy(topic)?.refresh == "legacy-refresh")
        assert(AntigravityQuotaClient.legacy(Data([10, 255])) == nil)
        d.read = { _ in nil }
        d.exists = { path in path.contains("Antigravity IDE") || path.hasSuffix("state.vscdb") }
        d.command = { executable, args in
            if executable.hasSuffix("security") { return "" }
            assert(executable.hasSuffix("sqlite3"))
            assert(args[0] == "-readonly" && args[1].contains("Antigravity IDE/"))
            return topic.base64EncodedString()
        }
        assert(AntigravityQuotaClient.credential(d)?.id == "legacy-id")
        d.exists = { path in !path.contains("Antigravity IDE") && path.hasSuffix("state.vscdb") }
        d.command = { executable, args in
            if executable.hasSuffix("security") { return "" }
            assert(args[1].contains("Antigravity/User/"))
            return topic.base64EncodedString()
        }
        assert(AntigravityQuotaClient.credential(d)?.refresh == "legacy-refresh")
        let summary = Data(#"{"groups":[{"name":"Gemini","buckets":[{"id":"5h","remainingFraction":0.2,"resetTime":12345},{"id":"weekly","remainingFraction":0.9,"resetTime":"2026-06-01T12:00:00Z"}]}]}"#.utf8)
        calls = 0
        d.http = { req in
            calls += 1
            if calls == 1 {
                assert(req.url!.host == "oauth2.googleapis.com")
                assert(req.httpBody.flatMap { String(data: $0, encoding: .utf8) }!.contains("refresh_token=legacy-refresh"))
                return (200, Data(#"{"access_token":"new-access","refresh_token":"rotated-ephemeral"}"#.utf8))
            }
            assert(req.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
            assert(req.value(forHTTPHeaderField: "User-Agent")!.hasPrefix("antigravity/1.20.5 darwin/"))
            if calls == 2 { return (200, Data(#"{"response":{"cloudaicompanionProject":{"projectId":"fixture-project"}}}"#.utf8)) }
            assert(req.url!.host == "daily-cloudcode-pa.googleapis.com")
            let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: String]
            assert(body["project"] == "fixture-project")
            return (200, summary)
        }
        let official = AntigravityQuotaClient.fetchSync(d)
        assert(official.kind == .ready && calls == 3)
        assert(official.meters[0].resetsAt == nil)
        assert(official.meters[1].resetsAt!.timeIntervalSince(official.meters[1].windowStart!) == 604_800)
        d.exists = { _ in false }
        d.command = { executable, _ in
            if executable.hasSuffix("ps") { return "42 /fixture/antigravity/language_server --csrf_token fixture-csrf" }
            if executable.hasSuffix("lsof") { return "n127.0.0.1:12345" }
            return ""
        }
        d.http = { req in
            assert(req.url!.host == "127.0.0.1")
            assert(req.value(forHTTPHeaderField: "x-codeium-csrf-token") == "fixture-csrf")
            return (200, summary)
        }
        assert(AntigravityQuotaClient.fetchSync(d).kind == .ready)
        print("Antigravity fixture tests passed")
    }
}
