import SwiftUI
import CarKit

/// Every Bluetooth LE device in range with its advertisement; tap one to connect and browse its services.
struct DebugView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var scan: ScanStore
    @EnvironmentObject private var link: LinkStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var namedOnly = true
    @State private var openDevice = false

    private var shown: [Advert] {
        scan.adverts.filter { ad in
            if namedOnly && ad.name == nil && !ad.isCar { return false }
            guard !filter.isEmpty else { return true }
            let needle = filter.lowercased()
            return ad.title.lowercased().contains(needle)
                || ad.id.uuidString.lowercased().contains(needle)
                || ad.services.contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    LabeledContent("State", value: ble.bluetoothState.label)
                    LabeledContent("Scanning", value: ble.isScanning ? "Yes" : "No")
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Log", systemImage: "list.bullet.rectangle")
                    }
                }
                if link.peripheralID != nil {
                    Section("Connected") {
                        NavigationLink {
                            DeviceView()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.name ?? "Unnamed device")
                                Text(link.state.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Named devices only", isOn: $namedOnly)
                    ForEach(shown) { ad in
                        Button {
                            ble.connect(ad.id)
                            openDevice = true
                        } label: {
                            AdvertRow(ad: ad, connected: link.peripheralID == ad.id)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Devices (\(shown.count))")
                } footer: {
                    Text("Tap a device to connect and see its services. The app reads every readable value and listens to every notification; all of it goes to the log.")
                }
            }
            .searchable(text: $filter, prompt: "Name, identifier or service")
            .navigationTitle("Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $openDevice) { DeviceView() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { ble.beginScan() }
        .onDisappear { ble.endScan() }
    }
}

struct AdvertRow: View {
    let ad: Advert
    let connected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if ad.isCar {
                    Image(systemName: "car.fill")
                        .foregroundStyle(Theme.accent)
                }
                Text(ad.title)
                    .font(.headline)
                if connected {
                    Image(systemName: "link")
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("\(ad.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(ad.details.dropFirst(2).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(ad.id.uuidString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
