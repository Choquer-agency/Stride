import SwiftUI

struct VoiceCoachSettingsSection: View {
    @State private var settings = VoiceCoachSettings.load()

    var body: some View {
        Section {
            NavigationLink {
                VoiceCoachSettingsView()
            } label: {
                HStack {
                    Label("Voice Coach", systemImage: "speaker.wave.2")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    Text(settings.isEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voice Coaching")
        }
        .onAppear { settings = VoiceCoachSettings.load() }
    }
}

struct VoiceCoachSettingsView: View {
    @State private var settings = VoiceCoachSettings.load()

    var body: some View {
        List {
            Section {
                Toggle("Voice Coach", isOn: binding(\.isEnabled))
            } footer: {
                Text("Voice coach speaks over your music during runs.")
            }

            Section("Units") {
                Picker("Pace Unit", selection: binding(\.paceUnit)) {
                    Text("Kilometers").tag(PaceUnit.km)
                    Text("Miles").tag(PaceUnit.miles)
                }
            }
            .disabled(!settings.isEnabled)

            Section("During Your Run") {
                settingToggle("Announce Splits", icon: "text.bubble", keyPath: \.announceKmSplits)
                settingToggle("Pace Alerts", icon: "gauge.with.dots.needle.33percent", keyPath: \.announcePaceZone)
                settingToggle("Halfway Alert", icon: "flag.checkered", keyPath: \.announceHalfway)
                settingToggle("Pause/Resume Cues", icon: "pause.circle", keyPath: \.speakPausedResumed)
                settingToggle("Countdown", icon: "timer", keyPath: \.announceCountdown)
                settingToggle("Workout Preview", icon: "list.bullet.clipboard", keyPath: \.announceWorkoutPreview)
                settingToggle("Encouragement", icon: "hand.thumbsup", keyPath: \.announceEncouragement)
                settingToggle("Finish Push", icon: "flag", keyPath: \.announceFinishPush)
                settingToggle("Terrain Coaching", icon: "mountain.2", keyPath: \.announceTerrainCoaching)
            }
            .disabled(!settings.isEnabled)

            Section("After Your Run") {
                settingToggle("Post-Run Summary", icon: "chart.bar", keyPath: \.announcePostRunSummary)
                settingToggle("Personal Records", icon: "trophy", keyPath: \.announceRecords)
            }
            .disabled(!settings.isEnabled)
        }
        .navigationTitle("Voice Coach")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.stridePrimary)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !settings.isEnabled {
                Text("Turn on Voice Coach to customize announcements.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
        .onAppear { settings = VoiceCoachSettings.load() }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VoiceCoachSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                settings.save()
            }
        )
    }

    private func settingToggle(
        _ title: String,
        icon: String,
        keyPath: WritableKeyPath<VoiceCoachSettings, Bool>
    ) -> some View {
        Toggle(isOn: binding(keyPath)) {
            Label(title, systemImage: icon)
                .foregroundStyle(Color.primary, Color.stridePrimary)
        }
    }
}
