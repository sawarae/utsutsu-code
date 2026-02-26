import SwiftUI

/// Terminal-like view showing Claude Code session activity in real-time.
struct SessionView: View {
    @ObservedObject var connection: RelayConnection
    @State private var autoScroll = true
    @State private var filterKind: String? = nil

    private var filteredMessages: [SessionMessage] {
        guard let kind = filterKind else { return connection.messages }
        return connection.messages.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                statusBar

                // Filter chips
                filterBar

                // Session log
                if connection.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
            }
            .navigationTitle("ターミナル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        connection.messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(connection.messages.isEmpty)
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(connection.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(connection.isConnected ? "接続中" : "未接続")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if connection.sessionActive {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                    Text("セッション実行中")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text("\(connection.messages.count) 件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "すべて", isSelected: filterKind == nil) {
                    filterKind = nil
                }
                FilterChip(label: "ツール", isSelected: filterKind == "tool_call") {
                    filterKind = "tool_call"
                }
                FilterChip(label: "アシスタント", isSelected: filterKind == "assistant") {
                    filterKind = "assistant"
                }
                FilterChip(label: "エラー", isSelected: filterKind == "error") {
                    filterKind = "error"
                }
                FilterChip(label: "完了", isSelected: filterKind == "task_complete") {
                    filterKind = "task_complete"
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredMessages) { msg in
                        SessionLineView(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color.black)
            .onChange(of: connection.messages.count) { _, _ in
                if autoScroll, let last = filteredMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("セッションログがありません")
                .foregroundStyle(.secondary)
            if !connection.isConnected {
                Text("接続タブからサーバーに接続してください")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

// MARK: - Session Line

struct SessionLineView: View {
    let message: SessionMessage

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(message.timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.gray)
                .frame(width: 52, alignment: .leading)

            Image(systemName: message.icon)
                .font(.system(size: 10))
                .foregroundStyle(colorForKind)
                .frame(width: 14)

            Text(message.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColorForKind)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var colorForKind: Color {
        switch message.iconColor {
        case "blue":   return .blue
        case "orange": return .orange
        case "gray":   return .gray
        case "green":  return .green
        case "red":    return .red
        case "purple": return .purple
        case "pink":   return .pink
        default:       return .secondary
        }
    }

    private var textColorForKind: Color {
        switch message.kind {
        case "error":         return .red
        case "task_complete": return .green
        case "tool_call":     return .cyan
        case "assistant":     return .white
        case "tts_request":   return .pink
        default:              return Color(.lightGray)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple.opacity(0.2) : Color(.systemGray5))
                .foregroundStyle(isSelected ? .purple : .secondary)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    SessionView(connection: RelayConnection())
}
