import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let day: TimeInterval = 86_400
let hour: TimeInterval = 3_600
let minute: TimeInterval = 60

func resetString(_ interval: TimeInterval, now: Date, style: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    var text = formatter.string(from: now.addingTimeInterval(interval))
    if style == "z" && text.hasSuffix("+00:00") {
        text = String(text.dropLast(6)) + "Z"
    }
    if style == "offset" || style == "fraction" {
        if text.hasSuffix("Z") {
            text = String(text.dropLast()) + "+00:00"
        }
    }
    if style == "fraction" {
        text = text.replacingOccurrences(of: "+00:00", with: ".717000+00:00")
    }
    return text
}

func bucket(_ percent: Int, _ reset: String) -> [String: Any] {
    return ["remaining_percent": percent, "reset_time": reset]
}

func snapshotProviders(now: Date) -> [String: Any] {
    return [
        "cursor": [
            "status": "ok",
            "reset_countdown": "6d 22h",
            "billing_cycle_end": resetString(6 * day + 22 * hour, now: now, style: "fraction"),
            "models": [
                "cursor_models": [
                    "remaining_percent": 100,
                    "used_percent": 0,
                ],
            ],
        ],
        "antigravity": [
            "status": "ok",
            "buckets": [
                "gemini_weekly": bucket(21, resetString(2 * day + 6 * hour, now: now, style: "z")),
                "gemini_5h": bucket(92, resetString(3 * hour + 11 * minute, now: now, style: "z")),
                "3p_weekly": bucket(100, resetString(6 * day + 23 * hour, now: now, style: "z")),
                "3p_5h": bucket(100, resetString(4 * hour + 59 * minute, now: now, style: "z")),
                "gemini_argon_wtu_weekly": bucket(0, resetString(4 * day + 6 * hour, now: now, style: "z")),
            ],
        ],
        "codex": [
            "status": "ok",
            "rate_limits": [
                "weekly": bucket(78, resetString(5 * day + 17 * hour, now: now, style: "offset")),
                "five_hour": bucket(77, resetString(8 * minute, now: now, style: "offset")),
            ],
        ],
        "openrouter": [
            "status": "ok",
            "remaining_usd": 9.99,
            "models": ["credits": ["remaining_percent": 100]],
        ],
        "claude": ["status": "ok", "total_sessions": 10],
        "copilot": ["status": "ok", "total_sessions": 4],
        "opencode": ["status": "ok", "total_sessions": 1],
    ]
}

func testOctoberSnapshot() {
    let now = Date(timeIntervalSince1970: 1_761_868_800)
    let ranks = QuotaPoolSuggestion.rank(providers: snapshotProviders(now: now), now: now)
    expect(ranks.map(\.id) == ["agy-claude-gpt", "codex", "agy-gemini"], "snapshot order \(ranks.map(\.id))")

    let top = ranks[0]
    expect(top.name == "Antigravity Claude & GPT", "top name \(top.name)")
    expect(top.headroom == 100, "top headroom \(top.headroom)")
    expect(top.weeklyPercent == 100, "top week \(top.weeklyPercent)")
    expect(top.countedFiveHourPercent == 100, "top 5h \(String(describing: top.countedFiveHourPercent))")
    expect(
        QuotaPoolSuggestion.menuLine(for: top) == "Use Antigravity Claude & GPT · week 100% · 5h 100%",
        "menu line \(QuotaPoolSuggestion.menuLine(for: top))"
    )

    let codex = ranks[1]
    expect(codex.headroom == 78, "codex headroom \(codex.headroom)")
    expect(codex.countedFiveHourPercent == nil, "codex 5h should be ignored")
    expect(codex.fiveHourIgnored, "codex 5h ignore flag")
    expect(
        QuotaPoolSuggestion.menuLine(for: codex) == "Use Codex · week 78% · 5h resets soon",
        "codex line \(QuotaPoolSuggestion.menuLine(for: codex))"
    )

    let gemini = ranks[2]
    expect(gemini.headroom == 21, "gemini headroom \(gemini.headroom)")
    expect(gemini.countedFiveHourPercent == 92, "gemini keeps the 5h percent")
    expect(ranks.contains { $0.id == "agy-argon" } == false, "argon at 0% stays out")
    expect(ranks.contains { $0.id == "cursor-fast" } == false, "ambiguous cursor 100% stays out")
    expect(ranks.contains { $0.id == "openrouter" } == false, "openrouter stays out")
}

func dualWindow(week: Int, five: Int, fiveIn: TimeInterval, weekIn: TimeInterval = 5 * day, now: Date) -> [String: Any] {
    return [
        "codex": [
            "status": "ok",
            "rate_limits": [
                "weekly": bucket(week, resetString(weekIn, now: now, style: "offset")),
                "five_hour": bucket(five, resetString(fiveIn, now: now, style: "offset")),
            ],
        ],
    ]
}

