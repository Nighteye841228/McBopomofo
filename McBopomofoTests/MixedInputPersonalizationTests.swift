// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import CryptoKit
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

        (0..<2).forEach { _ in
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

        (0..<3).forEach { _ in
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

        (0..<3).forEach { _ in
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

        (0..<3).forEach { _ in
            MixedInputPersonalization.observe(
                rawInput: "ru4", boundary: "candidate", selectedEnglish: true,
                defaults: defaults, now: now.addingTimeInterval(10 * day))
        }
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ru4", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)
    }

    private func observeChoices(
        _ choices: [Bool], rawInput: String = "ai", boundary: String = "candidate",
        defaults: UserDefaults, now: Date
    ) {
        choices.forEach { selectedEnglish in
            MixedInputPersonalization.observe(
                rawInput: rawInput, boundary: boundary, selectedEnglish: selectedEnglish,
                defaults: defaults, now: now)
        }
    }

    @Test("Recent explicit corrections can reverse a longstanding preference")
    func recentChoicesReversePreference() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices(Array(repeating: true, count: 100), defaults: defaults, now: now)
        observeChoices([false], defaults: defaults, now: now)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)
        observeChoices([false, false], defaults: defaults, now: now)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now)
                == .chinese)
    }

    @Test("Explicit token choices apply at every supported boundary",
          arguments: ["candidate", "space", "enter", "punctuation"])
    func supportedBoundariesSharePreference(boundary: String) {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: boundary, defaults: defaults, now: now)
                == .english)
    }

    @Test("Unrelated tokens do not inherit a learned preference")
    func unrelatedTokenStaysNeutral() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ji", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)
    }

    @Test("Learned preferences survive a new defaults instance")
    func preferenceSurvivesReload() throws {
        let suite = "MixedInputPersonalizationTests.Reload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: reopened, now: now)
                == .english)
    }

    @Test("Disabling an existing model neither reads nor changes it")
    func disabledExistingModel() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        let savedData = defaults.data(forKey: MixedInputPersonalization.dataKey)
        MixedInputPersonalization.observe(
            rawInput: "ai", boundary: "candidate", selectedEnglish: false,
            defaults: defaults, now: now, enabled: false)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now,
                enabled: false) == .neutral)
        #expect(defaults.data(forKey: MixedInputPersonalization.dataKey) == savedData)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now)
                == .english)
    }

    @Test("Read-only queries do not train the model or create storage")
    func queriesDoNotTrain() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        (0..<10).forEach { _ in
            #expect(
                MixedInputPersonalization.preference(
                    forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now)
                    == .neutral)
        }
        #expect(defaults.data(forKey: MixedInputPersonalization.dataKey) == nil)
        #expect(defaults.string(forKey: MixedInputPersonalization.saltKey) == nil)
    }

    @Test("Reset removes both learned preferences and their salt")
    func resetClearsStorage() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        MixedInputPersonalization.reset(defaults: defaults)
        #expect(defaults.data(forKey: MixedInputPersonalization.dataKey) == nil)
        #expect(defaults.string(forKey: MixedInputPersonalization.saltKey) == nil)
        #expect(
            MixedInputPersonalization.preference(
                forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now)
                == .neutral)
    }

    private func legacyKey(raw: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt)\u{0}\(raw)\u{0}candidate".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func installLegacyStore(
        defaults: UserDefaults, counts: [String: Int], raw: String = "ai"
    ) throws {
        let salt = "migration-test"
        let key = legacyKey(raw: raw, salt: salt)
        let bucket = counts.merging(["day": 23_148]) { first, _ in first }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": [key: [bucket]]])
        defaults.set(salt, forKey: MixedInputPersonalization.saltKey)
        defaults.set(data, forKey: MixedInputPersonalization.dataKey)
    }

    @Test("Existing V1 counts remain readable and can be corrected")
    func legacyStoreMigration() throws {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try installLegacyStore(defaults: defaults, counts: ["englishCount": 100, "chineseCount": 0])
        #expect(MixedInputPersonalization.preference(
            forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now) == .english)
        observeChoices([false, false, false], defaults: defaults, now: now)
        #expect(MixedInputPersonalization.preference(
            forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now) == .chinese)
    }

    @Test("Malformed historical counts cannot overflow learning", arguments: [-1, Int.max])
    func invalidHistoricalCounts(count: Int) throws {
        let defaults = makeDefaults()
        try installLegacyStore(defaults: defaults, counts: ["englishCount": count, "chineseCount": count])
        #expect(MixedInputPersonalization.preference(
            forRawInput: "ai", boundary: "candidate", defaults: defaults,
            now: Date(timeIntervalSince1970: 2_000_000_000)) == .neutral)
    }

    @Test("A full store evicts old tokens while continuing to learn new choices")
    func fullStoreContinuesLearning() throws {
        let defaults = makeDefaults()
        let entries = Dictionary(uniqueKeysWithValues: (0..<2_005).map { index in
            (String(format: "%064x", index), [["day": 23_148, "englishCount": 3, "chineseCount": 0]])
        })
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "entries": entries])
        defaults.set(data, forKey: MixedInputPersonalization.dataKey)
        defaults.set("capacity-test", forKey: MixedInputPersonalization.saltKey)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        observeChoices([true, true, true], defaults: defaults, now: now)
        #expect(MixedInputPersonalization.preference(
            forRawInput: "ai", boundary: "candidate", defaults: defaults, now: now) == .english)
        let stored = try #require(defaults.data(forKey: MixedInputPersonalization.dataKey))
        let decoded = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        let retained = try #require(decoded["entries"] as? [String: Any])
        #expect(retained.count == 2_000)
        #expect(stored.count < 1_048_576)
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

@Suite("Candidate Selection Personalization Tests", .serialized)
struct CandidateSelectionPersonalizationTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CandidateSelectionPersonalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("The latest single-character selection is persistent")
    func latestSelectionWins() {
        let defaults = makeDefaults()
        CandidateSelectionPersonalization.observe(
            reading: "ㄉㄨㄣ", value: "敦", defaults: defaults,
            now: Date(timeIntervalSince1970: 1))
        CandidateSelectionPersonalization.observe(
            reading: "ㄉㄨㄣ", value: "蹲", defaults: defaults,
            now: Date(timeIntervalSince1970: 2))

        #expect(
            CandidateSelectionPersonalization.preferredValue(
                forReading: "ㄉㄨㄣ", defaults: defaults) == "蹲")
        #expect(defaults.data(forKey: CandidateSelectionPersonalization.dataKey) != nil)
    }

    @Test("Phrase and punctuation selections are ignored")
    func ignoresIneligibleSelections() {
        let defaults = makeDefaults()
        CandidateSelectionPersonalization.observe(
            reading: "ㄉㄨㄣ-ㄏㄨㄤˊ", value: "敦煌", defaults: defaults)
        CandidateSelectionPersonalization.observe(
            reading: "_punctuation_>", value: "。", defaults: defaults)

        #expect(defaults.data(forKey: CandidateSelectionPersonalization.dataKey) == nil)
    }

    @Test("Corrupted storage is ignored")
    func corruptedStorage() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: CandidateSelectionPersonalization.dataKey)

        #expect(
            CandidateSelectionPersonalization.preferredValue(
                forReading: "ㄉㄨㄣ", defaults: defaults) == nil)
    }
}
