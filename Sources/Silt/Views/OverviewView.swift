import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: AppModel

    private var largestCategoryBytes: Int64 {
        max(1, model.categoriesWithContent.map { model.bytes(in: $0) }.max() ?? 1)
    }

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 18)]

    /// Review sizes are expensive, so the card reflects whether they have been paid for yet.
    @ViewBuilder
    private var reviewCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.warn)

            VStack(alignment: .leading, spacing: 3) {
                switch model.reviewState {
                case .measured:
                    Text("\(model.reviewBytes.byteLabel) sits in folders Silt will never touch")
                        .font(Theme.heading(15, weight: .semibold))
                    Text("Simulators, Docker images, package stores and backups. Open Review to see the exact command for each one.")
                        .font(Theme.heading(13))
                        .foregroundStyle(.secondary)
                case .measuring:
                    Text("Measuring the untouchable folders…")
                        .font(Theme.heading(15, weight: .semibold))
                    Text("\(model.reviewProgress.completed) of \(model.reviewProgress.total) · \(model.reviewProgress.currentName)")
                        .font(Theme.heading(13))
                        .foregroundStyle(.secondary)
                case .notMeasured:
                    Text("Big folders Silt will never touch")
                        .font(Theme.heading(15, weight: .semibold))
                    Text("Simulators, Docker images, package stores and backups. Sizing them means walking millions of small files, so it is not part of a normal scan.")
                        .font(Theme.heading(13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.reviewState == .measuring {
                Button("Stop") { model.cancelReviewMeasure() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            } else {
                Button(model.reviewState == .measured ? "Review" : "Measure") {
                    model.route = .category(.review)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .card(radius: 18, padding: 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DiskHeroView(model: model, animate: true)

            HStack(spacing: 10) {
                Text("What to clear")
                    .font(Theme.heading(15, weight: .bold))
                Spacer()
                Button("Recommended") { model.selectRecommended() }
                Button("Select all") { model.selectEverythingCleanable() }
                Button("None") { model.selection.removeAll() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.categoriesWithContent) { category in
                    CategoryCard(
                        category: category,
                        bytes: model.bytes(in: category),
                        selectedBytes: model.selectedBytes(in: category),
                        bucketCount: model.buckets(in: category).count,
                        share: Double(model.bytes(in: category)) / Double(largestCategoryBytes),
                        action: { model.route = .category(category) }
                    )
                }
            }

            if model.hasReviewTargets {
                reviewCard
            }
        }
    }
}

struct CategoryDetailView: View {
    @ObservedObject var model: AppModel
    let category: CleanCategory

    private var buckets: [ScannedTarget] { model.buckets(in: category) }

    private struct BucketGroup {
        let name: String
        let buckets: [ScannedTarget]
        var bytes: Int64 { buckets.reduce(0) { $0 + $1.bytes } }
    }

    /// Shown while the expensive review sizes are still being produced.
    @ViewBuilder
    private var reviewMeasuringCard: some View {
        HStack(spacing: 14) {
            if model.reviewState == .measuring {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Measuring \(model.reviewProgress.total) folders — \(model.reviewProgress.completed) done")
                        .font(Theme.heading(14, weight: .semibold))
                    Text(model.reviewProgress.currentName.isEmpty
                         ? "These are the biggest trees on the disk. The pnpm store alone can take a minute."
                         : model.reviewProgress.currentName)
                        .font(Theme.heading(12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") { model.cancelReviewMeasure() }
                    .controlSize(.large)
            } else {
                Image(systemName: "ruler")
                    .foregroundStyle(Theme.warn)
                Text("Sizes not measured yet — walking these folders takes a while.")
                    .font(Theme.heading(14, weight: .medium))
                Spacer()
                Button("Measure now") { model.measureReview(force: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
            }
        }
        .card(radius: 16, padding: 14)
    }

    /// Groups ordered by how much they hold, so the interesting ones are at the top.
    private var groups: [BucketGroup] {
        Dictionary(grouping: buckets, by: { $0.target.group })
            .map { BucketGroup(name: $0.key, buckets: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }
    private var allSelected: Bool {
        let deletable = buckets.filter { $0.target.kind.isDeletable }
        return !deletable.isEmpty && deletable.allSatisfy { model.isSelected($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                IconTile(symbol: category.symbol, tint: Theme.tint(for: category), size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(Theme.heading(20, weight: .bold))
                    Text(category.blurb)
                        .font(Theme.heading(14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.bytes(in: category).byteLabel)
                        .font(Theme.figure(20))
                    Text("in \(buckets.count) locations")
                        .font(Theme.heading(12))
                        .foregroundStyle(.secondary)
                }
            }
            .card(padding: 22)

            if category == .review, model.reviewState != .measured {
                reviewMeasuringCard
            }

            if category != .review {
                HStack {
                    Button(allSelected ? "Deselect all" : "Select all") {
                        model.setSelection(!allSelected, in: category)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Spacer()
                    Text("\(model.selectedBytes(in: category).byteLabel) selected here")
                        .font(Theme.heading(13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Grouped by language or tool family — Developer alone can hold 80 locations,
            // and a flat list of 80 rows is not something anyone reads.
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(group.name.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                            Text(group.bytes.byteLabel)
                                .font(Theme.figure(12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)

                        LazyVStack(spacing: 2) {
                            ForEach(group.buckets) { bucket in
                                BucketRow(
                                    bucket: bucket,
                                    isSelected: model.isSelected(bucket),
                                    onToggle: { model.toggle(bucket) },
                                    onReveal: { model.reveal(bucket.target.path) }
                                )
                                if bucket.id != group.buckets.last?.id {
                                    Divider().opacity(0.4).padding(.leading, 96)
                                }
                            }
                        }
                        .card(radius: 20, padding: 6)
                    }
                }
            }
        }
    }
}
