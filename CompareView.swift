import SwiftUI

struct CompareView: View {
    let left: PhotoItem
    let right: PhotoItem
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                FullscreenImage(filename: left.filename)
                    .tag(0)
                    .overlay(alignment: .topLeading) {
                        label("Day \(left.dayNumber)")
                    }

                FullscreenImage(filename: right.filename)
                    .tag(1)
                    .overlay(alignment: .topTrailing) {
                        label("Day \(right.dayNumber)")
                    }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption).bold()
            .padding(6)
            .foregroundStyle(.white)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 12)
            .padding(.horizontal, 12)
    }
}

private struct FullscreenImage: View {
    let filename: String
    var body: some View {
        let url = photosDir().appendingPathComponent(filename)
        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
            } else {
                Rectangle().fill(.black).ignoresSafeArea()
            }
        }
    }
}
