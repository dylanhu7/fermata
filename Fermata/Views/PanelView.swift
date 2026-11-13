import AppKit
import FermataCore
import ServiceManagement
import SwiftUI

/// The menu bar panel, laid out like a Control Center module: a titled switch on top,
/// then the device lists, with settings tucked into the footer.
struct PanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Header()
                .padding([.horizontal, .top], 14)
                .padding(.bottom, 12)

            if let notice = model.notice {
                NoticeBanner(text: notice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().padding(.horizontal, 14)

            DeviceList()

            Divider().padding(.horizontal, 14)
            Footer()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: 320)
        .animation(.snappy(duration: 0.2), value: model.settings.mode)
        .animation(.snappy(duration: 0.2), value: model.settings.isAutomatic)
        .animation(.snappy(duration: 0.2), value: model.isEditing)
        .animation(.snappy(duration: 0.2), value: model.notice)
    }
}

// MARK: - Header

private struct Header: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isAutomatic = model.settings.isAutomatic
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Automatic Switching")
                        .font(.headline)
                    Text(isAutomatic ? "Uses your highest-priority device" : "Devices only change when you pick one")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Toggle("Automatic Switching", isOn: Binding(get: { isAutomatic }, set: { model.setAutomatic($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if isAutomatic {
                ModeButtons()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }
}

/// Speakers or headphones: a capsule track with an accent pill that slides to the active mode.
private struct ModeButtons: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OutputCategory.allCases, id: \.self) { mode in
                let isSelected = model.settings.mode == mode
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.setMode(mode) }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: selection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

private struct NoticeBanner: View {
    @Environment(AppModel.self) private var model
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark") { model.dismissNotice() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 12))
    }
}

// MARK: - Footer

private struct Footer: View {
    @Environment(AppModel.self) private var model
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 12) {
            HiddenDevicesButton()
            Spacer()
            Button(model.isEditing ? "Done" : "Edit") { model.isEditing.toggle() }
                .fontWeight(model.isEditing ? .semibold : .regular)
                .foregroundStyle(model.isEditing ? Color.accentColor : .secondary)
                .help(model.isEditing ? "Hide disconnected devices" : "Show disconnected and hidden devices")

            Menu {
                Toggle("Mute Microphone", isOn: Binding(
                    get: { model.microphoneMute != nil },
                    set: { model.setMicrophoneMuted($0) }
                ))
                .keyboardShortcut("m", modifiers: [.option, .shift])
                Toggle("Microphones Follow Output", isOn: Binding(
                    get: { model.settings.micFollowsOutput },
                    set: { model.setMicFollowsOutput($0) }
                ))
                Divider()
                Toggle("Open at Login", isOn: $opensAtLogin)
                Divider()
                Button("Quit Fermata") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .onChange(of: opensAtLogin) { _, enabled in
            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            // The system can refuse (for example for a build run from Xcode); show what's true.
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.callout)
    }
}

private struct HiddenDevicesButton: View {
    @Environment(AppModel.self) private var model
    @State private var isShowing = false

    var body: some View {
        let hidden = model.hiddenDevices
        if !hidden.isEmpty, !model.isEditing {
            Button {
                isShowing.toggle()
            } label: {
                Label("\(hidden.count) Hidden", systemImage: "eye.slash")
            }
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hidden Devices")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    ForEach(hidden) { device in
                        HStack(spacing: 8) {
                            Image(systemName: device.role.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(device.name).lineLimit(1)
                                Text("From \(device.role.title.lowercased())").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button("Show") { model.setHidden(false, uid: device.uid, in: device.role) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(12)
                .frame(minWidth: 260)
            }
        }
    }
}
