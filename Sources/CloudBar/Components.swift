import AppKit
import CloudCore
import SwiftUI

extension SiteRow.State {
    var color: Color {
        switch self {
        case .running: .green
        case .stopped: .secondary
        case .broken: .orange
        }
    }

    var shortLabel: String {
        switch self {
        case .running(_, true): "Running"
        case .running(_, false): "Running by hand"
        case .stopped: "Stopped"
        case .broken: "Needs attention"
        }
    }
}

struct StatusDot: View {
    let state: SiteRow.State
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(state.color.gradient)
            .frame(width: size, height: size)
            .shadow(color: state.isRunning ? .green.opacity(0.7) : .clear, radius: size * 0.6)
    }
}

/// Running / Stopped capsule on glass, tinted by state.
struct StatusPill: View {
    let state: SiteRow.State

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(state: state, size: 7)
            Text(state.shortLabel).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassEffect(.regular.tint(state.isRunning ? .green.opacity(0.25) : .clear), in: .capsule)
    }
}

/// A translucent card with an icon, a caption and a value.
struct InfoCard<Value: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            value
                .font(.body.weight(.medium))
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension SiteRow {
    var colos: String? {
        guard let tunnel, tunnel.isConnected else { return nil }
        return Set(tunnel.connections.map(\.colo_name)).sorted().map { $0.uppercased() }.joined(separator: " · ")
    }

    var currentDomain: String { project?.domain ?? String(domain.drop { $0 != "." }.dropFirst()) }
}
