import SwiftUI
import Photos

struct PhotosGalleryView: View {
    var plan: Plan
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    // Flatten days → ordered items
    var items: [PhotoItem] {
        plan.days
            .sorted(by: { $0.date < $1.date })
            .flatMap { d -> [PhotoItem] in
                let dayNo = max(0, plan.startDate.days(to: d.date)) + 1
                return d.photos.map { PhotoItem(dayNumber: dayNo, date: d.date, filename: $0.filename) }
            }
    }

    @State private var compareMode = false
    @State private var selectedForCompare: [PhotoItem] = []

    @State private var showViewer = false
    @State private var viewerIndex = 0

    @State private var showCompare = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            ThumbCell(item: item,
                                      isSelected: compareMode && selectedForCompare.contains(item))
                            .onTapGesture {
                                if compareMode {
                                    toggleSelect(item)
                                } else {
                                    if let idx = items.firstIndex(of: item) {
                                        viewerIndex = idx
                                        showViewer = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .navigationTitle("Progress Photos")
            .fullScreenCover(isPresented: $showViewer) {
                PhotoDetailView(items: items, initialIndex: viewerIndex)
            }
            .sheet(isPresented: $showCompare) {
                if selectedForCompare.count == 2 {
                    CompareView(left: selectedForCompare[0], right: selectedForCompare[1])
                }
            }
        }
    }

    // MARK: Header
    @ViewBuilder
    private var header: some View {
        HStack {
            if compareMode {
                Button(role: .cancel) {
                    selectedForCompare.removeAll()
                    compareMode = false
                } label: { Label("Cancel", systemImage: "xmark.circle") }

                Spacer()

                Button {
                    if selectedForCompare.count == 2 { showCompare = true }
                } label: {
                    Label("Compare", systemImage: "square.split.2x1")
                }
                .disabled(selectedForCompare.count != 2)
            } else {
                Spacer()
                Button {
                    compareMode = true
                    selectedForCompare.removeAll()
                } label: { Label("Select 2 to Compare", systemImage: "square.on.square") }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggleSelect(_ item: PhotoItem) {
        if let i = selectedForCompare.firstIndex(of: item) {
            selectedForCompare.remove(at: i)
        } else if selectedForCompare.count < 2 {
            selectedForCompare.append(item)
        }
    }
}

// MARK: - Types

struct PhotoItem: Identifiable, Equatable {
    var id: String { filename }
    let dayNumber: Int
    let date: Date
    let filename: String
}

private struct ThumbCell: View {
    let item: PhotoItem
    var isSelected: Bool

    var body: some View {
        let url = photosDir().appendingPathComponent(item.filename)
        ZStack(alignment: .bottomLeading) {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 160)
                    .clipped()
                    .cornerRadius(10)
            } else {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 110, height: 160)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(item.dayNumber)").font(.caption2).bold().foregroundStyle(.white)
                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
            }
            .padding(6)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, .green)
                    .padding(6)
            }
        }
    }
}
