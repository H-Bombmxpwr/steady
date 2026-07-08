//
//  NumberEditor.swift
//  75
//
//  Created by Hunter Baisden on 9/4/25.
//

import SwiftUI

struct NumberEditor: View {
    let title: String
    @Binding var value: Int
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(title: String, value: Binding<Int>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(title, text: $text)
                    .keyboardType(.numberPad)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let v = Int(text) { value = v }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
