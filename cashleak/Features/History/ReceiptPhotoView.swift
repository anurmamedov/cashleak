import SwiftUI

/// A scanned receipt, full screen. Pinch or double-tap to zoom.
///
/// The photo lives with the purchase in the person's own iCloud, so they can
/// also remove it here to free that space — the amount, shop and date it gave
/// stay as they are.
struct ReceiptPhotoView: View {

    let image: UIImage
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var confirmingRemove = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value.magnification, 1), 5)
                        }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        confirmingRemove = true
                    } label: {
                        Label("Remove photo", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "Remove the receipt photo?",
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove photo", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            } message: {
                Text("The purchase stays as it is. Only the photo goes.")
            }
        }
    }
}
