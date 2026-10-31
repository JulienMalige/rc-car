import SwiftUI
import UIKit

/// The Bluetooth log, newest at the bottom; shared or copied as text to work out what a car does.
struct LogView: View {
    @EnvironmentObject private var log: LogStore
    @State private var only: LogStore.Kind?
    @State private var follow = true

    private var shown: [LogStore.Entry] {
        guard let only else { return log.entries }
        return log.entries.filter { $0.kind == only }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(shown) { entry in
                Text(LogStore.line(entry))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color(entry.kind))
                    .textSelection(.enabled)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .id(entry.id)
            }
            .listStyle(.plain)
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: log.entries.last?.id) { _, _ in
                if follow { scrollToEnd(proxy) }
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Show", selection: $only) {
                        Text("Everything").tag(LogStore.Kind?.none)
                        ForEach(LogStore.Kind.allCases) { kind in
                            Text(kind.title).tag(LogStore.Kind?.some(kind))
                        }
                    }
                    Toggle("Follow new lines", isOn: $follow)
                    Button {
                        UIPasteboard.general.string = log.export()
                    } label: {
                        Label("Copy all", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        log.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                ShareLink(item: log.export()) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func color(_ kind: LogStore.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .tx: return .cyan
        case .rx: return .green
        case .error: return .red
        }
    }
}
