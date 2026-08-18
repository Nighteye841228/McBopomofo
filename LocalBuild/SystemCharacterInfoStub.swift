// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import Foundation

public struct CharacterInfo {
    public let character: String?
    public let components: String?
    public let simplifiedExample: String?
    public let traditionalExample: String?
}

public enum SystemCharacterInfoError: Error {
    case notFound
}

public final class SystemCharacterInfo {
    public static let shared: SystemCharacterInfo? = nil

    public func read(string: String) throws -> CharacterInfo {
        throw SystemCharacterInfoError.notFound
    }
}

public struct UnihanEntry {
    public var name = ""
    public var japanese = ""
    public var japaneseKun = ""
    public var japaneseOn = ""
    public var korean = ""
    public var pinyinPrc = ""
    public var pinyinRoc = ""
    public var pinyinPrimary = ""
    public var canjie = ""
    public var canjieKeys = ""
    public var components = ""
    public var phonetic = ""
    public var wubiXing = ""
    public var wubiHua = ""
}

public final class UnihanDictionary {
    public static let shared: UnihanDictionary? = nil

    public func read(string: String) throws -> UnihanEntry {
        throw SystemCharacterInfoError.notFound
    }
}
