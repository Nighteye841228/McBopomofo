// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import AppKit
import Testing

@testable import McBopomofo

@Suite("Mixed Input Key Handler Tests", .serialized)
final class MixedInputKeyHandlerTests {
    private var handler = KeyHandler()
    private var state: InputState = InputState.Empty()
    private var committedText = ""
    private var savedMixedInputEnabled = false
    private var savedKeyboardLayout: KeyboardLayout = .standard
    private var savedAssociatedPhrasesEnabled = false
    private var savedPersonalizationEnabled = false
    private var savedPersonalizationData: Data?
    private var savedPersonalizationSalt: String?
    private var savedCandidateSelectionData: Data?

    init() {
        savedPersonalizationEnabled = Preferences.mixedInputPersonalizationEnabled
        savedPersonalizationData = UserDefaults.standard.data(forKey: MixedInputPersonalization.dataKey)
        savedPersonalizationSalt = UserDefaults.standard.string(forKey: MixedInputPersonalization.saltKey)
        MixedInputPersonalization.reset()
        Preferences.mixedInputPersonalizationEnabled = false
        savedMixedInputEnabled = Preferences.mixedInputEnabled
        savedKeyboardLayout = Preferences.keyboardLayout
        savedAssociatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        savedCandidateSelectionData = UserDefaults.standard.data(
            forKey: CandidateSelectionPersonalization.dataKey)
        CandidateSelectionPersonalization.reset()
        Preferences.mixedInputEnabled = true
        Preferences.keyboardLayout = .standard
        Preferences.associatedPhrasesEnabled = false
        LanguageModelManager.loadDataModels()
        handler = KeyHandler()
        handler.inputMode = .bopomofo
        handler.syncWithPreferences()
        state = InputState.Empty()
        committedText = ""
    }

    deinit {
        Preferences.mixedInputPersonalizationEnabled = savedPersonalizationEnabled
        UserDefaults.standard.set(savedPersonalizationData, forKey: MixedInputPersonalization.dataKey)
        UserDefaults.standard.set(savedPersonalizationSalt, forKey: MixedInputPersonalization.saltKey)
        Preferences.mixedInputEnabled = savedMixedInputEnabled
        Preferences.keyboardLayout = savedKeyboardLayout
        Preferences.associatedPhrasesEnabled = savedAssociatedPhrasesEnabled
        if let savedCandidateSelectionData {
            UserDefaults.standard.set(
                savedCandidateSelectionData, forKey: CandidateSelectionPersonalization.dataKey)
        } else {
            CandidateSelectionPersonalization.reset()
        }
    }

    @discardableResult
    private func send(_ text: String, flags: NSEvent.ModifierFlags = []) -> Bool {
        let code = text.unicodeScalars.first.map { UInt16($0.value) } ?? 0
        let input = KeyHandlerInput(
            inputText: text,
            keyCode: 0,
            charCode: code,
            flags: flags,
            isVerticalMode: false)
        return handler.handle(input: input, state: state) { [self] newState in
            if let committing = newState as? InputState.Committing {
                committedText += committing.poppedText
            }
            state = newState
        } errorCallback: {
            Issue.record("Mixed input should not report an input error")
        }
    }

    private func sendKeys(_ keys: String) {
        keys.forEach { key in
            #expect(send(String(key)))
        }
    }

    private func sendShiftedKeys(_ keys: String) {
        keys.forEach { key in
            #expect(send(String(key), flags: .shift))
        }
    }

    @discardableResult
    private func sendOptionEllipsis() -> Bool {
        let input = KeyHandlerInput(
            inputText: "…", keyCode: 41, charCode: 0x2026, flags: .option,
            isVerticalMode: false, inputTextIgnoringModifiers: ";")
        return handler.handle(input: input, state: state) { [self] newState in
            if let committing = newState as? InputState.Committing {
                committedText += committing.poppedText
            }
            state = newState
        } errorCallback: {
            Issue.record("Option-semicolon should not report an input error")
        }
    }

    @discardableResult
    private func sendDown() -> Bool {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        return handler.handle(input: input, state: state) { [self] newState in
            state = newState
        } errorCallback: {
            Issue.record("Opening mixed candidates should not report an input error")
        }
    }

    private var composingBuffer: String {
        (state as? InputState.Inputting)?.composingBuffer ?? ""
    }

