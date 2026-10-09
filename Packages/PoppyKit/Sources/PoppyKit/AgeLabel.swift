import Foundation

/// Idade compacta de um item ("agora", "13 min", "2 h", "3 d"). Substitui o
/// `Text(style: .relative)` do sistema, que sai verboso ("13 minutes, 44 seconds").
public enum AgeLabel {
    public static func text(since: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(since)))
        switch s {
        case ..<60: return "agora"
        case ..<3600: return "\(s / 60) min"
        case ..<86_400: return "\(s / 3600) h"
        default: return "\(s / 86_400) d"
        }
    }
}
