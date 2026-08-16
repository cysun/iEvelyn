import SwiftUI

struct LegacyImportReviewView: View {
    let plan: LegacyImportPlan
    let onImport: (LegacyDuplicateStrategy) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var duplicateStrategy: LegacyDuplicateStrategy?
    @State private var isImporting = false

    private var hasConflicts: Bool {
        !plan.summary.duplicateConflicts.isEmpty
    }

    private var plannedResult: (books: Int, chapters: Int, assetRecords: Int, skipped: Int)? {
        let strategy: LegacyDuplicateStrategy
        if hasConflicts {
            guard let duplicateStrategy else { return nil }
            strategy = duplicateStrategy
        } else {
            strategy = .importAsNew
        }
        let conflictIDs = Set(plan.summary.duplicateConflicts.map(\.legacyBookID))
        let selectedBooks = plan.bundle.books.filter {
            strategy == .importAsNew || !conflictIDs.contains($0.legacyID)
        }
        return (
            books: selectedBooks.count,
            chapters: selectedBooks.reduce(0) { $0 + $1.chapters.count },
            assetRecords: selectedBooks.reduce(0) { $0 + $1.referencedAssetIDs.count },
            skipped: strategy == .skipLikelyDuplicates ? conflictIDs.count : 0
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Validated Bundle") {
                    LabeledContent("Books", value: plan.summary.books.formatted())
                    LabeledContent("Chapters", value: plan.summary.chapters.formatted())
                    LabeledContent("Assets", value: plan.summary.assets.formatted())
                    LabeledContent(
                        "Asset Data",
                        value: ByteCountFormatter.string(
                            fromByteCount: plan.summary.assetBytes,
                            countStyle: .file
                        )
                    )
                    LabeledContent("Source Snapshot", value: plan.summary.sourceSnapshotTimestamp)
                }

                Section("Reconciliation") {
                    LabeledContent("Likely Duplicates", value: plan.summary.duplicateConflicts.count.formatted())
                    LabeledContent("Exporter Warnings", value: plan.summary.exporterWarnings.formatted())
                    LabeledContent(
                        "Exporter Skips",
                        value: "\(plan.summary.exporterSkippedCount) item(s) in \(plan.summary.exporterSkippedItems) report row(s)"
                    )
                    LabeledContent("Importer Warnings", value: plan.summary.importerWarnings.count.formatted())
                }

                if hasConflicts {
                    Section("Duplicate Strategy") {
                        Picker("How should likely duplicates be handled?", selection: $duplicateStrategy) {
                            Text("Choose a strategy").tag(LegacyDuplicateStrategy?.none)
                            ForEach(LegacyDuplicateStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.title).tag(Optional(strategy))
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .accessibilityIdentifier("legacy-import-duplicate-strategy")

                        if let duplicateStrategy {
                            Text(duplicateStrategy.explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(plan.summary.duplicateConflicts.prefix(12)) { conflict in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conflict.title)
                                Text("\(conflict.author) · legacy ID \(conflict.legacyBookID)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if plan.summary.duplicateConflicts.count > 12 {
                            Text("And \(plan.summary.duplicateConflicts.count - 12) more likely duplicate(s).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Duplicate Strategy") {
                        Label("No likely duplicate books were found.", systemImage: "checkmark.circle")
                    }
                }

                Section("Planned Result") {
                    if let plannedResult {
                        LabeledContent("Books to Add", value: plannedResult.books.formatted())
                        LabeledContent("Chapters to Add", value: plannedResult.chapters.formatted())
                        LabeledContent("Asset Records to Add", value: plannedResult.assetRecords.formatted())
                        LabeledContent(
                            "Likely Duplicates to Skip",
                            value: plannedResult.skipped.formatted()
                        )
                    } else {
                        Text("Choose a duplicate strategy to calculate additions and skips.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !plan.summary.importerWarnings.isEmpty {
                    Section("Importer Warnings") {
                        ForEach(Array(plan.summary.importerWarnings.prefix(12).enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.callout)
                        }
                        if plan.summary.importerWarnings.count > 12 {
                            Text("The permanent reconciliation report will include all warnings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("Nothing has been written to the library yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .disabled(isImporting)
                Button("Import") {
                    let strategy = duplicateStrategy ?? .importAsNew
                    isImporting = true
                    Task {
                        let succeeded = await onImport(strategy)
                        isImporting = false
                        if succeeded {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || (hasConflicts && duplicateStrategy == nil))
                .accessibilityIdentifier("legacy-import-confirm")
            }
            .padding()
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 680)
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("Building and validating the imported library…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("legacy-import-progress")
            }
        }
        .navigationTitle("Review Legacy Import")
        .accessibilityIdentifier("legacy-import-review")
    }
}
