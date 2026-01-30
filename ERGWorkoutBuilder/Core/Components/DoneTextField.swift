import SwiftUI
import UIKit

struct DoneTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var value: Int
    var keyboardType: UIKeyboardType = .numberPad

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.textAlignment = .right
        textField.delegate = context.coordinator

        // Create toolbar with Done button
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.donePressed))
        toolbar.items = [flexSpace, doneButton]
        textField.inputAccessoryView = toolbar

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.text = "\(value)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DoneTextField

        init(_ parent: DoneTextField) {
            self.parent = parent
        }

        @objc func donePressed() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if let text = textField.text, let intValue = Int(text) {
                parent.value = intValue
            }
        }
    }
}

struct DoneDecimalField: UIViewRepresentable {
    let placeholder: String
    @Binding var value: Double

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.delegate = context.coordinator

        // Create toolbar with Done button
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.donePressed))
        toolbar.items = [flexSpace, doneButton]
        textField.inputAccessoryView = toolbar

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.text = String(format: "%.1f", value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DoneDecimalField

        init(_ parent: DoneDecimalField) {
            self.parent = parent
        }

        @objc func donePressed() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if let text = textField.text, let doubleValue = Double(text) {
                parent.value = doubleValue
            }
        }
    }
}
