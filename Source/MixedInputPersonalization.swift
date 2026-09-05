// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import CryptoKit
import Foundation

@objc enum MixedInputPreference: Int {
    case neutral
    case chinese
    case english
}

@objc(MixedInputPersonalization)
final class MixedInputPersonalization: NSObject {
    private struct Bucket: Codable, Equatable {
        var day: Int
        var englishCount: Int
        var chineseCount: Int
    }

    private struct Choice: Codable {
        var day: Int
        var english: Bool
    }

    private struct Store: Codable {
        var version = 1
        var entries: [String: [Bucket]] = [:]
        // Optional to preserve preferences saved before recent-choice learning.
        var recentChoices: [String: [Choice]]?
    }

    static let dataKey = "MixedInputPersonalizationDataV1"
    static let saltKey = "MixedInputPersonalizationSaltV1"
    private static let retentionDays = 30
    private static let capacity = 2_000

    @objc(preferenceForRawInput:boundary:)
    static func preference(forRawInput rawInput: String, boundary: String) -> MixedInputPreference {
        preference(
            forRawInput: rawInput, boundary: boundary, defaults: .standard, now: Date(),
            enabled: Preferences.mixedInputPersonalizationEnabled)
    }

    @objc(observeRawInput:boundary:selectedEnglish:)
    static func observe(rawInput: String, boundary: String, selectedEnglish: Bool) {
        observe(
            rawInput: rawInput, boundary: boundary, selectedEnglish: selectedEnglish,
            defaults: .standard, now: Date(),
            enabled: Preferences.mixedInputPersonalizationEnabled)
    }

    static func preference(
        forRawInput rawInput: String, boundary: String, defaults: UserDefaults, now: Date,
        enabled: Bool = true
    ) -> MixedInputPreference {
        guard enabled else {
            return .neutral
        }

        let store = prunedStore(defaults: defaults, currentDay: utcDay(for: now))
        let key = signature(
            rawInput: rawInput, boundary: boundary, defaults: defaults, createSalt: false)
        return storedPreference(store: store, key: key)
    }

    private static func prunedStore(defaults: UserDefaults, currentDay: Int) -> Store {
        let store = pruned(
            store: loadStore(defaults: defaults), currentDay: currentDay,
            retentionDays: retentionDays)
        if defaults.data(forKey: dataKey) != nil {
            save(store: store, defaults: defaults)
        }
        return store
    }

    private static func storedPreference(store: Store, key: String?) -> MixedInputPreference {
        guard let key else { return .neutral }
        return tokenPreference(store: store, key: key)
    }

    private static func tokenPreference(store: Store, key: String) -> MixedInputPreference {
        if let choices = store.recentChoices?[key] {
            return recentPreference(choices: choices)
        }
        return historicalPreference(buckets: store.entries[key] ?? [])
    }

    private static func recentPreference(choices: [Choice]) -> MixedInputPreference {
        guard choices.count >= 3 else { return .neutral }
        let englishCount = choices.suffix(3).filter(\.english).count
        return [0: MixedInputPreference.chinese, 3: .english][englishCount] ?? .neutral
    }

    private static func historicalPreference(buckets: [Bucket]) -> MixedInputPreference {
        let valid = buckets.filter(validHistoricalBucket)
        let english = valid.reduce(0.0) { $0 + Double($1.englishCount) }
        let chinese = valid.reduce(0.0) { $0 + Double($1.chineseCount) }
        guard english + chinese >= 3 else { return .neutral }
        let probability = (english + 1) / (english + chinese + 2)
        return probabilityPreference(englishProbability: probability)
    }

    private static func validHistoricalBucket(_ bucket: Bucket) -> Bool {
        let validCount = 0...1_000_000
        return validCount.contains(bucket.englishCount) && validCount.contains(bucket.chineseCount)
    }

    private static func probabilityPreference(englishProbability: Double) -> MixedInputPreference {
        if englishProbability >= 0.8 { return .english }
        return chineseProbabilityPreference(englishProbability: englishProbability)
    }

    private static func chineseProbabilityPreference(
        englishProbability: Double
    ) -> MixedInputPreference {
        englishProbability <= 0.2 ? .chinese : .neutral
    }

    static func observe(
        rawInput: String, boundary: String, selectedEnglish: Bool, defaults: UserDefaults,
        now: Date, enabled: Bool = true
    ) {
        guard enabled else {
            return
        }

        let key = signature(
            rawInput: rawInput, boundary: boundary, defaults: defaults, createSalt: true)
        recordChoice(key: key, selectedEnglish: selectedEnglish, defaults: defaults, now: now)
    }

    private static func recordChoice(
        key: String?, selectedEnglish: Bool, defaults: UserDefaults, now: Date
    ) {
        guard let key else { return }
        let day = utcDay(for: now)
        let store = pruned(
            store: loadStore(defaults: defaults), currentDay: day,
            retentionDays: retentionDays)
        let updated = recording(
            choice: Choice(day: day, english: selectedEnglish), key: key, store: store)
        save(store: limited(store: updated, preserving: key, capacity: capacity), defaults: defaults)
    }

    private static func limited(store: Store, preserving key: String, capacity: Int) -> Store {
        let recentKeys = store.entries.keys.filter { $0 != key }.sorted { lhs, rhs in
            (latestDay(store: store, key: lhs), lhs) > (latestDay(store: store, key: rhs), rhs)
        }.prefix(capacity - 1)
        let retained = Set(recentKeys).union([key])
        var result = store
        result.entries = store.entries.filter { retained.contains($0.key) }
        result.recentChoices = store.recentChoices?.filter { retained.contains($0.key) }
        return result
    }