    @Test("English phrase survives a following Chinese syllable", arguments: [
        ("apple doctorsu3", "apple doctor你"),
        ("apple doctor su3", "apple doctor 你"),
        ("hello worldsu3cl3", "hello world你好"),
        ("hello world su3cl3", "hello world 你好"),
        ("ai modelsu3cl3", "ai model你好"),
        ("ai model su3cl3", "ai model 你好"),
        ("hello to su3cl3", "hello to 你好"),
        ("apple doctor call su3", "apple doctor call 你"),
        ("ji3apple doctor su3", "我apple doctor 你"),
        ("apple  doctor su3", "apple  doctor 你"),
        ("machine learningsu3", "machine learning你"),
        ("machine learningg0 ", "machine learning山"),
        ("open source su3", "open source 你"),
        ("good morning su3", "good morning 你"),
        ("foo barsu3", "foo bar你"),
        ("visual studio code su3", "visual studio code 你"),
        ("unit testsu3", "unit test你"),
        ("go tosu3", "go to你"),
    ])
    func englishPhraseBeforeChinese(example: (keys: String, expected: String)) {
        sendKeys(example.keys)
        #expect(composingBuffer == example.expected)
        #expect(send("\r"))
        #expect(committedText == example.expected)
        #expect(state is InputState.Empty)
    }

    private func clearComposition() {
        handler.clear()
        state = InputState.Empty()
        committedText = ""
    }

    private func chooseMixedCandidate(useEnglish: Bool) throws {
        #expect(sendDown())
        let choosing = try #require(state as? InputState.ChoosingMixedInputCandidate)
        let chineseIndex = choosing.englishCandidateIndex == 0 ? 1 : 0
        let selected = choosing.candidates[chineseIndex]
        state = handler.applyMixedInputCandidate(useEnglish: useEnglish)
        if !useEnglish {
            handler.fixNode(
                reading: selected.reading, value: selected.value,
                originalCursorIndex: Int(choosing.originalCursorIndex),
                candidateCursorIndex: Int(choosing.candidateCursorIndex),
                useMoveCursorAfterSelectionSetting: true)
            state = handler.buildInputtingState()
        }
    }

    private func trainCandidate(keys: String, useEnglish: Bool) throws {
        clearComposition()
        sendKeys(keys)
        try chooseMixedCandidate(useEnglish: useEnglish)
    }

