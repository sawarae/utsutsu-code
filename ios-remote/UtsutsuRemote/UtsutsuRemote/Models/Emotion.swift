import SwiftUI

/// Available emotions for TTS requests, matching mascot/config/emotions.toml.
enum Emotion: String, CaseIterable, Identifiable {
    case gentle  = "Gentle"
    case joy     = "Joy"
    case blush   = "Blush"
    case trouble = "Trouble"
    case singing = "Singing"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle:  return "穏やか"
        case .joy:     return "喜び"
        case .blush:   return "照れ"
        case .trouble: return "困惑"
        case .singing: return "ノリノリ"
        }
    }

    var emoji: String {
        switch self {
        case .gentle:  return "😊"
        case .joy:     return "😆"
        case .blush:   return "😳"
        case .trouble: return "😰"
        case .singing: return "🎵"
        }
    }

    var color: Color {
        switch self {
        case .gentle:  return .blue
        case .joy:     return .yellow
        case .blush:   return .pink
        case .trouble: return .purple
        case .singing: return .orange
        }
    }
}
