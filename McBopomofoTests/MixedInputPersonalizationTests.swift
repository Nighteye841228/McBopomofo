// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import Foundation
import Testing

@testable import McBopomofo

@Suite("Mixed Input Personalization Tests", .serialized)
struct MixedInputPersonalizationTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "MixedInputPersonalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Three explicit English choices reach the English threshold")
    func englishThreshold() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for _ in 0..<2 {
            MixedInputPersonalization.observe(
                rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
                defaults: defaults, now: now)
        }
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)

        MixedInputPersonalization.observe(
            rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
            defaults: defaults, now: now)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now)
                == .english)
    }

    @Test("Three explicit Chinese choices reach the Chinese threshold")
    func chineseThreshold() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for _ in 0..<3 {
            MixedInputPersonalization.observe(
                rawInput: "ru4", boundary: "candidate", selectedEnglish: false,
                defaults: defaults, now: now)
        }
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now)
                == .chinese)
    }

    @Test("Observations expire after thirty days")
    func expiresAfterThirtyDays() {
        let defaults = makeDefaults()
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 2_000_000_000)

        for _ in 0..<3 {
            MixedInputPersonalization.observe(
                rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
                defaults: defaults, now: start)
        }
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults,
                now: start.addingTimeInterval(29 * day)) == .english)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults,
                now: start.addingTimeInterval(30 * day)) == .neutral)
    }

    @Test("Disabled personalization neither reads nor writes")
    func disabled() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        MixedInputPersonalization.observe(
            rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
            defaults: defaults, now: now, enabled: false)
        #expect(defaults.data(forKey: MixedInputPersonalization.dataKey) == nil)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now,
                enabled: false)
                == .neutral)
    }

    @Test("Stored data does not contain the raw token")
    func hashesRawToken() {
        let defaults = makeDefaults()

        MixedInputPersonalization.observe(
            rawInput: "private@example.com", boundary: "candidate", selectedEnglish: true,
            defaults: defaults, now: Date(timeIntervalSince1970: 2_000_000_000))
        let data = defaults.data(forKey: MixedInputPersonalization.dataKey)!
        #expect(!String(decoding: data, as: UTF8.self).contains("private@example.com"))
    }

    @Test("Clock rollback does not revive future observations")
    func clockRollback() {
        let defaults = makeDefaults()
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for _ in 0..<3 {
            MixedInputPersonalization.observe(
                rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
                defaults: defaults, now: now.addingTimeInterval(10 * day))
        }
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)
    }

    @Test("Corrupted storage falls back to neutral")
    func corruptedStorage() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: MixedInputPersonalization.dataKey)
        defaults.set("salt", forKey: MixedInputPersonalization.saltKey)

        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults,
                now: Date(timeIntervalSince1970: 2_000_000_000)) == .neutral)
    }
}
