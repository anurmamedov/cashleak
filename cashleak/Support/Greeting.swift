import Foundation

/// The small hello at the top of Overview: "Morning, Anar".
///
/// From the phone's own clock and time zone, so it's right wherever the person
/// is, and the profile's first name — or no name at all, never "Hi, ." (D-032).
enum Greeting {

    enum Moment: Equatable {
        case morning, afternoon, evening, late

        /// 5:00–11:59, 12:00–16:59, 17:00–21:59, 22:00–4:59.
        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<22: self = .evening
            default: self = .late
            }
        }

        var symbol: String {
            switch self {
            case .morning: "sun.max"
            case .afternoon: "sun.min"
            case .evening: "moon"
            case .late: "moon.stars"
            }
        }

        var isDaytime: Bool { self == .morning || self == .afternoon }
    }

    static func text(for moment: Moment, firstName: String) -> String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (moment, name.isEmpty) {
        case (.morning, false): return "Morning, \(name)"
        case (.afternoon, false): return "Afternoon, \(name)"
        case (.evening, false): return "Evening, \(name)"
        case (.late, false): return "Late one, \(name)"
        case (.morning, true): return "Good morning"
        case (.afternoon, true): return "Good afternoon"
        case (.evening, true): return "Good evening"
        case (.late, true): return "Late one"
        }
    }

    static func moment(at date: Date, calendar: Calendar = .current) -> Moment {
        Moment(hour: calendar.component(.hour, from: date))
    }
}
