import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// Where the notification permission comes from. Injectable so a preview can show the denied state.
    private let effects: any SessionEffects
    /// Starts as `.allowed` so the "Notifications are off" row doesn't flash before the first read.
    @State private var notificationAuthorization: NotificationAuthorization = .allowed
    @AppStorage(AppSettings.Key.defaultReps) private var reps = AppSettings.Default.reps
    @AppStorage(AppSettings.Key.defaultKg) private var kg = AppSettings.Default.kg
    @AppStorage(AppSettings.Key.defaultRestSeconds) private var restSeconds = AppSettings.Default.restSeconds
    @AppStorage(AppSettings.Key.weightStep) private var weightStepRaw = AppSettings.Default.weightStep.rawValue
    @AppStorage(AppSettings.Key.soundEnabled) private var soundEnabled = AppSettings.Default.soundEnabled
    @AppStorage(AppSettings.Key.hapticsEnabled) private var hapticsEnabled = AppSettings.Default.hapticsEnabled

    init(effects: any SessionEffects = SessionEffectsProvider.current) {
        self.effects = effects
    }

    // Bindings clamp on read and write, so a bad stored value is never shown or written back.
    private var repsBinding: Binding<Int> {
        Binding(get: { AppSettings.clampReps(reps) }, set: { reps = AppSettings.clampReps($0) })
    }

    private var kgBinding: Binding<Double> {
        Binding(get: { AppSettings.snapKg(kg) }, set: { kg = AppSettings.snapKg($0) })
    }

    private var restBinding: Binding<Int> {
        Binding(get: { AppSettings.clampRest(restSeconds) }, set: { restSeconds = AppSettings.clampRest($0) })
    }

    private var weightStepBinding: Binding<WeightStep> {
        Binding(
            get: { WeightStep(rawValue: weightStepRaw) ?? .default },
            set: { weightStepRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    NavigationLink("Exercises") { ExerciseListView() }
                }
                Section {
                    RepsStepper(reps: repsBinding)
                    WeightField(kg: kgBinding)
                    RestStepper(seconds: restBinding)
                } header: {
                    Text("Defaults for new sets")
                } footer: {
                    Text("Used for a new exercise\u{2019}s first set when the exercise has no defaults of its own and isn\u{2019}t in any saved workout.")
                }
                Section {
                    Picker("Weight Step", selection: weightStepBinding) {
                        ForEach(WeightStep.allCases) { step in
                            Text(step.displayName).tag(step)
                        }
                    }
                } footer: {
                    Text("How much the + and \u{2212} buttons change the weight.")
                }
                Section {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                    if SettingsRules.showsNotificationsOffRow(for: notificationAuthorization) {
                        notificationsOffRow
                    }
                } header: {
                    Text(SettingsMessages.restEndAlertTitle)
                } footer: {
                    Text(SettingsMessages.restEndAlertFooter)
                }
            }
            .navigationTitle("Settings")
            .task { await refreshNotificationAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                // Back from the system Settings, where the user may have changed it.
                guard phase == .active else { return }
                Task { await refreshNotificationAuthorization() }
            }
        }
    }

    private var notificationsOffRow: some View {
        LabeledContent {
            Button(SettingsMessages.openSettingsButton) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            .accessibilityHint(SettingsMessages.openSettingsHint)
        } label: {
            Label {
                Text(SettingsMessages.notificationsOffTitle)
            } icon: {
                Image(systemName: "bell.slash").accessibilityHidden(true)
            }
        }
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorization = await effects.notificationAuthorization()
    }
}

/// Reports the permission as denied, so a preview can show the "Notifications are off" row.
private struct DeniedNotificationEffects: SessionEffects {
    func sessionChanged(_ state: SessionEffectsState) {}
    func appBecameActive(_ state: SessionEffectsState) {}
    func requestNotificationPermissionIfNeeded() {}
    func notificationAuthorization() async -> NotificationAuthorization { .denied }
    func restEndAlertIsCovered(restEndsAt: Date) -> Bool { false }
}

#Preview {
    SettingsView()
        .modelContainer(ExercisePreviewData.container())
}

#Preview("Notifications denied") {
    SettingsView(effects: DeniedNotificationEffects())
        .modelContainer(ExercisePreviewData.container())
}
