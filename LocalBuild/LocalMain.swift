// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import Cocoa
import InputMethodKit
import InputSourceHelper

@main
enum LocalMain {
    private static let connectionName = "McBopomofo_1_Connection"

    private static func install() -> Int32 {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return 1
        }
        let bundleURL = Bundle.main.bundleURL
        if InputSourceHelper.inputSource(for: bundleID) == nil,
            !InputSourceHelper.registerInputSource(at: bundleURL)
        {
            NSLog("Unable to register input source at \(bundleURL.path)")
            return 2
        }
        guard let inputSource = InputSourceHelper.inputSource(for: bundleID) else {
            return 3
        }
        if !InputSourceHelper.inputSourceEnabled(for: inputSource),
            !InputSourceHelper.enable(inputSource: inputSource)
        {
            return 4
        }
        _ = InputSourceHelper.enableAllInputMode(for: bundleID)
        return 0
    }

    private static func selfCheck() -> Int32 {
        let requiredResources = [
            "data.txt",
            "data-plain-bpmf.txt",
            "associated-phrases-v2.txt",
            "bpmfvs-pua.txt",
            "bpmfvs-variants.txt",
        ]
        for resource in requiredResources {
            guard Bundle.main.url(forResource: resource, withExtension: nil) != nil else {
                fputs("Missing resource: \(resource)\n", stderr)
                return 10
            }
        }
        LanguageModelManager.loadDataModels()
        let savedMixedInputEnabled = Preferences.mixedInputEnabled
        let savedPersonalizationEnabled = Preferences.mixedInputPersonalizationEnabled
        let savedKeyboardLayout = Preferences.keyboardLayout
        let savedAssociatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        let savedSelectPhraseAfterCursor = Preferences.selectPhraseAfterCursorAsCandidate
        let savedMoveCursorAfterSelection = Preferences.moveCursorAfterSelectingCandidate
        let savedCandidateSelectionData = UserDefaults.standard.data(
            forKey: CandidateSelectionPersonalization.dataKey)
        defer {
            Preferences.mixedInputEnabled = savedMixedInputEnabled
            Preferences.mixedInputPersonalizationEnabled = savedPersonalizationEnabled
            Preferences.keyboardLayout = savedKeyboardLayout
            Preferences.associatedPhrasesEnabled = savedAssociatedPhrasesEnabled
            Preferences.selectPhraseAfterCursorAsCandidate = savedSelectPhraseAfterCursor
            Preferences.moveCursorAfterSelectingCandidate = savedMoveCursorAfterSelection
            if let savedCandidateSelectionData {
                UserDefaults.standard.set(
                    savedCandidateSelectionData,
                    forKey: CandidateSelectionPersonalization.dataKey)
            } else {
                CandidateSelectionPersonalization.reset()
            }
        }
        Preferences.mixedInputEnabled = true
        Preferences.mixedInputPersonalizationEnabled = false
        Preferences.keyboardLayout = .standard
        Preferences.associatedPhrasesEnabled = false
        Preferences.selectPhraseAfterCursorAsCandidate = false
        Preferences.moveCursorAfterSelectingCandidate = true
        CandidateSelectionPersonalization.reset()

        func evaluateInputs(_ inputs: [(String, NSEvent.ModifierFlags)]) -> String? {
            let handler = KeyHandler()
            handler.inputMode = .bopomofo
            handler.syncWithPreferences()
            var state: InputState = InputState.Empty()
            var inputError = false
            for (text, flags) in inputs {
                let charCode = text.utf16.first ?? 0
                let input = KeyHandlerInput(
                    inputText: text, keyCode: 0, charCode: charCode, flags: flags,
                    isVerticalMode: false)
                let handled = handler.handle(
                    input: input, state: state,
                    stateCallback: { state = $0 },
                    errorCallback: { inputError = true })
                if !handled || inputError {
                    return nil
                }
            }
            return (state as? InputState.Inputting)?.composingBuffer
        }

        func evaluate(_ keys: String) -> String? {
            evaluateInputs(keys.map { (String($0), NSEvent.ModifierFlags()) })
        }

        let coreInput = "ji3vu04y94callsu3"
        guard evaluate(coreInput) == "我現在call你" else {
            let actual = evaluate(coreInput) ?? "<not inputting>"
            fputs("Unexpected mixed-input result: \(actual)\n", stderr)
            return 12
        }
        let shiftedPrefix = evaluateInputs([
            ("A", .shift), ("g", []), ("k", []), ("4", []),
            ("j", []), ("p", []), ("6", []),
        ])
        let shiftedSuffix = evaluateInputs([
            ("g", []), ("k", []), ("4", []), ("A", .shift),
        ])
        guard shiftedPrefix == "A社文", shiftedSuffix == "社A" else {
            fputs(
                "Shift-letter boundary regression failed: prefix=\(shiftedPrefix ?? "<nil>"), "
                    + "suffix=\(shiftedSuffix ?? "<nil>")\n",
                stderr)
            return 19
        }
        let reportInput = "fu062j0 dashboardm3g6u04y xul4g4rm,6cj84r,u4au04interfaced9 z8 "
        let reportExpected = "前端dashboard與實驗資料視覺化介面interface開發"
        guard evaluate(reportInput) == reportExpected else {
            let actual = evaluate(reportInput) ?? "<not inputting>"
            fputs("Unexpected report sentence result: \(actual)\n", stderr)
            return 13
        }
        guard evaluate("u.3ru.4") == "有就", evaluate(".u3") == "有" else {
            fputs("OU-key regression failed\n", stderr)
            return 15
        }
        guard evaluate("bt4g.org") == "bt4g.org" else {
            let actual = evaluate("bt4g.org") ?? "<not inputting>"
            fputs("Domain ASCII regression failed: \(actual)\n", stderr)
            return 20
        }
        let chinesePriorityCases = [
            ("ru.456ru, ", "就直接"),
            ("e942. ", "概都"),
            ("capsfu, ", "caps切"),
            ("g4tester@example.org", "是tester＠example.org"),
            ("bj4https://api.example.net/v2/status", "入https：//api.example.net/v2/status"),
        ]
        for (input, expected) in chinesePriorityCases {
            guard evaluate(input) == expected else {
                let actual = evaluate(input) ?? "<not inputting>"
                fputs("Chinese-priority regression failed for \(input): \(actual)\n", stderr)
                return 22
            }
        }
        let shiftedPunctuation = evaluateInputs([
            ("s", []), ("u", []), ("3", []), (">", .shift),
        ])
        guard shiftedPunctuation == "你。" else {
            fputs(
                "Shifted punctuation regression failed: \(shiftedPunctuation ?? "<nil>")\n",
                stderr)
            return 23
        }
        let closingQuote = evaluateInputs([
            ("a", []), ("p", []), ("p", []), ("l", []), ("e", []), ("]", []),
        ])
        guard closingQuote == "apple」" else {
            fputs("Closing quote regression failed: \(closingQuote ?? "<nil>")\n", stderr)
            return 24
        }
        CandidateSelectionPersonalization.observe(reading: "ㄉㄨㄣ", value: "蹲")
        guard evaluate("2jp ") == "蹲" else {
            let actual = evaluate("2jp ") ?? "<not inputting>"
            fputs("Candidate personalization regression failed: \(actual)\n", stderr)
            return 25
        }
        CandidateSelectionPersonalization.reset()
        guard evaluate("104293284584") == "辦逮大炸" else {
            let actual = evaluate("104293284584") ?? "<not inputting>"
            fputs("Numeric Bopomofo regression failed: \(actual)\n", stderr)
            return 17
        }
        let spacedEnglish = "hello world "
        let spacedActual = evaluate(spacedEnglish)
        let ambiguousActual = evaluate("ai model ")
        let strongActual = evaluate("g0 dashboard model")
        guard spacedActual == spacedEnglish, ambiguousActual == "ai model ",
            strongActual == "山dashboard model"
        else {
            fputs(
                "Deferred-space regression failed: spaced=\(spacedActual ?? "<nil>"), "
                    + "ambiguous=\(ambiguousActual ?? "<nil>"), "
                    + "strong=\(strongActual ?? "<nil>")\n",
                stderr)
            return 18
        }

        let candidateHandler = KeyHandler()
        candidateHandler.inputMode = .bopomofo
        candidateHandler.syncWithPreferences()
        var candidateState: InputState = InputState.Empty()
        for key in "m3" {
            let text = String(key)
            let input = KeyHandlerInput(
                inputText: text, keyCode: 0, charCode: text.utf16.first ?? 0,
                flags: [], isVerticalMode: false)
            _ = candidateHandler.handle(
                input: input, state: candidateState,
                stateCallback: { candidateState = $0 }, errorCallback: {})
        }
        let down = KeyHandlerInput(
            inputText: " ", keyCode: 125, charCode: 0, flags: [], isVerticalMode: false)
        _ = candidateHandler.handle(
            input: down, state: candidateState,
            stateCallback: { candidateState = $0 }, errorCallback: {})
        guard let choosing = candidateState as? InputState.ChoosingMixedInputCandidate,
            choosing.englishCandidateIndex == 1,
            choosing.candidates.count > 1,
            choosing.candidates[1].value == "m3"
        else {
            fputs("Mixed candidate list did not preserve the original candidates\n", stderr)
            return 14
        }

        let cursorHandler = KeyHandler()
        cursorHandler.inputMode = .bopomofo
        cursorHandler.syncWithPreferences()
        var cursorState: InputState = InputState.Empty()
        for key in "su3cl3" {
            let text = String(key)
            let input = KeyHandlerInput(
                inputText: text, keyCode: 0, charCode: text.utf16.first ?? 0,
                flags: [], isVerticalMode: false)
            _ = cursorHandler.handle(
                input: input, state: cursorState,
                stateCallback: { cursorState = $0 }, errorCallback: {})
        }
        let left = KeyHandlerInput(
            inputText: " ", keyCode: 123, charCode: 0, flags: [], isVerticalMode: false)
        _ = cursorHandler.handle(
            input: left, state: cursorState,
            stateCallback: { cursorState = $0 }, errorCallback: {})
        _ = cursorHandler.handle(
            input: down, state: cursorState,
            stateCallback: { cursorState = $0 }, errorCallback: {})
        guard let cursorChoosing = cursorState as? InputState.ChoosingCandidate,
            let selected = cursorChoosing.candidates.first
        else {
            fputs("Candidate cursor self-check could not open candidates\n", stderr)
            return 21
        }
        cursorHandler.fixNode(
            reading: selected.reading, value: selected.value,
            originalCursorIndex: Int(cursorChoosing.originalCursorIndex),
            useMoveCursorAfterSelectionSetting: true)
        guard let moved = cursorHandler.buildInputtingState() as? InputState.Inputting,
            moved.cursorIndex == 2
        else {
            fputs("Candidate cursor did not move to the next Chinese node\n", stderr)
            return 22
        }
        let carryHandler = KeyHandler()
        carryHandler.inputMode = .bopomofo
        carryHandler.syncWithPreferences()
        let carryInputting = InputState.Inputting(composingBuffer: "與", cursorIndex: 1)
        var carryState: InputState = InputState.AssociatedPhrases(
            previousState: carryInputting, prefixCursorIndex: 0,
            prefixReading: "ㄩˇ", prefixValue: "與", selectedIndex: 0, candidates: [],
            useVerticalMode: false, autoTriggered: true)
        for key in "g0 u " {
            let text = String(key)
            let input = KeyHandlerInput(
                inputText: text, keyCode: 0, charCode: text.utf16.first ?? 0,
                flags: [], isVerticalMode: false)
            _ = carryHandler.handle(
                input: input, state: carryState,
                stateCallback: { carryState = $0 }, errorCallback: {})
        }
        guard let inputting = carryState as? InputState.Inputting,
            inputting.composingBuffer.hasSuffix("山一")
        else {
            let actual =
                (carryState as? InputState.Inputting)?.composingBuffer ?? "<not inputting>"
            fputs("Dismissed candidate left a detached component: \(actual)\n", stderr)
            return 16
        }
        print("McBopomofo local build self-check passed: \(reportExpected)")
        return 0
    }

    static func main() {
        if CommandLine.arguments.dropFirst().first == "--self-check" {
            exit(selfCheck())
        }
        if CommandLine.arguments.dropFirst().first == "install" {
            exit(install())
        }

        Preferences.populateDefaults()
        UserDefaults.standard.set(false, forKey: "CheckUpdateAutomatically")

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        guard let bundleID = Bundle.main.bundleIdentifier,
            let server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
        else {
            NSLog("Unable to initialize IMKServer")
            exit(20)
        }
        withExtendedLifetime(server) {
            application.run()
        }
    }
}
