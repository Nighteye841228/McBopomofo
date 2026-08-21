// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import AppKit
import XCTest

@testable import McBopomofo

final class MixedInputKeyHandlerTests: XCTestCase {
    private var handler = KeyHandler()
    private var state: InputState = InputState.Empty()
    private var committedText = ""
    private var savedMixedInputEnabled = false
    private var savedKeyboardLayout: KeyboardLayout = .standard
    private var savedAssociatedPhrasesEnabled = false
    private var savedCandidateSelectionData: Data?

    override func setUpWithError() throws {
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
        state = InputState.Empty()
        committedText = ""
    }

    override func tearDownWithError() throws {
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
            XCTFail("Mixed input should not report an input error")
        }
    }

    private func sendKeys(_ keys: String) {
        for key in keys {
            XCTAssertTrue(send(String(key)))
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
            XCTFail("Opening mixed candidates should not report an input error")
        }
    }

    private var composingBuffer: String {
        (state as? InputState.Inputting)?.composingBuffer ?? ""
    }

    func testCoreMixedInputExample() {
        sendKeys("ji3vu04y94callsu3")
        XCTAssertEqual(composingBuffer, "我現在call你")
    }

    func testSpaceCompletesFirstToneWithoutSelectingCandidate() {
        sendKeys("ji")
        XCTAssertTrue(send(" "))
        XCTAssertEqual(composingBuffer, "我")
    }

    func testInvalidReadingKeepsAsciiAndSpace() {
        sendKeys("call")
        XCTAssertTrue(send(" "))
        XCTAssertEqual(composingBuffer, "call ")
    }

    func testEmailMarkerReclassifiesEarlierReadingAsAscii() {
        sendKeys("a3")
        XCTAssertNotEqual(composingBuffer, "a3")
        XCTAssertTrue(send("@", flags: .shift))
        sendKeys("example.com")
        XCTAssertEqual(composingBuffer, "a3@example.com")
    }

    func testEnterDoesNotCompleteFirstTone() {
        sendKeys("ji")
        XCTAssertTrue(send("\r"))
        XCTAssertEqual(committedText, "ji")
        XCTAssertTrue(state is InputState.Empty)
    }

    func testShiftLetterStartsUppercaseEnglishSegment() {
        sendKeys("ji3")
        XCTAssertTrue(send("C", flags: .shift))
        XCTAssertEqual(composingBuffer, "我C")
    }

    func testShiftLetterStartsIndependentTokenBeforeChinese() {
        XCTAssertTrue(send("A", flags: .shift))
        sendKeys("gk4jp6")
        XCTAssertEqual(composingBuffer, "A社文")
    }

    func testShiftLetterAfterChineseDoesNotJoinItsToken() {
        sendKeys("gk4")
        XCTAssertTrue(send("A", flags: .shift))
        XCTAssertEqual(composingBuffer, "射A")
    }

    func testConsecutiveShiftLettersDoNotInsertSpaces() {
        XCTAssertTrue(send("A", flags: .shift))
        XCTAssertTrue(send("B", flags: .shift))
        XCTAssertEqual(composingBuffer, "AB")
    }

    func testCapsLockLetterUsesTheSameEnglishBoundary() {
        XCTAssertTrue(send("a", flags: .capsLock))
        sendKeys("gk4jp6")
        XCTAssertEqual(composingBuffer, "A社文")
    }

    func testBackspaceRemovesDirectShiftLetter() {
        XCTAssertTrue(send("A", flags: .shift))
        XCTAssertTrue(send("\u{8}"))
        XCTAssertEqual(composingBuffer, "")
    }

    func testDomainLikeAsciiDoesNotSplitCompletedChinesePrefix() {
        sendKeys("bt4g.org")
        XCTAssertEqual(composingBuffer, "bt4g.org")
    }

    func testExactChineseReadingIsNotRolledBackAsDomain() {
        sendKeys("ru.456ru, ")
        XCTAssertEqual(composingBuffer, "就直接")
    }

    func testConsecutiveExactChineseReadingsAreNotRolledBackAsDomain() {
        sendKeys("e942. ")
        XCTAssertEqual(composingBuffer, "概都")
    }

    func testExactChinesePrefixBeforeEmailUsesChinesePunctuation() {
        sendKeys("g4tester@example.org")
        XCTAssertEqual(composingBuffer, "是tester＠example.org")
    }

    func testExactChinesePrefixBeforeUrlUsesChinesePunctuation() {
        sendKeys("bj4https://api.example.net/v2/status")
        XCTAssertEqual(composingBuffer, "入https：//api.example.net/v2/status")
    }

    func testBackspaceDeletesPendingAsciiOneCharacterAtATime() {
        sendKeys("call")
        XCTAssertTrue(send("\u{8}"))
        XCTAssertEqual(composingBuffer, "cal")
    }

    func testDownArrowShowsChineseAndEnglishAlternatives() {
        sendKeys("a3")
        XCTAssertTrue(sendDown())
        guard let choosing = state as? InputState.ChoosingMixedInputCandidate else {
            return XCTFail("Expected mixed candidate state, got \(state)")
        }
        XCTAssertGreaterThan(choosing.candidates.count, 1)
        XCTAssertEqual(choosing.englishCandidateIndex, 1)
        XCTAssertEqual(choosing.candidates[1].value, "a3")
    }

    func testSelectingEnglishAlternativeKeepsRawInput() {
        sendKeys("a3")
        XCTAssertTrue(sendDown())
        state = handler.applyMixedInputCandidate(useEnglish: true)
        XCTAssertEqual(composingBuffer, "a3")
    }

    func testSelectingChineseAlternativeMovesToNextReading() {
        let oldMoveCursor = Preferences.moveCursorAfterSelectingCandidate
        let oldSelectAfterCursor = Preferences.selectPhraseAfterCursorAsCandidate
        defer {
            Preferences.moveCursorAfterSelectingCandidate = oldMoveCursor
            Preferences.selectPhraseAfterCursorAsCandidate = oldSelectAfterCursor
        }
        Preferences.moveCursorAfterSelectingCandidate = true
        Preferences.selectPhraseAfterCursorAsCandidate = false

        sendKeys("a3")
        XCTAssertTrue(sendDown())
        guard let choosing = state as? InputState.ChoosingMixedInputCandidate else {
            return XCTFail("Expected mixed candidate state, got \(state)")
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
            return XCTFail("Expected inputting state after selection")
        }
        XCTAssertEqual(inputting.cursorIndex, 1)
        XCTAssertTrue(send("gk4"))
        XCTAssertTrue(composingBuffer.contains("射"))
    }

    func testAcceptsNonCanonicalBopomofoComponentOrder() {
        sendKeys("5;j4")
        XCTAssertEqual(composingBuffer, "撞")
    }

    func testOuKeyIsParsedAsBopomofoInsteadOfAsciiPunctuation() {
        sendKeys("u.3ru.4")
        XCTAssertEqual(composingBuffer, "有就")
    }

    func testAllNumericBopomofoSyllablesAreNotProtectedAscii() {
        sendKeys("104293284584")
        XCTAssertEqual(composingBuffer, "辦逮大炸")
    }

    func testEnglishWordsPreserveLiteralSpaces() {
        sendKeys("hello world ")
        XCTAssertEqual(composingBuffer, "hello world ")
    }

    func testEnglishPrefixUsesConsonantLedChineseFirstToneSuffix() {
        sendKeys("capsfu, ")
        XCTAssertEqual(composingBuffer, "caps切")
    }

    func testShiftedPeriodUsesChinesePunctuation() {
        sendKeys("su3")
        XCTAssertTrue(send(">", flags: .shift))
        XCTAssertEqual(composingBuffer, "你。")
    }

    func testClosingQuoteAfterEnglishUsesChinesePunctuation() {
        sendKeys("apple")
        XCTAssertTrue(send("]"))
        XCTAssertEqual(composingBuffer, "apple」")
    }

    func testSingleCharacterSelectionBecomesPreferred() {
        sendKeys("2jp ")
        XCTAssertTrue(sendDown())
        guard let choosing = state as? InputState.ChoosingCandidate,
            let selected = choosing.candidates.first(where: { $0.value == "蹲" })
        else {
            return XCTFail("Expected 蹲 in the candidate list")
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
        XCTAssertEqual(composingBuffer, "蹲")

        XCTAssertTrue(sendDown())
        guard let reordered = state as? InputState.ChoosingCandidate else {
            return XCTFail("Expected candidate state after applying personalization")
        }
        XCTAssertEqual(reordered.candidates.first?.value, "蹲")
    }

    func testAmbiguousFirstToneRollsBackBeforeEnglishToken() {
        sendKeys("ai model ")
        XCTAssertEqual(composingBuffer, "ai model ")
    }

    func testStrongChineseFirstToneRemainsBeforeEnglishToken() {
        sendKeys("g0 dashboard model ")
        XCTAssertEqual(composingBuffer, "山dashboard model ")
    }

    func testEnglishPrefixBeforeChineseFirstToneUsesDeferredSpace() {
        sendKeys("ji3vsvm ru83")
        XCTAssertEqual(composingBuffer, "我vs虛假")
    }

    func testSelectingEnglishFirstToneAlternativeRestoresSpace() {
        sendKeys("ai")
        XCTAssertTrue(send(" "))
        XCTAssertTrue(sendDown())
        state = handler.applyMixedInputCandidate(useEnglish: true)
        XCTAssertEqual(composingBuffer, "ai ")
    }

    func testSyllableCanStartWithPunctuationPositionKey() {
        sendKeys(".u3")
        XCTAssertEqual(composingBuffer, "有")
    }

    func testDismissedAssociatedPhraseDoesNotLeaveFirstComponentBehind() {
        sendKeys("m3")
        guard let inputting = state as? InputState.NotEmpty else {
            return XCTFail("Expected inputting state")
        }
        state = InputState.AssociatedPhrases(
            previousState: inputting, prefixCursorIndex: 0, prefixReading: "ㄩˇ",
            prefixValue: inputting.composingBuffer, selectedIndex: 0, candidates: [],
            useVerticalMode: false, autoTriggered: true)
        sendKeys("g0")
        XCTAssertTrue(send(" "))
        sendKeys("u")
        XCTAssertTrue(send(" "))
        XCTAssertTrue(composingBuffer.hasSuffix("山一"), composingBuffer)
    }

    func testReportSentenceRegression() {
        sendKeys("fu062j0 dashboardm3g6u04y xul4g4rm,6cj84r,u4au04interfaced9 z8 ")
        XCTAssertEqual(composingBuffer, "前端dashboard與實驗資料視覺化介面interface開發")
    }
}
