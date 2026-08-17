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

    func testBackspaceDeletesPendingAsciiOneCharacterAtATime() {
        sendKeys("call")
        XCTAssertTrue(send("\u{8}"))
        XCTAssertEqual(composingBuffer, "cal")
    }
}