func testImminentFiveHourRules() {
    let now = Date(timeIntervalSince1970: 1_761_868_800)

    let ignored = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 41, five: 10, fiveIn: 10 * minute, now: now),
        now: now
    )
    expect(ignored.first?.headroom == 41, "healthy week ignores an imminent 5h dip")
    expect(ignored.first?.fiveHourIgnored == true, "ignore flag on healthy imminent dip")

    let exact = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 80, five: 10, fiveIn: QuotaPoolSuggestion.imminentFiveHour, now: now),
        now: now
    )
    expect(exact.first?.headroom == 80, "a reset at exactly 30 minutes still counts as soon")

    let outside = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 80, five: 10, fiveIn: QuotaPoolSuggestion.imminentFiveHour + 1, now: now),
        now: now
    )
    expect(outside.first?.headroom == 10, "one second past 30 minutes keeps the 5h percent")

    let warningLine = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: QuotaPoolSuggestion.warningAtOrBelow, five: 10, fiveIn: 10 * minute, now: now),
        now: now
    )
    expect(warningLine.first?.headroom == 10, "40% is still a warning, so the 5h percent counts")

    let unhealthy = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 21, five: 10, fiveIn: 5 * minute, now: now),
        now: now
    )
    expect(unhealthy.first?.headroom == 10, "a short week does not ignore a low 5h bucket")

    let higherFive = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 70, five: 90, fiveIn: 8 * minute, now: now),
        now: now
    )
    expect(higherFive.first?.headroom == 70, "a higher 5h bucket does not raise the week")
    expect(higherFive.first?.fiveHourIgnored == false, "a higher 5h bucket is still shown")
    expect(higherFive.first?.countedFiveHourPercent == 90, "a higher 5h percent stays visible")

    let fractional = QuotaPoolSuggestion.rank(
        providers: [
            "codex": [
                "status": "ok",
                "rate_limits": [
                    "weekly": bucket(80, resetString(5 * day, now: now, style: "offset")),
                    "five_hour": bucket(10, resetString(8 * minute, now: now, style: "fraction")),
                ],
            ],
        ],
        now: now
    )
    expect(fractional.first?.headroom == 80, "a fractional-second reset still counts as soon")
}

func testZeroAndTies() {
    let now = Date(timeIntervalSince1970: 1_761_868_800)
    let emptyFive = QuotaPoolSuggestion.rank(
        providers: dualWindow(week: 90, five: 0, fiveIn: 2 * hour, now: now),
        now: now
    )
    expect(emptyFive.isEmpty, "a 0% 5h bucket that is not about to reset drops the pool")

    let soon = QuotaPoolSuggestion.rank(
        providers: [
            "antigravity": [
                "status": "ok",
                "buckets": [
                    "gemini_weekly": bucket(50, resetString(3 * day, now: now, style: "z")),
                    "gemini_5h": bucket(90, resetString(2 * hour, now: now, style: "z")),
                    "3p_weekly": bucket(50, resetString(1 * day, now: now, style: "z")),
                    "3p_5h": bucket(90, resetString(2 * hour, now: now, style: "z")),
                ],
            ],
        ],
        now: now
    )
    expect(soon.map(\.id) == ["agy-claude-gpt", "agy-gemini"], "equal headroom prefers the earlier weekly reset")
}

func testMeasuredCursor() {
    let now = Date(timeIntervalSince1970: 1_761_868_800)
    let ranks = QuotaPoolSuggestion.rank(
        providers: [
            "cursor": [
                "status": "ok",
                "billing_cycle_end": resetString(6 * day, now: now, style: "fraction"),
                "models": [
                    "cursor_models": [
                        "remaining_percent": 75,
                        "used_percent": 25,
                    ],
                ],
            ],
        ],
        now: now
    )
    expect(ranks.map(\.id) == ["cursor-fast"], "measured cursor joins the rank")
    expect(ranks.first?.headroom == 75, "cursor headroom is its cycle percent")
    expect(
        QuotaPoolSuggestion.menuLine(for: ranks[0]) == "Use Cursor Fast Models · cycle 75%",
        "cursor line \(QuotaPoolSuggestion.menuLine(for: ranks[0]))"
    )

    let offline = QuotaPoolSuggestion.rank(
        providers: ["codex": ["status": "error", "rate_limits": ["weekly": bucket(90, resetString(day, now: now, style: "offset"))]]],
        now: now
    )
    expect(offline.isEmpty, "a provider that is not ok stays out")
}

@main
struct QuotaPoolSuggestionTest {
    static func main() {
        testOctoberSnapshot()
        testImminentFiveHourRules()
        testZeroAndTies()
        testMeasuredCursor()
        print("PASS: quota pool suggestion")
    }
}
