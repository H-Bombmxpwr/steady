import SwiftUI
import PhotosUI

struct PhotoDetailView: View {
    let items: [PhotoItem]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    init(items: [PhotoItem], initialIndex: Int) {
        self.items = items
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(items.indices, id: \.self) { i in
                    ZoomableImage(filename: items[i].filename)
                        .tag(i)
                        .background(Color.black)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Day \(items[index].dayNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        saveToPhotos(filename: items[index].filename)
                    } label: { Image(systemName: "square.and.arrow.down") }

                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(isPresented: $showShare) {
                let url = photosDir().appendingPathComponent(items[index].filename)
                ActivityView(activityItems: [url])
            }
        }
    }

    private func saveToPhotos(filename: String) {
        let url = photosDir().appendingPathComponent(filename)
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
}

private struct ZoomableImage: View {
    let filename: String
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        let url = photosDir().appendingPathComponent(filename)

        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    // Pinch zoom
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale = max(1.0, $0) }
                            .onEnded { _ in
                                if scale < 1.02 { scale = 1.0; offset = .zero }
                            }
                    )
                    // Pan only when zoomed in — do NOT block TabView swipe otherwise
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.02 { offset = value.translation }
                            }
                            .onEnded { _ in
                                if scale <= 1.02 { offset = .zero }
                            }
                    )
            } else {
                Rectangle().fill(Color.black)
            }
        }
    }
}

