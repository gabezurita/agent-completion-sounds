import Foundation

struct QuotaPoolRank: Equatable {
    let id: String
    let name: String
    let headroom: Int
    let weeklyPercent: Int
    /// 5-hour percent when it was part of the score. Nil when the pool has no 5-hour bucket, or that bucket was ignored.
    let countedFiveHourPercent: Int?
    /// True when a healthy week caused an imminent 5-hour dip to be left out of the score.
    let fiveHourIgnored: Bool
    let longWindowReset: Date?
    /// "week" for a weekly bucket, "cycle" for Cursor's billing cycle.
    let primaryLabel: String
}

enum QuotaPoolSuggestion {
    static let imminentFiveHour: TimeInterval = 30 * 60
    /// Matches the menu warning line: at or below this percent is a warning.
    static let warningAtOrBelow = 40

    static func rank(providers: [String: Any], now: Date) -> [QuotaPoolRank] {
        return collect(providers: providers).compactMap { score($0, now: now) }.sorted(by: higherRank)
    }

    static func menuLine(for rank: QuotaPoolRank) -> String {
        var parts = ["Use \(rank.name)", "\(rank.primaryLabel) \(rank.weeklyPercent)%"]
        if let five = rank.countedFiveHourPercent {
            parts.append("5h \(five)%")
        } else if rank.fiveHourIgnored {
            parts.append("5h resets soon")
        }
        return parts.joined(separator: " · ")
    }

    private struct Window {
        let percent: Int
        let reset: Date?
    }

    private struct Candidate {
        let id: String
        let name: String
        let weekly: Window
        let fiveHour: Window?
        let primaryLabel: String
    }

