import SwiftUI
import PDFKit

/// Inline PDF viewer — wraps PDFKit's PDFView. Loads from a local file URL (the downloaded + cached memoir).
struct PDFKitView: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = PDFDocument(url: fileURL)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != fileURL { v.document = PDFDocument(url: fileURL) }
    }
}
