import SwiftUI
import UIKit

/// Ground truth for treadmill BLE: live link status plus the persistent event
/// log, so a dead run can be diagnosed after the fact without Xcode attached.
struct TreadmillDiagnosticsView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @ObservedObject private var diag = BLEDiagnosticsLog.shared
    @State private var copied = false
    @State private var captureFiles: [URL] = []

    var body: some View {
        List {
            Section {
                if captureFiles.isEmpty {
                    Text("No treadmill captures yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(captureFiles, id: \.self) { file in
                        ShareLink(item: file) {
                            Label(file.lastPathComponent, systemImage: "square.and.arrow.up")
                                .lineLimit(2)
                        }
                    }
                }
                Button("Refresh Captures") {
                    captureFiles = TreadmillRawCapture.shared.files()
                }
            } header: {
                Text("Raw treadmill data · Share CSV")
            } footer: {
                Text("Each indoor run records every received FTMS packet, including its original hex bytes and timestamp. Share the file after ending the run.")
            }

            Section {
                statusRow("Link", bluetoothManager.connectionState)
                statusRow("Subscription", bluetoothManager.subscriptionState)
                statusRow("Packets received", "\(bluetoothManager.packetCount)")
                statusRow("Last packet", lastPacketText)
            } header: {
                Text("Live Status")
            }

            Section {
                Button {
                    bluetoothManager.forceFreshReconnect()
                } label: {
                    Label("Forget & Reconnect Fresh", systemImage: "arrow.clockwise")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                Button {
                    UIPasteboard.general.string = diag.fullText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy Log", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(Color.primary, Color.stridePrimary)
                }
                Button(role: .destructive) {
                    diag.clear()
                } label: {
                    Label("Clear Log", systemImage: "trash")
                }
            }

            Section {
                if diag.lines.isEmpty {
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                        .font(.inter(size: 13))
                } else {
                    ForEach(Array(diag.lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(lineColor(line))
                            .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 8))
                    }
                }
            } header: {
                Text("Event Log (newest first)")
            }
        }
        .navigationTitle("Treadmill Diagnostics")
        .strideSecondaryScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { captureFiles = TreadmillRawCapture.shared.files() }
    }

    private var lastPacketText: String {
        guard let at = bluetoothManager.lastPacketAt else { return "never" }
        let age = Int(Date().timeIntervalSince(at))
        return age < 2 ? "just now" : "\(age) s ago"
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.inter(size: 14))
            Spacer()
            Text(value)
                .font(.inter(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("FAILED") || line.contains("MISSING") || line.contains("TIMEOUT") { return .red }
        if line.contains("watchdog") || line.contains("FORCE") { return .orange }
        if line.contains("SUBSCRIBED") || line.contains("FIRST PACKET") || line.contains("CONNECTED") { return .green }
        return .primary
    }
}