    private static func collect(providers: [String: Any]) -> [Candidate] {
        var pools: [Candidate] = []

        if let agy = providers["antigravity"] as? [String: Any],
           agy["status"] as? String == "ok",
           let buckets = agy["buckets"] as? [String: Any] {
            if let weekly = window(from: buckets["gemini_weekly"]) {
                pools.append(Candidate(
                    id: "agy-gemini",
                    name: "Antigravity Gemini",
                    weekly: weekly,
                    fiveHour: window(from: buckets["gemini_5h"]),
                    primaryLabel: "week"
                ))
            }
            if let weekly = window(from: buckets["3p_weekly"]) {
                pools.append(Candidate(
                    id: "agy-claude-gpt",
                    name: "Antigravity Claude & GPT",
                    weekly: weekly,
                    fiveHour: window(from: buckets["3p_5h"]),
                    primaryLabel: "week"
                ))
            }
            if let weekly = window(from: buckets["gemini_argon_wtu_weekly"]) {
                pools.append(Candidate(
                    id: "agy-argon",
                    name: "Antigravity Argon",
                    weekly: weekly,
                    fiveHour: nil,
                    primaryLabel: "week"
                ))
            }
        }

        if let codex = providers["codex"] as? [String: Any],
           codex["status"] as? String == "ok",
           let limits = codex["rate_limits"] as? [String: Any],
           let weekly = window(from: limits["weekly"]) {
            pools.append(Candidate(
                id: "codex",
                name: "Codex",
                weekly: weekly,
                fiveHour: window(from: limits["five_hour"]),
                primaryLabel: "week"
            ))
        }

        if let claude = providers["claude"] as? [String: Any],
           claude["status"] as? String == "ok" {
            let claudeProfiles: [[String: Any]]
            if let list = claude["profiles"] as? [[String: Any]], !list.isEmpty {
                claudeProfiles = list
            } else {
                claudeProfiles = [claude]
            }
            for (index, prof) in claudeProfiles.enumerated() {
                guard let limits = prof["rate_limits"] as? [String: Any],
                      let weekly = window(from: limits["weekly"]) else {
                    continue
                }
                let rawId = (prof["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let poolId: String
                if rawId.isEmpty || rawId == "default" {
                    poolId = index == 0 ? "claude" : "claude-\(index)"
                } else {
                    poolId = "claude-\(rawId)"
                }
                let rawPlan = (prof["plan"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let poolName = rawPlan.isEmpty ? "Claude Code" : rawPlan
                pools.append(Candidate(
                    id: poolId,
                    name: poolName,
                    weekly: weekly,
                    fiveHour: window(from: limits["five_hour"]),
                    primaryLabel: "week"
                ))
            }
        }

        if let cursor = measuredCursor(providers["cursor"]) {
            pools.append(cursor)
        }

        return pools
    }

    /// A 100% Cursor bar with no recorded use matches both a full cycle and the collector's synthesized fallback.
    private static func measuredCursor(_ value: Any?) -> Candidate? {
        guard let cursor = value as? [String: Any],
              cursor["status"] as? String == "ok",
              let models = cursor["models"] as? [String: Any],
              let fast = models["cursor_models"] as? [String: Any],
              let remaining = percent(fast["remaining_percent"]) else {
            return nil
        }
        let used = percent(fast["used_percent"]) ?? 0
        if remaining == 100 && used == 0 {
            return nil
        }
        return Candidate(
            id: "cursor-fast",
            name: "Cursor Fast Models",
            weekly: Window(percent: remaining, reset: parseReset(cursor["billing_cycle_end"])),
            fiveHour: nil,
            primaryLabel: "cycle"
        )
    }

    private static func score(_ candidate: Candidate, now: Date) -> QuotaPoolRank? {
        let weekly = candidate.weekly.percent
        let countedFive: Int?
        let ignored: Bool
        let headroom: Int

        if let five = candidate.fiveHour {
            let imminent = isImminent(five.reset, now: now) && weekly > warningAtOrBelow && five.percent < weekly
            if imminent {
                headroom = weekly
                countedFive = nil
                ignored = true
            } else {
                headroom = min(weekly, five.percent)
                countedFive = five.percent
                ignored = false
            }
        } else {
            ignored = false
            headroom = weekly
            countedFive = nil
        }

        guard headroom > 0 else { return nil }

        return QuotaPoolRank(
            id: candidate.id,
            name: candidate.name,
            headroom: headroom,
            weeklyPercent: weekly,
            countedFiveHourPercent: countedFive,
            fiveHourIgnored: ignored,
            longWindowReset: candidate.weekly.reset,
            primaryLabel: candidate.primaryLabel
        )
    }

    private static func higherRank(_ lhs: QuotaPoolRank, _ rhs: QuotaPoolRank) -> Bool {
        if lhs.headroom != rhs.headroom {
            return lhs.headroom > rhs.headroom
        }
        switch (lhs.longWindowReset, rhs.longWindowReset) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    private static func isImminent(_ reset: Date?, now: Date) -> Bool {
        guard let reset = reset else { return false }
        let remaining = reset.timeIntervalSince(now)
        return remaining >= 0 && remaining <= imminentFiveHour
    }

    private static func window(from value: Any?) -> Window? {
        guard let bucket = value as? [String: Any],
              let remaining = percent(bucket["remaining_percent"]) else {
            return nil
        }
        return Window(percent: remaining, reset: parseReset(bucket["reset_time"]))
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return Int(number.doubleValue.rounded())
    }

    private static let internetFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseReset(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let date = internetFractional.date(from: trimmed) { return date }
        if let date = internet.date(from: trimmed) { return date }
        let stripped = trimmed.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        if stripped != trimmed {
            return internet.date(from: stripped)
        }
        return nil
    }
}

// MARK: - Model Advisor Task Picks (Coding & Reasoning)

struct ModelAdvisorPick: Equatable {
    let category: String
    let label: String
    let modelId: String
    let modelName: String
    let tool: String
    let effort: String
    let quotaLabel: String
}

enum ModelAdvisorPicks {
    private static let featuredOrder: [(key: String, label: String)] = [
        ("coding", "Coding"),
        ("reasoning", "Reasoning"),
    ]

    static func parse(jsonData: Data) -> [ModelAdvisorPick] {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
              let tiers = root["tiers"] as? [[String: Any]] else {
            return []
        }

        var byCategory: [String: [String: Any]] = [:]
        for tier in tiers {
            if let key = tier["task_category"] as? String,
               let top = tier["top"] as? [String: Any] {
                byCategory[key] = top
            }
        }

        var picks: [ModelAdvisorPick] = []
        for entry in featuredOrder {
            guard let top = byCategory[entry.key],
                  let modelId = top["id"] as? String, !modelId.isEmpty,
                  let modelName = top["name"] as? String, !modelName.isEmpty,
                  let tool = top["tool"] as? String, !tool.isEmpty else {
                continue
            }
            let effort = (top["effort"] as? String) ?? "medium"
            let quotaDict = top["quota"] as? [String: Any]
            let quotaLabel = (quotaDict?["label"] as? String) ?? ""
            picks.append(ModelAdvisorPick(
                category: entry.key,
                label: entry.label,
                modelId: modelId,
                modelName: modelName,
                tool: tool,
                effort: effort,
                quotaLabel: quotaLabel
            ))
        }
        return picks
    }

    static func menuLine(for pick: ModelAdvisorPick) -> String {
        var line = "\(pick.label): \(pick.modelName) (\(pick.tool) · \(pick.effort))"
        if !pick.quotaLabel.isEmpty && pick.quotaLabel != "n/a" {
            line += " · \(pick.quotaLabel)"
        }
        return line
    }
}
