import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                placeholder("Workouts", systemImage: "dumbbell")
            }
            Tab("History", systemImage: "calendar") {
                placeholder("History", systemImage: "calendar")
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                placeholder("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }

    private func placeholder(_ title: LocalizedStringKey, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon."))
    }
}

#Preview {
    RootTabView()
}
