import Foundation

/// A single session activity entry from the relay server.
struct SessionMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Double
    let kind: String
    let content: String

    init(timestamp: Double, kind: String, content: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.content = content
    }

    var date: Date {
        Date(timeIntervalSince1970: timestamp)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    var icon: String {
        switch kind {
        case "assistant":     return "bubble.left.fill"
        case "tool_call":     return "terminal.fill"
        case "tool_output":   return "doc.text.fill"
        case "task_complete": return "checkmark.circle.fill"
        case "error":         return "exclamationmark.triangle.fill"
        case "test_result":   return "testtube.2"
        case "session_start": return "play.circle.fill"
        case "session_end":   return "stop.circle.fill"
        case "tts_request":   return "speaker.wave.2.fill"
        default:              return "text.alignleft"
        }
    }

    var iconColor: String {
        switch kind {
        case "assistant":     return "blue"
        case "tool_call":     return "orange"
        case "tool_output":   return "gray"
        case "task_complete": return "green"
        case "error":         return "red"
        case "test_result":   return "purple"
        case "session_start": return "green"
        case "session_end":   return "red"
        case "tts_request":   return "pink"
        default:              return "secondary"
        }
    }

    // Custom Codable to handle missing id from server
    enum CodingKeys: String, CodingKey {
        case timestamp, kind, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.timestamp = try container.decode(Double.self, forKey: .timestamp)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.content = try container.decode(String.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
    }
}
