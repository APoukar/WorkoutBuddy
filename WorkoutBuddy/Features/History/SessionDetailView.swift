import SwiftData
import SwiftUI

/// A saved session (F6): name, start, duration, volume and every set as done, with the plan where it differs,
/// and a Delete button. The view keeps `SessionDetailContent` (a value), not the model, so a deleted session
/// is never read and the screen doesn't flip to "Workout Not Found" while it pops; the model is looked up
/// again by ID only when Delete is confirmed.
struct SessionDetailView: View {
    let sessionID: UUID
    /// Called after a successful delete, so the caller can pop this screen.
    let onDeleted: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var content: SessionDetailContent?
    /// Set once the first lookup has run, so "Not Found" doesn't flash before it.
    @State private var loaded = false
    @State private var confirmingDelete = false
    @State private var error: Error?

    private var library: HistoryLibrary { HistoryLibrary(context: context) }

    var body: some View {
        Group {
            if let content {
                list(content)
            } else if loaded {
                ContentUnavailableView {
                    Label(HistoryMessages.notFoundTitle, systemImage: "calendar.badge.exclamationmark")
                }
            } else {
                Color.clear
            }
        }
        .navigationTitle(content?.workoutName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if content != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label(HistoryMessages.deleteButton, systemImage: "trash")
                    }
                    .accessibilityIdentifier(UITestingContract.Identifier.historyDeleteSession)
                }
            }
        }
        .alert(HistoryMessages.deleteTitle, isPresented: $confirmingDelete) {
            Button(HistoryMessages.cancelButton, role: .cancel) {}
            Button(HistoryMessages.deleteButton, role: .destructive) { delete() }
        } message: {
            Text(content.map { HistoryMessages.deleteMessage(startedAt: $0.startedAt) } ?? "")
        }
        .errorAlert($error, message: SessionMessages.failureMessage(for:))
        .onAppear(perform: reload)
    }

    private func list(_ content: SessionDetailContent) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.startText)
                    if let endedEarly = content.endedEarlyText {
                        Text(endedEarly)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(SessionMessages.durationLabel) { Text(content.durationText) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionMessages.durationLabel)
                    .accessibilityValue(content.spokenDurationText)
                LabeledContent(SessionMessages.volumeLabel) { Text(content.volumeText) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionMessages.volumeLabel)
                    .accessibilityValue(content.spokenVolumeText)
            }
            ForEach(content.sections) { section in
                Section(section.name) {
                    ForEach(section.rows) { row in setRow(row) }
                }
            }
        }
    }

    @ViewBuilder
    private func setRow(_ row: SessionDetailContent.SetRow) -> some View {
        let title = Text(row.title)
        let primary = Text(row.primaryText)
        let planned = row.plannedText.map {
            Text($0).font(.subheadline).foregroundStyle(.secondary)
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Too wide for two columns: stack the row.
                VStack(alignment: .leading, spacing: 2) {
                    title
                    primary
                    planned
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        primary
                        planned
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenText)
    }

    /// Builds the content from the store. A session that can't be found after it was shown keeps its content.
    private func reload() {
        defer { loaded = true }
        guard let session = library.session(id: sessionID) else { return }
        let sessions = SessionLibrary(context: context)
        content = SessionDetailContent(
            sessions.snapshot(of: session), workoutName: session.workout?.name,
            exerciseNames: sessions.exerciseNames(of: session))
    }

    private func delete() {
        // Already gone: nothing to delete, just leave the screen.
        guard let session = library.session(id: sessionID) else {
            onDeleted()
            return
        }
        // An in-progress session isn't history: `HistoryLibrary.delete` would do nothing, so don't leave the screen.
        guard session.status == .completed || session.status == .endedEarly else { return }
        do {
            try library.delete(session)
            onDeleted()
        } catch {
            ErrorLogging.log(error, action: "Deleting session", category: "history")
            self.error = error
        }
    }
}

private struct DetailPreview: View {
    let preview = HistoryPreviewData.make()
    let pick: (HistoryPreviewData.Preview) -> UUID

    var body: some View {
        NavigationStack {
            SessionDetailView(sessionID: pick(preview), onDeleted: {})
        }
        .modelContainer(preview.container)
    }
}

#Preview("Completed") { DetailPreview(pick: \.completedID) }

#Preview("Ended early") { DetailPreview(pick: \.endedEarlyID) }

#Preview("Bodyweight, deleted template") { DetailPreview(pick: \.bodyweightID) }

#Preview("Ended early, accessibility size") {
    DetailPreview(pick: \.endedEarlyID).dynamicTypeSize(.accessibility3)
}
