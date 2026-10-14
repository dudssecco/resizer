import SwiftUI
import AppKit

/// Text field that only accepts digits and caps the value at `max`.
/// Uses NSTextField because SwiftUI's TextField on macOS doesn't revert
/// the typed text when the filtered value equals the previous one.
struct NumericField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let max: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumericField
        init(_ parent: NumericField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let clean = Self.sanitize(field.stringValue, max: parent.max)
            if field.stringValue != clean { field.stringValue = clean }
            if parent.text != clean { parent.text = clean }
        }

        static func sanitize(_ text: String, max: Int) -> String {
            let digits = String(text.filter { ("0"..."9").contains($0) }.prefix(5))
            guard let n = Int(digits) else { return digits }
            return String(min(n, max))
        }
    }
}
