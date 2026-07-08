//
//  DocumentExporter.swift
//  75
//
//  Created by Hunter Baisden on 9/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Exporting (copies file out to provider destinations)
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
