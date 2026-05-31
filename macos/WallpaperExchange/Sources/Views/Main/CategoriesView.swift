import SwiftUI

// Categories index — loads /categories then renders a tile grid.
// Clicking a category pushes a SearchResultsView-equivalent feed
// filtered by category_id; for the demo we route by issuing a
// category-filtered fetch in a small child view.
struct CategoriesView: View {
    var onPickCategory: (Category) -> Void

    @State private var cats: [Category] = []
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Browse by topic")
                    Text("Categories").font(.display32).foregroundStyle(Color.ink)
                }
                if loading && cats.isEmpty {
                    ProgressView()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(cats) { c in
                            Button(action: { onPickCategory(c) }) {
                                CategoryCard(name: c.name, slug: c.slug)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let list = try? await APIClient.shared.fetchCategories() {
            cats = list.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }
    }
}

struct CategoryCard: View {
    let name: String
    let slug: String
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.paper2)
                Image(systemName: iconFor(slug))
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.ink2)
            }
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))

            Text(name)
                .font(.displayMd).foregroundStyle(Color.ink)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.clear))
        .scaleEffect(hover ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }
    private func iconFor(_ slug: String) -> String {
        switch slug {
        case "nature":   "leaf"
        case "city":     "building.2"
        case "anime":    "paintbrush"
        case "abstract": "swirl.circle.righthalf.filled"
        case "animal":   "pawprint"
        case "space":    "moon.stars"
        case "minimal":  "minus.rectangle"
        case "tech":     "cpu"
        case "game":     "gamecontroller"
        default:         "square.grid.3x2"
        }
    }
}

// Category-filtered feed, pushed on top of the nav stack when a card
// is tapped.
struct CategoryFeedView: View {
    let category: Category
    var onWallpaper: (Wallpaper) -> Void

    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Category · \(category.slug)")
                    Text(category.name).font(.display32).foregroundStyle(Color.ink)
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
                if loading && items.isEmpty {
                    ProgressView()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(items) { wp in
                            Button(action: { onWallpaper(wp) }) { MainGridTile(wallpaper: wp) }
                                .buttonStyle(.plain)
                                .onAppear { maybeLoadMore(wp) }
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.paper.ignoresSafeArea())
        .task(id: category.id) { await reload() }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false
        await loadMore()
    }
    private func loadMore() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchWallpapers(cursor: cursor, limit: 24, categoryID: category.id) {
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        }
    }
    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }
}
