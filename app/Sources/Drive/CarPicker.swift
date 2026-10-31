import SwiftUI
import CarKit

/// The cars in range, nearest signal shown; tap one to drive it. Other devices are one tap away, for a car that
/// advertises an unexpected name.
struct CarPicker: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var scan: ScanStore
    @EnvironmentObject private var link: LinkStore
    @Environment(\.dismiss) private var dismiss
    @State private var showOthers = false

    private var cars: [Advert] { scan.adverts.filter(\.isCar) }
    private var others: [Advert] { scan.adverts.filter { !$0.isCar && $0.name != nil } }

    var body: some View {
        NavigationStack {
            List {
                if let problem = ble.bluetoothState.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if link.peripheralID != nil {
                    Section("Current") {
                        HStack {
                            Text(link.name ?? "Unnamed device")
                            Spacer()
                            Text(link.state.label)
                                .foregroundStyle(.secondary)
                        }
                        Button("Disconnect", role: .destructive) {
                            ble.disconnect()
                        }
                    }
                }
                Section {
                    if cars.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for cars…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(cars) { ad in row(ad) }
                } header: {
                    Text("Cars nearby")
                } footer: {
                    Text("Switch the car on and keep it close. A car takes one phone at a time: close the Shell app if it is connected.")
                }
                if !others.isEmpty {
                    Section("Other devices") {
                        if showOthers {
                            ForEach(others) { ad in row(ad) }
                        } else {
                            Button("Show \(others.count) other devices") { showOthers = true }
                        }
                    }
                }
            }
            .navigationTitle("Choose your car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { ble.beginScan() }
        .onDisappear { ble.endScan() }
    }

    private func row(_ ad: Advert) -> some View {
        Button {
            ble.connect(ad.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ad.isCar ? "car.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(ad.isCar ? Theme.accent : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ad.title)
                        .foregroundStyle(.primary)
                    if let hint = ad.protocolHint {
                        Text(hint.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if link.peripheralID == ad.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                }
                Text("\(ad.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