    private static func latestDay(store: Store, key: String) -> Int {
        store.entries[key]?.map(\.day).max() ?? Int.min
    }

    private static func recording(choice: Choice, key: String, store: Store) -> Store {
        // Only explicit candidate choices enter this window. Three consistent
        // corrections can replace an old habit without reinforcing predictions.
        let previousChoices = store.recentChoices?[key] ?? []
        var recent = store.recentChoices ?? [:]
        recent[key] = Array((previousChoices + [choice]).suffix(3))
        var updated = store
        updated.recentChoices = recent
        updated.entries[key] = [Bucket(day: choice.day, englishCount: 0, chineseCount: 0)]
        return updated
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dataKey)
        defaults.removeObject(forKey: saltKey)
    }

    private static func utcDay(for date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    private static func loadStore(defaults: UserDefaults) -> Store {
        guard let data = defaults.data(forKey: dataKey),
            let store = try? JSONDecoder().decode(Store.self, from: data), store.version == 1
        else {
            return Store()
        }
        return store
    }

    private static func save(store: Store, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(store), data.count <= 1_048_576 else {
            return
        }
        defaults.set(data, forKey: dataKey)
    }

    private static func pruned(store: Store, currentDay: Int, retentionDays: Int) -> Store {
        let validDays = (currentDay - retentionDays + 1)...currentDay
        var updated = store
        updated.entries = store.entries.mapValues { buckets in
            buckets.filter { validDays.contains($0.day) }
        }.filter { !$0.value.isEmpty }
        updated.recentChoices = store.recentChoices?.mapValues { choices in
            choices.filter { validDays.contains($0.day) }
        }.filter { !$0.value.isEmpty }
        return updated
    }

    private static func normalizedBoundary(_ boundary: String) -> String {
        let sharedBoundaries = ["candidate", "space", "enter", "punctuation"]
        return sharedBoundaries.contains(boundary) ? "candidate" : boundary
    }

    private static func signature(
        rawInput: String, boundary: String, defaults: UserDefaults, createSalt: Bool
    ) -> String? {
        salt(defaults: defaults, create: createSalt).map { salt in
            hashedSignature(rawInput: rawInput, boundary: normalizedBoundary(boundary), salt: salt)
        }
    }

    private static func hashedSignature(rawInput: String, boundary: String, salt: String) -> String {
        let data = Data("\(salt)\u{0}\(rawInput)\u{0}\(boundary)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func salt(defaults: UserDefaults, create: Bool) -> String? {
        if let existing = defaults.string(forKey: saltKey) {
            return existing
        }
        return createSalt(defaults: defaults, enabled: create)
    }

    private static func createSalt(defaults: UserDefaults, enabled: Bool) -> String? {
        guard enabled else { return nil }
        let salt = UUID().uuidString
        defaults.set(salt, forKey: saltKey)
        return salt
    }

}

@objc(CandidateSelectionPersonalization)
final class CandidateSelectionPersonalization: NSObject {
    private struct Entry: Codable, Equatable {
        var value: String
        var timestamp: TimeInterval
    }

    private struct Store: Codable {
        var version = 1
        var entries: [String: Entry] = [:]
    }

    static let dataKey = "CandidateSelectionPersonalizationDataV1"
    private static let capacity = 500

    @objc(preferredValueForReading:)
    static func preferredValue(forReading reading: String) -> String? {
        preferredValue(forReading: reading, defaults: .standard)
    }

    @objc(observeReading:value:)
    static func observe(reading: String, value: String) {
        observe(reading: reading, value: value, defaults: .standard, now: Date())
    }

    static func preferredValue(forReading reading: String, defaults: UserDefaults) -> String? {
        guard isEligible(reading: reading) else {
            return nil
        }
        return loadStore(defaults: defaults).entries[reading]?.value
    }

    static func observe(
        reading: String, value: String, defaults: UserDefaults, now: Date = Date()
    ) {
        guard isEligible(reading: reading), value.count == 1 else {
            return
        }

        var store = loadStore(defaults: defaults)
        store.entries[reading] = Entry(value: value, timestamp: now.timeIntervalSince1970)
        if store.entries.count > capacity {
            let overflow = store.entries.count - capacity
            let oldestReadings = store.entries.sorted { lhs, rhs in
                if lhs.value.timestamp == rhs.value.timestamp {
                    return lhs.key < rhs.key
                }
                return lhs.value.timestamp < rhs.value.timestamp
            }.prefix(overflow).map(\.key)
            for oldReading in oldestReadings {
                store.entries.removeValue(forKey: oldReading)
            }
        }
        save(store: store, defaults: defaults)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dataKey)
    }

    private static func isEligible(reading: String) -> Bool {
        !reading.isEmpty && !reading.hasPrefix("_") && !reading.contains("-")
    }

    private static func loadStore(defaults: UserDefaults) -> Store {
        guard let data = defaults.data(forKey: dataKey),
            let store = try? JSONDecoder().decode(Store.self, from: data), store.version == 1
        else {
            return Store()
        }
        return store
    }

    private static func save(store: Store, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(store), data.count <= 1_048_576 else {
            return
        }
        defaults.set(data, forKey: dataKey)
    }
}
