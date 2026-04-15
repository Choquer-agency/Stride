import SwiftUI

struct VoiceCoachSettingsSection: View {
    @State private var settings = VoiceCoachSettings.load()

    var body: some View {
        Section {
            Toggle(isOn: $settings.isEnabled) {
                Label("Voice Coach", systemImage: "speaker.wave.2")
                    .foregroundStyle(Color.primary, Color.stridePrimary)
            }
            .tint(Color.stridePrimary)
            .onChange(of: settings.isEnabled) { _, _ in settings.save() }

            if settings.isEnabled {
                // Pace unit picker
                HStack {
                    Label("Pace Unit", systemImage: "ruler")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                    Spacer()
                    Picker("", selection: $settings.paceUnit) {
                        Text("km").tag(PaceUnit.km)
                        Text("miles").tag(PaceUnit.miles)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .onChange(of: settings.paceUnit) { _, _ in settings.save() }
                }

                Toggle(isOn: $settings.announceKmSplits) {
                    Label("Announce Splits", systemImage: "text.bubble")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceKmSplits) { _, _ in settings.save() }

                Toggle(isOn: $settings.announcePaceZone) {
                    Label("Pace Alerts", systemImage: "gauge.with.dots.needle.33percent")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announcePaceZone) { _, _ in settings.save() }

                Toggle(isOn: $settings.announceHalfway) {
                    Label("Halfway Alert", systemImage: "flag.checkered")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceHalfway) { _, _ in settings.save() }

                Toggle(isOn: $settings.speakPausedResumed) {
                    Label("Pause/Resume Cues", systemImage: "pause.circle")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.speakPausedResumed) { _, _ in settings.save() }

                Toggle(isOn: $settings.announceCountdown) {
                    Label("Countdown", systemImage: "timer")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceCountdown) { _, _ in settings.save() }

                Toggle(isOn: $settings.announceWorkoutPreview) {
                    Label("Workout Preview", systemImage: "list.bullet.clipboard")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceWorkoutPreview) { _, _ in settings.save() }

                Toggle(isOn: $settings.announceEncouragement) {
                    Label("Encouragement", systemImage: "hand.thumbsup")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceEncouragement) { _, _ in settings.save() }

                Toggle(isOn: $settings.announcePostRunSummary) {
                    Label("Post-Run Summary", systemImage: "chart.bar")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announcePostRunSummary) { _, _ in settings.save() }

                Toggle(isOn: $settings.announceRecords) {
                    Label("Personal Records", systemImage: "trophy")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                .tint(Color.stridePrimary)
                .onChange(of: settings.announceRecords) { _, _ in settings.save() }
            }
        } header: {
            Text("Voice Coaching")
        } footer: {
            Text("Voice coach speaks over your music during runs. Uses pre-recorded audio for instant playback.")
        }
    }
}
