import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var monitor: AudioMonitor

    private var isMonitoring: Binding<Bool> {
        Binding(
            get: { monitor.isMonitoring },
            set: { enabled in
                if enabled {
                    monitor.start()
                } else {
                    monitor.stop()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Monitoring", isOn: isMonitoring)
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(monitor.volume * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $monitor.volume, in: 0...1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Button("Quit Return") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .keyboardShortcut("q", modifiers: .command)
        }
        .frame(width: 260)
    }
}
