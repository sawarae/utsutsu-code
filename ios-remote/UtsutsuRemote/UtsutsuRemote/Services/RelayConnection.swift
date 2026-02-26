import Foundation
import Combine

/// Manages the WebSocket connection to the relay server.
@MainActor
final class RelayConnection: ObservableObject {
    @Published var isConnected = false
    @Published var sessionActive = false
    @Published var messages: [SessionMessage] = []
    @Published var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var serverURL: URL?

    private let maxMessages = 500

    // MARK: - Connection

    func connect(host: String, port: Int = 8765) {
        disconnect()

        guard let url = URL(string: "ws://\(host):\(port)") else {
            lastError = "Invalid URL"
            return
        }
        serverURL = url

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        isConnected = true
        lastError = nil
        receiveMessage()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    // MARK: - Send

    func sendTTS(message: String, emotion: Emotion) {
        let payload: [String: Any] = [
            "type": "tts",
            "data": [
                "message": message,
                "emotion": emotion.rawValue,
            ]
        ]
        send(payload)
    }

    func sendPing() {
        send(["type": "ping"])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage() // continue listening
                case .failure(let error):
                    self.handleDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "status":
            if let statusData = json["data"] as? [String: Any] {
                sessionActive = statusData["session_active"] as? Bool ?? false
            }

        case "session_line":
            if let lineData = json["data"] as? [String: Any] {
                if let msg = parseSessionMessage(lineData) {
                    appendMessage(msg)
                }
            }

        case "session_lines":
            if let lines = json["data"] as? [[String: Any]] {
                let parsed = lines.compactMap { parseSessionMessage($0) }
                messages.append(contentsOf: parsed)
                trimMessages()
            }

        case "notify":
            if let notifyData = json["data"] as? [String: Any] {
                let title = notifyData["title"] as? String ?? "utsutsu-code"
                let body = notifyData["body"] as? String ?? ""
                NotificationService.shared.scheduleLocal(title: title, body: body)
            }

        case "pong":
            break // ping response

        case "tts_result":
            break // TTS confirmation

        default:
            break
        }
    }

    private func parseSessionMessage(_ dict: [String: Any]) -> SessionMessage? {
        guard let timestamp = dict["timestamp"] as? Double,
              let kind = dict["kind"] as? String,
              let content = dict["content"] as? String else { return nil }
        return SessionMessage(timestamp: timestamp, kind: kind, content: content)
    }

    private func appendMessage(_ msg: SessionMessage) {
        messages.append(msg)
        trimMessages()
    }

    private func trimMessages() {
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    // MARK: - Reconnect

    private func handleDisconnect(error: Error) {
        isConnected = false
        lastError = error.localizedDescription
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            guard !Task.isCancelled, let url = serverURL else { return }
            connect(host: url.host ?? "localhost", port: url.port ?? 8765)
        }
    }

    deinit {
        reconnectTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
    }
}
