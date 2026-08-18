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
        let savedKeyboardLayout = Preferences.keyboardLayout
        let savedAssociatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        defer {
            Preferences.mixedInputEnabled = savedMixedInputEnabled
            Preferences.keyboardLayout = savedKeyboardLayout
            Preferences.associatedPhrasesEnabled = savedAssociatedPhrasesEnabled
        }
        Preferences.mixedInputEnabled = true
        Preferences.keyboardLayout = .standard
        Preferences.associatedPhrasesEnabled = false

        let handler = KeyHandler()
        handler.inputMode = .bopomofo
        handler.syncWithPreferences()
        var state: InputState = InputState.Empty()
        var inputError = false
        for key in "ji3vu04y94callsu3" {
            let text = String(key)
            let charCode = text.utf16.first ?? 0
            let input = KeyHandlerInput(
                inputText: text, keyCode: 0, charCode: charCode, flags: [],
                isVerticalMode: false)
            let handled = handler.handle(
                input: input, state: state,
                stateCallback: { state = $0 },
                errorCallback: { inputError = true })
            if !handled || inputError {
                fputs("KeyHandler rejected mixed-input self-check\n", stderr)
                return 11
            }
        }
        guard let inputting = state as? InputState.Inputting,
            inputting.composingBuffer == "我現在call你"
        else {
            let actual = (state as? InputState.Inputting)?.composingBuffer ?? "<not inputting>"
            fputs("Unexpected mixed-input result: \(actual)\n", stderr)
            return 12
        }
        print("McBopomofo local build self-check passed: \(inputting.composingBuffer)")
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
