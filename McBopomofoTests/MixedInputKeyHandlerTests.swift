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

    override func setUpWithError() throws {
        savedMixedInputEnabled = Preferences.mixedInputEnabled
        savedKeyboardLayout = Preferences.keyboardLayout
        savedAssociatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
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

    func testAmbiguousFirstToneRollsBackBeforeEnglishToken() {
        sendKeys("ai model ")
        XCTAssertEqual(composingBuffer, "ai model ")
    }

    func testStrongChineseFirstToneRemainsBeforeEnglishToken() {
        sendKeys("g0 dashboard model")
        XCTAssertEqual(composingBuffer, "山dashboard model")
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
