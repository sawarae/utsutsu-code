import SwiftUI

/// View for sending TTS requests to Tsukuyomi-chan from iOS.
struct TtsRequestView: View {
    @ObservedObject var connection: RelayConnection
    @State private var message = ""
    @State private var selectedEmotion: Emotion = .gentle
    @State private var isSending = false
    @State private var showSentFeedback = false

    // Quick message presets
    private let presets: [(String, Emotion)] = [
        ("進捗どうですか？", .gentle),
        ("テスト走らせて", .gentle),
        ("ビルドお願いします", .gentle),
        ("お疲れ様です", .joy),
        ("ちょっと待ってね", .blush),
        ("やり直して", .trouble),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Mascot header
                    mascotHeader

                    // Emotion selector
                    emotionSelector

                    // Message input
                    messageInput

                    // Quick presets
                    presetButtons

                    // Recent TTS requests
                    recentRequests
                }
                .padding()
            }
            .navigationTitle("つくよみちゃんにお願い")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(sentFeedbackOverlay)
        }
    }

    // MARK: - Mascot Header

    private var mascotHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(selectedEmotion.color.opacity(0.15))
                    .frame(width: 80, height: 80)
                Text(selectedEmotion.emoji)
                    .font(.system(size: 40))
            }

            Text("つくよみちゃん")
                .font(.headline)

            if !connection.isConnected {
                Label("未接続", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Emotion Selector

    private var emotionSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("感情")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Emotion.allCases) { emotion in
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedEmotion = emotion
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(emotion.emoji)
                                .font(.title2)
                            Text(emotion.label)
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedEmotion == emotion
                                ? emotion.color.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(
                        selectedEmotion == emotion
                            ? emotion.color
                            : .secondary
                    )
                }
            }
            .padding(4)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Message Input

    private var messageInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("メッセージ")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("つくよみちゃんに伝えたいこと", text: $message)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(canSend ? Color.purple : Color.gray)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }

            Text("30文字以内・日本語で入力")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Presets

    private var presetButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("クイックメッセージ")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 8) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        message = preset.0
                        selectedEmotion = preset.1
                        sendMessage()
                    } label: {
                        Text(preset.0)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(.primary)
                    .disabled(!connection.isConnected)
                }
            }
        }
    }

    // MARK: - Recent Requests

    private var recentRequests: some View {
        let ttsMessages = connection.messages
            .filter { $0.kind == "tts_request" }
            .suffix(5)
            .reversed()

        return Group {
            if !ttsMessages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近のお願い")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(Array(ttsMessages)) { msg in
                        HStack {
                            Image(systemName: "speaker.wave.2")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(msg.content)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(msg.timeString)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Sent Feedback

    private var sentFeedbackOverlay: some View {
        Group {
            if showSentFeedback {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("送信しました！")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 10)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Logic

    private var canSend: Bool {
        connection.isConnected && !message.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, connection.isConnected else { return }

        isSending = true
        connection.sendTTS(message: text, emotion: selectedEmotion)
        message = ""
        isSending = false

        withAnimation(.spring(duration: 0.4)) {
            showSentFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSentFeedback = false
            }
        }
    }
}

#Preview {
    TtsRequestView(connection: RelayConnection())
}
