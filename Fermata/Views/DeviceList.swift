import FermataCore
import SwiftUI

/// The priority lists as one SwiftUI List: click a row to use a device, drag to reorder.
struct DeviceList: View {
    @Environment(AppModel.self) private var model

    static let rowHeight: CGFloat = 36
    private static let headerHeight: CGFloat = 28
    private static let maximumHeight: CGFloat = 460

    var body: some View {
        let sections = lists.map { ($0, model.rows(for: $0)) }
        List {
            ForEach(sections, id: \.0) { list, rows in
                Text(list.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: Self.headerHeight, alignment: .bottom)
                if rows.isEmpty {
                    Text("No \(list.hiddenRole.title.lowercased()) connected")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .frame(height: Self.rowHeight)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    DeviceRowView(list: list, row: row, rank: index + 1)
                }
                .onMove { source, destination in
                    var uids = rows.map(\.id)
                    uids.move(fromOffsets: source, toOffset: destination)
                    model.reorder(list, to: uids)
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .environment(\.defaultMinListRowHeight, Self.headerHeight)
        // A List has no natural height; size it to its rows up to a limit.
        .frame(height: min(sections.reduce(8) { $0 + Self.headerHeight + CGFloat(max($1.1.count, 1)) * Self.rowHeight }, Self.maximumHeight))
        .animation(.snappy(duration: 0.2), value: sections.map(\.1))
    }

    private var lists: [PriorityList] {
        var lists: [PriorityList] = []
        if model.settings.mode == .speaker || !model.settings.isAutomatic { lists.append(.speakers) }
        if model.settings.mode == .headphone || !model.settings.isAutomatic { lists.append(.headphones) }
        lists.append(model.activeMicrophoneList)
        return lists
    }
}

private struct DeviceRowView: View {
    @Environment(AppModel.self) private var model
    let list: PriorityList
    let row: DeviceRow
    let rank: Int

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            DeviceIcon(symbol: row.symbol, isActive: row.isCurrent)
                .opacity(row.isConnected ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .lineLimit(1)
                    .foregroundStyle(row.isConnected && !row.isHidden ? .primary : .secondary)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(row.isMuted ? Color.red : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if isHovering {
                Menu("Options", systemImage: "ellipsis") { RowMenuItems(list: list, row: row) }
                    .labelStyle(.iconOnly)
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
            } else {
                Text(rank, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: DeviceList.rowHeight)
        .background(.primary.opacity(isHovering ? 0.07 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .onTapGesture {
            if row.isConnected { model.select(row.id, in: list) }
        }
        .contextMenu { RowMenuItems(list: list, row: row) }
        .help("Priority \(rank). Click to use, drag to reorder.")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private var status: String? {
        if row.isMuted { return "Muted" }
        if let lastSeen = row.lastSeen {
            return "Last connected \(lastSeen.formatted(.relative(presentation: .numeric, unitsStyle: .wide)))"
        }
        if row.isHidden { return "Hidden" }
        if row.isNeverAuto { return "Only when picked" }
        return nil
    }
}

/// The round icon macOS uses for devices in its Sound menu, filled with the accent color for
/// the device in use.
private struct DeviceIcon: View {
    let symbol: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? Color.white : .primary)
            .frame(width: 26, height: 26)
            .background(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.09)), in: .circle)
            .contentTransition(.symbolEffect(.replace))
    }
}

private struct RowMenuItems: View {
    @Environment(AppModel.self) private var model
    let list: PriorityList
    let row: DeviceRow

    var body: some View {
        if row.isConnected, !row.isCurrent {
            Button("Use Now", systemImage: "checkmark.circle") { model.select(row.id, in: list) }
            Divider()
        }

        switch list.category {
        case .headphone: Button("Treat as Speakers", systemImage: "hifispeaker") { model.setCategory(.speaker, for: row.id) }
        case .speaker: Button("Treat as Headphones", systemImage: "headphones") { model.setCategory(.headphone, for: row.id) }
        case nil: EmptyView()
        }

        Toggle("Never Choose Automatically", systemImage: "nosign", isOn: Binding(
            get: { row.isNeverAuto },
            set: { model.setNeverAuto($0, uid: row.id) }
        ))

        Divider()
        let listName = list.hiddenRole.title
        if row.isHidden {
            Button("Show in \(listName)", systemImage: "eye") { model.setHidden(false, uid: row.id, in: list.hiddenRole) }
        } else {
            Button("Hide from \(listName)", systemImage: "eye.slash") { model.setHidden(true, uid: row.id, in: list.hiddenRole) }
            if list.direction == .output {
                Button("Hide Everywhere", systemImage: "eye.slash.fill") { model.setHidden(true, uid: row.id, in: .speaker, .headphone) }
            }
        }

        if !row.isConnected {
            Button("Forget Device", systemImage: "trash", role: .destructive) { model.forget(row.id) }
        }
    }
}
