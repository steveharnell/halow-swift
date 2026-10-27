import SwiftUI
import AppKit
import HaLowCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HaLowSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BridgeModel()

    var body: some Scene {
        Window("HaLow Swift", id: "main") {
            BridgeWindow(model: model)
                .frame(minWidth: 900, minHeight: 650)
                .task { model.scan() }
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan for Bridges") { model.scan() }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(model.isBusy)
                Button("Refresh Bridge") { model.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.isBusy || model.selected == nil)
                Button("Export Snapshot…") { model.exportSnapshot() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.isBusy || !model.hasResults)
            }
        }
    }
}

private struct BridgeWindow: View {
    @ObservedObject var model: BridgeModel
    private let accent = Color(red: 0.02, green: 0.48, blue: 0.48)

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 254)
            Divider()
            VStack(spacing: 0) {
                if let message = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help("Dismiss message")
                    }
                    .padding(14).background(Color.orange.opacity(0.08))
                    Divider()
                }
                if let device = model.selected {
                    overview(device: device)
                } else { emptyState }
                Divider()
                statusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .toolbar {
            ToolbarItemGroup {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isBusy || model.selected == nil)
                    .help("Read the current bridge settings (⌘R)")
                Button { model.exportSnapshot() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(model.isBusy || !model.hasResults)
                    .help("Export a snapshot of the current readings")
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 43, height: 43)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("HaLow Swift").font(.system(size: 19, weight: .semibold))
                    Text("Bridge manager").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 24).padding(.bottom, 29)

            Text("NETWORK ADAPTER").font(.system(size: 10, weight: .semibold))
                .tracking(1).foregroundStyle(.secondary).padding(.bottom, 8)
            Picker("Network adapter", selection: $model.adapterID) {
                if model.adapters.isEmpty { Text("No active adapters").tag("") }
                ForEach(model.adapters) { adapter in Text(adapter.label).tag(adapter.id) }
            }
            .labelsHidden().disabled(model.isBusy)
            .onChange(of: model.adapterID) { _ in model.scan() }
            if let adapter = model.adapter {
                Text(adapter.addresses.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).padding(.top, 5)
            }
            Button { model.scan() } label: {
                Label("Scan for bridges", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).disabled(model.isBusy)
            .padding(.top, 16).padding(.bottom, 26)

            HStack {
                Text("BRIDGES").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text("\(model.devices.count)").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }.foregroundStyle(.secondary).padding(.bottom, 10)

            if model.devices.isEmpty {
                Text(model.isBusy ? "Searching this adapter…" : "Discovered bridges will appear here.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(model.devices, id: \.text) { device in
                            Button { model.select(device) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "network").font(.system(size: 19))
                                        .foregroundStyle(model.selectedID == device.text ? accent : .secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("HaLow Bridge").font(.system(size: 13, weight: .medium))
                                        Text(device.text).font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.selectedID == device.text {
                                        Circle().fill(accent).frame(width: 6, height: 6)
                                    }
                                }
                                .padding(12).contentShape(Rectangle())
                                .background(model.selectedID == device.text ? accent.opacity(0.1) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain).disabled(model.isBusy)
                        }
                    }
                }
            }
            Spacer(minLength: 20)
            HStack(spacing: 7) {
                Image(systemName: "cable.connector").foregroundStyle(accent)
                Text("Local Ethernet connection").font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
        .background(.regularMaterial)
    }

    private func overview(device: MAC) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewHeader(device: device)
                metrics
                networkCard
                if model.wirelessConnected == false { disconnectedNotice }
                if model.hasResults { responseDetails }
            }
            .padding(26)
            .frame(maxWidth: 950)
            .frame(maxWidth: .infinity)
        }
    }

    private func overviewHeader(device: MAC) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bridge overview").font(.system(size: 28, weight: .semibold))
                HStack(spacing: 7) {
                    Text(device.text).font(.system(size: 12, design: .monospaced))
                    Text("·").foregroundStyle(.tertiary)
                    Text(model.adapterID).font(.system(size: 12))
                }.foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            connectionBadge.padding(.top, 5)
        }
    }

    private var metrics: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                MetricCard(title: "Device role", value: model.role,
                           subtitle: "Wireless operating mode", icon: "arrow.left.arrow.right", accent: accent)
                MetricCard(title: "Bandwidth", value: model.bandwidth,
                           subtitle: "Radio channel width", icon: "waveform.path", accent: accent)
            }
            HStack(spacing: 14) {
                MetricCard(title: "Transmit power", value: model.power,
                           subtitle: "Configured radio power", icon: "antenna.radiowaves.left.and.right", accent: accent)
                MetricCard(title: "Security", value: model.security,
                           subtitle: "Wireless authentication", icon: "lock.shield", accent: accent)
            }
        }
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: "wifi").font(.system(size: 17)).foregroundStyle(accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Wireless network").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(model.ssid).font(.system(size: 19, weight: .medium)).textSelection(.enabled)
                }
                Spacer()
            }
            Divider()
            HStack(alignment: .center, spacing: 14) {
                Text("Channels").font(.system(size: 12)).foregroundStyle(.secondary)
                if model.channels.isEmpty { Text("—").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.channels, id: \.self) { channel in
                        Text(channel).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }.padding(20).cardStyle()
    }

    private var disconnectedNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link.badge.plus").font(.system(size: 18)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text("Waiting for a wireless partner").font(.system(size: 13, weight: .medium))
                Text("The bridge is responding over Ethernet. Its wireless link is currently disconnected.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(16).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var responseDetails: some View {
        DisclosureGroup("Response details") {
            VStack(alignment: .leading, spacing: 13) {
                ForEach(model.readings, id: \.command) { reading in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(BridgeModel.fieldName(reading.command)).font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(reading.status == "received" ? "Received" : reading.status.replacingOccurrences(of: "_", with: " "))
                                .font(.caption).foregroundStyle(reading.status == "received" ? Color.secondary : Color.orange)
                        }
                        Text(reading.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No response" :
                                reading.response.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 14)
        }
        .font(.system(size: 12, weight: .medium)).padding(17).cardStyle()
    }

    private var connectionBadge: some View {
        let color: Color = model.wirelessConnected == true ? .green : (model.wirelessConnected == false ? .orange : .secondary)
        let text = model.wirelessConnected == true ? "Wireless connected" :
            (model.wirelessConnected == false ? "Wireless disconnected" : (model.isBusy ? "Checking link…" : "Link unavailable"))
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color).padding(.horizontal, 11).padding(.vertical, 8)
        .background(color.opacity(0.09), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: model.isBusy ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 48, weight: .light)).foregroundStyle(accent)
                .frame(width: 100, height: 100)
                .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 25))
            Text(model.isBusy ? "Finding your bridge" : (model.hasScanned ? "No bridges found" : "Connect your HaLow bridge"))
                .font(.system(size: 23, weight: .semibold))
            Text(model.isBusy ? "Searching the selected network adapter." :
                    "Connect a powered bridge by Ethernet, select its adapter, and scan.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 350)
            if model.isBusy { ProgressView().controlSize(.small) }
            else { Button("Scan for bridges") { model.scan() }.buttonStyle(.borderedProminent) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 9) {
            if model.isBusy {
                ProgressView().controlSize(.mini)
                Text(model.activity).font(.system(size: 11)).foregroundStyle(.secondary)
                ProgressView(value: model.progress).frame(width: 80)
                Spacer()
                Button("Stop") { model.cancel() }.buttonStyle(.borderless).font(.system(size: 11))
            } else {
                Image(systemName: model.hasResults ? "checkmark.circle" : "circle.dotted")
                    .font(.system(size: 11)).foregroundStyle(model.hasResults ? accent : .secondary)
                Text(model.activity).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let date = model.refreshedAt {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }.padding(.horizontal, 20).frame(height: 38)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(accent.opacity(0.85))
            }
            Text(value).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        self.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.055)))
    }
}
