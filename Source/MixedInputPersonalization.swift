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

    private struct Store: Codable {
        var version = 1
        var entries: [String: [Bucket]] = [:]
    }

    static let dataKey = "MixedInputPersonalizationDataV1"
    static let saltKey = "MixedInputPersonalizationSaltV1"
    private static let retentionDays = 30

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

        let day = utcDay(for: now)
        var store = loadStore(defaults: defaults)
        prune(store: &store, currentDay: day)
        if defaults.data(forKey: dataKey) != nil {
            save(store: store, defaults: defaults)
        }
        let key = signature(
            rawInput: rawInput, boundary: boundary, defaults: defaults, createSalt: false)
        guard let key, let buckets = store.entries[key] else {
            return .neutral
        }

        let english = buckets.reduce(0) { $0 + $1.englishCount }
        let chinese = buckets.reduce(0) { $0 + $1.chineseCount }
        guard english + chinese >= 3 else {
            return .neutral
        }

        let englishProbability = Double(english + 1) / Double(english + chinese + 2)
        if englishProbability >= 0.8 {
            return .english
        }
        if englishProbability <= 0.2 {
            return .chinese
        }
        return .neutral
    }

    static func observe(
        rawInput: String, boundary: String, selectedEnglish: Bool, defaults: UserDefaults,
        now: Date, enabled: Bool = true
    ) {
        guard enabled else {
            return
        }

        let day = utcDay(for: now)
        var store = loadStore(defaults: defaults)
        prune(store: &store, currentDay: day)
        guard
            let key = signature(
                rawInput: rawInput, boundary: boundary, defaults: defaults, createSalt: true)
        else {
            return
        }

        var buckets = store.entries[key] ?? []
        if let index = buckets.firstIndex(where: { $0.day == day }) {
            if selectedEnglish {
                buckets[index].englishCount += 1
            } else {
                buckets[index].chineseCount += 1
            }
        } else {
            buckets.append(
                Bucket(
                    day: day, englishCount: selectedEnglish ? 1 : 0,
                    chineseCount: selectedEnglish ? 0 : 1))
        }
        store.entries[key] = buckets.sorted { $0.day < $1.day }
        save(store: store, defaults: defaults)
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

    private static func prune(store: inout Store, currentDay: Int) {
        let earliestDay = currentDay - retentionDays + 1
        store.entries = store.entries.reduce(into: [:]) { result, item in
            let buckets = item.value.filter { $0.day >= earliestDay && $0.day <= currentDay }
            if !buckets.isEmpty {
                result[item.key] = buckets
            }
        }
    }

    private static func signature(
        rawInput: String, boundary: String, defaults: UserDefaults, createSalt: Bool
    ) -> String? {
        var salt = defaults.string(forKey: saltKey)
        if salt == nil && createSalt {
            salt = UUID().uuidString
            defaults.set(salt, forKey: saltKey)
        }
        guard let salt else {
            return nil
        }

        let data = Data("\(salt)\u{0}\(rawInput)\u{0}\(boundary)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
