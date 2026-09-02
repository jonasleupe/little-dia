import SwiftUI

/// Root of the share extension: owns the `ChatModel` for this share and shows
/// the Little Dia sheet.
struct ShareRootView: View {
    let onClose: () -> Void
    @State private var model: ChatModel

    init(content: SharedContent, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: ChatModel(content: content))
    }

    var body: some View {
        DiaSheetView(model: model, onClose: onClose)
    }
}