    @Test("An explicit English correction learns the entire ambiguous word")
    func learnsWholeEnglishWord() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in
            try trainCandidate(keys: "apple ", useEnglish: true)
            #expect(composingBuffer == "apple ")
        }
        #expect(MixedInputPersonalization.preference(forRawInput: "apple", boundary: "candidate") == .english)
        #expect(MixedInputPersonalization.preference(forRawInput: "le", boundary: "candidate") == .neutral)
        clearComposition()
        sendKeys("apple ")
        #expect(composingBuffer == "apple ")
    }

    @Test("A learned English token can be explicitly corrected back to Chinese")
    func learnedEnglishCanBeCorrected() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in
            try trainCandidate(keys: "ru4", useEnglish: true)
        }
        clearComposition()
        sendKeys("ru4")
        #expect(composingBuffer == "ru4")
        try (0..<3).forEach { _ in
            try trainCandidate(keys: "ru4", useEnglish: false)
            #expect(composingBuffer != "ru4")
        }
        #expect(MixedInputPersonalization.preference(forRawInput: "ru4", boundary: "candidate") == .chinese)
        clearComposition()
        sendKeys("ru4")
        #expect(composingBuffer != "ru4")
    }

    @Test("Candidate corrections remain available with learning disabled")
    func disabledLearningDoesNotStoreCorrection() throws {
        try trainCandidate(keys: "apple ", useEnglish: true)
        #expect(composingBuffer == "apple ")
        #expect(UserDefaults.standard.data(forKey: MixedInputPersonalization.dataKey) == nil)
        #expect(UserDefaults.standard.string(forKey: MixedInputPersonalization.saltKey) == nil)
    }

    @Test("Backspace after English phrase preserves earlier spaces")
    func backspaceAtEnglishChineseBoundary() {
        sendKeys("apple doctorsu3")
        #expect(composingBuffer == "apple doctor你")
        #expect(send("\u{8}"))
        #expect(composingBuffer == "apple doctor")
        sendKeys("cl3")
        #expect(composingBuffer == "apple doctor好")
    }

    @Test("Chinese punctuation follows a completed mixed English phrase")
    func punctuationAfterEnglishChineseBoundary() {
        sendKeys("apple doctorsu3")
        #expect(send(">", flags: .shift))
        #expect(composingBuffer == "apple doctor你。")
    }

    @Test("A Chinese first tone remains available after an English phrase")
    func firstToneAfterEnglishPhrase() {
        sendKeys("apple doctorg0 ")
        #expect(composingBuffer == "apple doctor山")
    }

    @Test("Cancelling learned-English candidates preserves text and preference")
    func cancellingLearnedEnglishCandidate() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in try trainCandidate(keys: "ru4", useEnglish: true) }
        clearComposition()
        sendKeys("ru4")
        #expect(sendDown())
        #expect(state is InputState.ChoosingMixedInputCandidate)
        #expect(send("\u{1b}"))
        #expect(composingBuffer == "ru4")
        #expect(MixedInputPersonalization.preference(forRawInput: "ru4", boundary: "candidate") == .english)
    }

    @Test("Deleting a learned token invalidates its old correction span")
    func deletingInvalidatesCorrection() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in try trainCandidate(keys: "ru4", useEnglish: true) }
        clearComposition()
        sendKeys("ru4")
        #expect(send("\u{8}"))
        #expect(composingBuffer == "ru")
        state = handler.applyMixedInputCandidate(useEnglish: false)
        #expect(composingBuffer == "ru")
        #expect(MixedInputPersonalization.preference(forRawInput: "ru4", boundary: "candidate") == .english)
    }

    @Test("A learned first-tone English word can restore Chinese and its cursor")
    func restoreFirstToneChineseFromLearnedWord() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in try trainCandidate(keys: "apple ", useEnglish: true) }
        clearComposition()
        sendKeys("apple ")
        try chooseMixedCandidate(useEnglish: false)
        #expect(composingBuffer == "app高")
        sendKeys("su3")
        #expect(composingBuffer == "app高你")
    }

    @Test("Repeated spaces after an exact Chinese first tone keep the reading")
    func repeatedSpaceAfterChineseFirstTone() {
        sendKeys("g0  su3")
        #expect(composingBuffer == "山 你")
    }

    @Test("Explicit Chinese preference overrides an English phrase context")
    func chinesePreferenceOverridesContext() throws {
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in try trainCandidate(keys: "apple ", useEnglish: false) }
        clearComposition()
        sendKeys("hello world apple ")
        #expect(composingBuffer == "hello world app高")
        sendKeys("doctor")
        #expect(send("\r"))
        #expect(committedText == "hello world app高doctor")
        clearComposition()
        sendKeys("apple  ")
        #expect(composingBuffer == "app高 ")
    }

    @Test("Escape clears pending ASCII according to the composition preference", arguments: [false, true])
    func escapeMixedComposition(clearAll: Bool) {
        let saved = Preferences.escToCleanInputBuffer
        defer { Preferences.escToCleanInputBuffer = saved }
        Preferences.escToCleanInputBuffer = clearAll
        sendKeys("su3call")
        #expect(send("\u{1b}"))
        #expect(composingBuffer == (clearAll ? "" : "你"))
    }

    @Test("Opening candidates finalizes pending English without losing its space")
    func navigationFinalizesEnglishPhrase() throws {
        sendKeys("apple doctor")
        #expect(sendDown())
        let choosing = try #require(state as? InputState.ChoosingCandidate)
        #expect(choosing.composingBuffer == "apple doctor")
        #expect(send("\u{1b}"))
        #expect(composingBuffer == "apple doctor")
    }

    @Test("English-to-Chinese correction respects both candidate cursor modes", arguments: [
        (false, false), (false, true), (true, false), (true, true),
    ])
    func correctingEnglishWithCursorPreferences(settings: (afterCursor: Bool, moveCursor: Bool)) throws {
        let savedAfter = Preferences.selectPhraseAfterCursorAsCandidate
        let savedMove = Preferences.moveCursorAfterSelectingCandidate
        defer {
            Preferences.selectPhraseAfterCursorAsCandidate = savedAfter
            Preferences.moveCursorAfterSelectingCandidate = savedMove
        }
        Preferences.selectPhraseAfterCursorAsCandidate = settings.afterCursor
        Preferences.moveCursorAfterSelectingCandidate = settings.moveCursor
        Preferences.mixedInputPersonalizationEnabled = true
        try (0..<3).forEach { _ in try trainCandidate(keys: "ru4", useEnglish: true) }
        clearComposition()
        sendKeys("ru4")
        try chooseMixedCandidate(useEnglish: false)
        let inputting = try #require(state as? InputState.Inputting)
        #expect(inputting.cursorIndex == 1)
        #expect(composingBuffer.count == 1)
        sendKeys("su3")
        #expect(composingBuffer.hasSuffix("你"))
        #expect(composingBuffer.count == 2)
    }

    @Test
    func testCoreMixedInputExample() {
        sendKeys("ji3vu04y94callsu3")
        #expect(composingBuffer == "我現在call你")
    }

    @Test
    func testSpaceCompletesFirstToneWithoutSelectingCandidate() {
        sendKeys("ji")
        #expect(send(" "))
        #expect(composingBuffer == "窩")
    }

    @Test
    func testNumericAsciiKeepsSpace() {
        sendKeys("123")
        #expect(send(" "))
        #expect(composingBuffer == "123 ")
    }

    @Test
    func testEmailMarkerContinuesInvalidNumericAsciiToken() {
        sendKeys("a3")
        #expect(composingBuffer == "a3")
        #expect(send("@", flags: .shift))
        sendKeys("example.com")
        #expect(composingBuffer == "a3@example.com")
    }

    @Test
    func testEnterDoesNotCompleteFirstTone() {
        sendKeys("ji")
        #expect(send("\r"))
        #expect(committedText == "ji")
        #expect(state is InputState.Empty)
    }

    @Test
    func testEnterFinalizesTwoEnglishWordsUsingFreshState() {
        sendKeys("apple")
        #expect(send(" "))
        #expect(composingBuffer == "app高")
        sendKeys("doctor")
        #expect(composingBuffer == "app高doctor")

        #expect(send("\r"))
        #expect(committedText == "apple doctor")
        #expect(state is InputState.Empty)
    }

    @Test
    func testEnterDoesNotRollbackASingleAmbiguousWord() {
        sendKeys("apple")
        #expect(send(" "))
        #expect(composingBuffer == "app高")

        #expect(send("\r"))
        #expect(committedText == "app高")
        #expect(state is InputState.Empty)
    }

    @Test
    func testShiftLetterStartsUppercaseEnglishSegment() {
        sendKeys("ji3")
        #expect(send("C", flags: .shift))
        #expect(composingBuffer == "我C")
    }

    @Test
    func testShiftLetterStartsIndependentTokenBeforeChinese() {
        #expect(send("A", flags: .shift))
        sendKeys("gk4jp6")
        #expect(composingBuffer == "A社文")
    }

    @Test
    func testShiftLetterAfterChineseDoesNotJoinItsToken() {
        sendKeys("gk4")
        #expect(send("A", flags: .shift))
        #expect(composingBuffer == "社A")
    }

    @Test
    func testConsecutiveShiftLettersDoNotInsertSpaces() {
        #expect(send("A", flags: .shift))
        #expect(send("B", flags: .shift))
        #expect(composingBuffer == "AB")
    }

    @Test
    func testCapsLockLetterUsesTheSameEnglishBoundary() {
        #expect(send("a", flags: .capsLock))
        sendKeys("gk4jp6")
        #expect(composingBuffer == "A社文")
    }

    @Test
    func testBackspaceRemovesDirectShiftLetter() {
        #expect(send("A", flags: .shift))
        #expect(send("\u{8}"))
        #expect(composingBuffer == "")
    }

    @Test
    func testDomainLikeAsciiDoesNotSplitCompletedChinesePrefix() {
        sendKeys("bt4g.org")
        #expect(composingBuffer == "bt4g.org")
    }

    @Test
    func testExactChineseReadingIsNotRolledBackAsDomain() {
        sendKeys("ru.456ru, ")
        #expect(composingBuffer == "就直接")
    }

    @Test
    func testConsecutiveExactChineseReadingsAreNotRolledBackAsDomain() {
        sendKeys("e942. ")
        #expect(composingBuffer == "概都")
    }

    @Test
    func testExactChinesePrefixBeforeEmailUsesChinesePunctuation() {
        sendKeys("g4tester@example.org")
        #expect(composingBuffer == "是tester＠example.org")
    }

    @Test
    func testExactChinesePrefixBeforeUrlUsesChinesePunctuation() {
        sendKeys("bj4https://api.example.net/v2/status")
        #expect(composingBuffer == "入https：//api.example.net/v2/status")
    }

    @Test
    func testBackspaceDeletesPendingAsciiOneCharacterAtATime() {
        sendKeys("call")
        #expect(send("\u{8}"))
        #expect(composingBuffer == "cal")
    }

    @Test
    func testDownArrowShowsChineseAndEnglishAlternatives() {
        sendKeys("ru4")
        #expect(sendDown())
        guard let choosing = state as? InputState.ChoosingMixedInputCandidate else {
            Issue.record("Expected mixed candidate state, got \(state)")
            return
        }
        #expect(choosing.candidates.count > 1)
        #expect(choosing.englishCandidateIndex == 1)
        #expect(choosing.candidates[1].value == "ru4")
    }

    @Test
    func testSelectingEnglishAlternativeKeepsRawInput() {
        sendKeys("ru4")
        #expect(sendDown())
        state = handler.applyMixedInputCandidate(useEnglish: true)
        #expect(composingBuffer == "ru4")
    }

    @Test
    func testSelectingChineseAlternativeMovesToNextReading() {
        let oldMoveCursor = Preferences.moveCursorAfterSelectingCandidate
        let oldSelectAfterCursor = Preferences.selectPhraseAfterCursorAsCandidate
        defer {
            Preferences.moveCursorAfterSelectingCandidate = oldMoveCursor
            Preferences.selectPhraseAfterCursorAsCandidate = oldSelectAfterCursor
        }
        Preferences.moveCursorAfterSelectingCandidate = true
        Preferences.selectPhraseAfterCursorAsCandidate = false

        sendKeys("ru4")
        #expect(sendDown())
        guard let choosing = state as? InputState.ChoosingMixedInputCandidate else {
            Issue.record("Expected mixed candidate state, got \(state)")
            return
        }
        let chineseIndex = choosing.englishCandidateIndex == 0 ? 1 : 0
        let selected = choosing.candidates[chineseIndex]
        handler.applyMixedInputCandidate(useEnglish: false)
        handler.fixNode(
            reading: selected.reading, value: selected.value,
            originalCursorIndex: Int(choosing.originalCursorIndex),
            candidateCursorIndex: Int(choosing.candidateCursorIndex),
            useMoveCursorAfterSelectionSetting: true)
        state = handler.buildInputtingState()

        guard let inputting = state as? InputState.Inputting else {
            Issue.record("Expected inputting state after selection")
            return
        }
        #expect(inputting.cursorIndex == 1)
        sendKeys("gk4")
        #expect(composingBuffer.contains("社"))
    }

    @Test
    func testAcceptsNonCanonicalBopomofoComponentOrder() {
        sendKeys("5;j4")
        #expect(composingBuffer == "狀")
    }

    @Test
    func testOuKeyIsParsedAsBopomofoInsteadOfAsciiPunctuation() {
        sendKeys("u.3ru.4")
        #expect(composingBuffer == "有就")
    }

    @Test
    func testAllNumericBopomofoSyllablesAreNotProtectedAscii() {
        sendKeys("104293284584")
        #expect(composingBuffer == "辦逮大炸")
    }

    @Test
    func testEnglishWordsPreserveLiteralSpaces() {
        sendKeys("hello world ")
        #expect(composingBuffer == "hello world ")
    }

    @Test
    func testEnglishPrefixUsesConsonantLedChineseFirstToneSuffix() {
        sendKeys("capsfu, ")
        #expect(composingBuffer == "caps切")
    }

    @Test
    func testShiftedPeriodUsesChinesePunctuation() {
        sendKeys("su3")
        #expect(send(">", flags: .shift))
        #expect(composingBuffer == "你。")
    }

    @Test
    func testClosingQuoteAfterEnglishUsesChinesePunctuation() {
        sendKeys("apple")
        #expect(send("]"))
        #expect(composingBuffer == "apple」")
    }

    @Test
    func testOptionSemicolonProducesChineseEllipsis() {
        #expect(sendOptionEllipsis())
        #expect(composingBuffer == "……")
    }

    @Test
    func testOptionSemicolonFinalizesPendingEnglish() {
        sendKeys("apple")
        #expect(sendOptionEllipsis())
        #expect(composingBuffer == "apple……")
    }

    @Test
    func testOptionSemicolonAppendsAfterChinese() {
        sendKeys("su3")
        #expect(sendOptionEllipsis())
        #expect(composingBuffer == "你……")
    }

    @Test
    func testUnderscoreKeyBetweenExplicitEnglishSegmentsBecomesLiteral() {
        sendShiftedKeys("RUST")
        #expect(send("_", flags: .shift))
        #expect(composingBuffer == "RUST—")

        sendShiftedKeys("GUI")
        #expect(composingBuffer == "RUST_GUI")
    }

    @Test
    func testUnderscoreKeyBeforeChineseKeepsEmDash() {
        sendShiftedKeys("RUST")
        #expect(send("_", flags: .shift))
        sendKeys("su3")
        #expect(composingBuffer == "RUST—你")
    }

    @Test
    func testUnderscoreKeyAfterChineseKeepsEmDash() {
        sendKeys("su3")
        #expect(send("_", flags: .shift))
        sendShiftedKeys("GUI")
        #expect(composingBuffer == "你—GUI")
    }

    @Test
    func testEnterFinalizesLowercaseIdentifierWithUnderscore() {
        sendKeys("rust")
        #expect(send("_", flags: .shift))
        sendKeys("doctor")
        #expect(composingBuffer == "rust—doctor")

        #expect(send("\r"))
        #expect(committedText == "rust_doctor")
        #expect(state is InputState.Empty)
    }

    @Test
    func testSingleCharacterSelectionBecomesPreferred() {
        sendKeys("2jp ")
        #expect(sendDown())
        guard let choosing = state as? InputState.ChoosingCandidate,
            let selected = choosing.candidates.first(where: { $0.value == "蹲" })
        else {
            Issue.record("Expected 蹲 in the candidate list")
            return
        }

        if state is InputState.ChoosingMixedInputCandidate {
            _ = handler.applyMixedInputCandidate(useEnglish: false)
        }
        handler.fixNode(
            reading: selected.reading, value: selected.value,
            originalCursorIndex: Int(choosing.originalCursorIndex),
            candidateCursorIndex: Int(choosing.candidateCursorIndex),
            useMoveCursorAfterSelectionSetting: false)

        handler.clear()
        state = InputState.Empty()
        sendKeys("2jp ")
        #expect(composingBuffer == "蹲")

        #expect(sendDown())
        guard let reordered = state as? InputState.ChoosingCandidate else {
            Issue.record("Expected candidate state after applying personalization")
            return
        }
        #expect(reordered.candidates.first?.value == "蹲")
    }

    @Test
    func testAmbiguousFirstToneRollsBackBeforeEnglishToken() {
        sendKeys("ai model ")
        #expect(composingBuffer == "ai model ")
    }

    @Test
    func testStrongChineseFirstToneRemainsBeforeEnglishToken() {
        sendKeys("g0 dashboard model ")
        #expect(composingBuffer == "山dashboard model ")
    }

    @Test
    func testEnglishPrefixBeforeChineseFirstToneUsesDeferredSpace() {
        sendKeys("ji3vsvm ru83")
        #expect(composingBuffer == "我vs虛假")
    }

    @Test
    func testSelectingEnglishFirstToneAlternativeRestoresSpace() {
        sendKeys("ai")
        #expect(send(" "))
        #expect(sendDown())
        state = handler.applyMixedInputCandidate(useEnglish: true)
        #expect(composingBuffer == "ai ")
    }

    @Test
    func testSyllableCanStartWithPunctuationPositionKey() {
        sendKeys(".u3")
        #expect(composingBuffer == "有")
    }

    @Test
    func testDismissedAssociatedPhraseDoesNotLeaveFirstComponentBehind() {
        sendKeys("m3")
        guard let inputting = state as? InputState.NotEmpty else {
            Issue.record("Expected inputting state")
            return
        }
        state = InputState.AssociatedPhrases(
            previousState: inputting, prefixCursorIndex: 0, prefixReading: "ㄩˇ",
            prefixValue: inputting.composingBuffer, selectedIndex: 0, candidates: [],
            useVerticalMode: false, autoTriggered: true)
        sendKeys("g0")
        #expect(send(" "))
        sendKeys("u")
        #expect(send(" "))
        #expect(composingBuffer.hasSuffix("山一"), "\(composingBuffer)")
    }

    @Test
    func testReportSentenceRegression() {
        sendKeys("fu062j0 dashboardm3g6u04y xul4g4rm,6cj84r,u4au04interfaced9 z8 ")
        #expect(composingBuffer == "前端dashboard與實驗資料視覺化介面interface開發")
    }
}
