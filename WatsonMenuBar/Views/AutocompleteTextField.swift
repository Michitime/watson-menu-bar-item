import AppKit
import SwiftUI

struct AutocompleteTextField: NSViewRepresentable {
    enum CompletionMode {
        case wholeField
        case delimitedToken
    }

    @Binding var text: String

    let placeholder: String
    let candidates: [String]
    let isEnabled: Bool
    let completionMode: CompletionMode
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.bezelStyle = .roundedBezel
        textField.isBordered = true
        textField.drawsBackground = true
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        textField.focusRingType = .default
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}

extension AutocompleteTextField {
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutocompleteTextField

        init(parent: AutocompleteTextField) {
            self.parent = parent
        }

        func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
            parent.isEnabled
        }

        func controlTextDidChange(_ notification: Notification) {
            guard parent.isEnabled else {
                return
            }

            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard parent.isEnabled else {
                return true
            }

            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                return complete(control: control, textView: textView)
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                submit(control: control, textView: textView)
                return true
            default:
                return false
            }
        }

        private func complete(control: NSControl, textView: NSTextView) -> Bool {
            let currentText = textView.string
            let selectedRange = textView.selectedRange()
            let completion: CompletionResult?

            switch parent.completionMode {
            case .wholeField:
                completion = completeWholeField(currentText)
            case .delimitedToken:
                completion = completeDelimitedToken(in: currentText, selectedRange: selectedRange)
            }

            guard let completion, completion.text != currentText else {
                return true
            }

            updateControl(control, text: completion.text)
            textView.string = completion.text
            parent.text = completion.text
            textView.setSelectedRange(completion.selectedRange)

            return true
        }

        private func completeWholeField(_ text: String) -> CompletionResult? {
            let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let match = bestMatch(for: prefix) else {
                return nil
            }

            return CompletionResult(
                text: match,
                selectedRange: NSRange(location: (match as NSString).length, length: 0)
            )
        }

        private func completeDelimitedToken(in text: String, selectedRange: NSRange) -> CompletionResult? {
            let nsText = text as NSString
            let boundedLocation = min(selectedRange.location, nsText.length)
            let boundedEnd = min(selectedRange.location + selectedRange.length, nsText.length)
            let tokenStart = tokenStartLocation(in: text, before: boundedLocation)
            let tokenEnd = tokenEndLocation(in: text, after: boundedEnd)
            let prefixRange = NSRange(location: tokenStart, length: boundedLocation - tokenStart)
            let prefix = nsText.substring(with: prefixRange)

            guard let match = bestMatch(for: prefix) else {
                return nil
            }

            let tokenRange = NSRange(location: tokenStart, length: tokenEnd - tokenStart)
            let completedText = nsText.replacingCharacters(in: tokenRange, with: match)
            let selectedLocation = tokenStart + (match as NSString).length

            return CompletionResult(
                text: completedText,
                selectedRange: NSRange(location: selectedLocation, length: 0)
            )
        }

        private func bestMatch(for prefix: String) -> String? {
            let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedPrefix.isEmpty else {
                return nil
            }

            return parent.candidates
                .enumerated()
                .filter { _, candidate in
                    candidate.range(
                        of: trimmedPrefix,
                        options: [.anchored, .caseInsensitive]
                    ) != nil
                }
                .sorted { lhs, rhs in
                    let comparison = lhs.element.localizedCaseInsensitiveCompare(rhs.element)

                    if comparison == .orderedSame {
                        return lhs.offset < rhs.offset
                    }

                    return comparison == .orderedAscending
                }
                .first?
                .element
        }

        private func tokenStartLocation(in text: String, before location: Int) -> Int {
            guard location > 0 else {
                return 0
            }

            let nsText = text as NSString

            for candidateLocation in stride(from: location - 1, through: 0, by: -1) {
                let character = nsText.character(at: candidateLocation)

                if isTagSeparator(character) {
                    return firstTokenCharacterLocation(in: nsText, after: candidateLocation)
                }
            }

            return 0
        }

        private func tokenEndLocation(in text: String, after location: Int) -> Int {
            let nsText = text as NSString

            guard location < nsText.length else {
                return nsText.length
            }

            for candidateLocation in location..<nsText.length {
                let character = nsText.character(at: candidateLocation)

                if isTagSeparator(character) {
                    return candidateLocation
                }
            }

            return nsText.length
        }

        private func isTagSeparator(_ character: unichar) -> Bool {
            character == CharacterCode.comma || character == CharacterCode.semicolon
        }

        private func firstTokenCharacterLocation(in text: NSString, after separatorLocation: Int) -> Int {
            var location = separatorLocation + 1

            while location < text.length {
                let character = text.character(at: location)

                guard
                    let scalar = UnicodeScalar(character),
                    CharacterSet.whitespacesAndNewlines.contains(scalar)
                else {
                    break
                }

                location += 1
            }

            return location
        }

        private func submit(control: NSControl, textView: NSTextView) {
            updateControl(control, text: textView.string)
            parent.text = textView.string
            parent.onSubmit()
        }

        private func updateControl(_ control: NSControl, text: String) {
            guard let textField = control as? NSTextField else {
                return
            }

            textField.stringValue = text
        }
    }
}

private struct CompletionResult {
    let text: String
    let selectedRange: NSRange
}

private enum CharacterCode {
    static let comma = unichar(44)
    static let semicolon = unichar(59)
}
