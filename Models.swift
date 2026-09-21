import Foundation

// `nonisolated` — модели данных не привязаны к главному потоку.
// Это важно для Xcode 26: в новых проектах всё по умолчанию привязано к
// главному потоку (MainActor), и без этой пометки шифрование в фоне не собралось бы.

nonisolated struct Bank: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
}

nonisolated struct Account: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var bankId: UUID
}

nonisolated struct OperationType: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
}

nonisolated struct Category: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var opId: UUID
}

nonisolated struct Subcategory: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var catId: UUID
}

nonisolated struct Person: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
}

nonisolated struct OperationRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var date: String       // "yyyy-MM-dd"
    var time: String       // "HH:mm" или ""
    var bank: String
    var account: String
    var operation: String
    var category: String
    var subcategory: String
    var person: String
    var amount: Double
    var comment: String
    var createdAt: Double  // timestamp, для сортировки при равных датах и времени

    var isIncome: Bool { operation.localizedCaseInsensitiveContains("доход") }
    var isExpense: Bool { operation.localizedCaseInsensitiveContains("расход") }
}

nonisolated struct AppData: Codable, Equatable {
    var banks: [Bank] = []
    var accounts: [Account] = []
    var optypes: [OperationType] = []
    var categories: [Category] = []
    var subcategories: [Subcategory] = []
    var persons: [Person] = []
    var operations: [OperationRecord] = []
}

// MARK: - Форматирование дат

/// Даты и время всегда в фиксированном формате, независимо от настроек iPhone
/// (12/24-часовой формат, буддийский/японский календарь и т.п.).
nonisolated enum DateFmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    static func dayString(_ d: Date) -> String { make("yyyy-MM-dd").string(from: d) }
    static func timeString(_ d: Date) -> String { make("HH:mm").string(from: d) }
    static func fileStamp(_ d: Date) -> String { make("yyyy-MM-dd_HHmm").string(from: d) }
    static func day(from s: String) -> Date? { s.isEmpty ? nil : make("yyyy-MM-dd").date(from: s) }
    static func time(from s: String) -> Date? { s.isEmpty ? nil : make("HH:mm").date(from: s) }

    /// "2026-09-15" → "15.09.2026" для показа на экране
    static func display(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return s }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// "2026-09" → "Сентябрь 2026"
    static func monthTitle(_ ym: String) -> String {
        let names = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
                     "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return ym }
        return "\(names[m - 1]) \(parts[0])"
    }
}

// MARK: - Деньги

nonisolated enum Money {
    /// "1 234,56" — для показа на экране
    static func format(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Разбор введённой суммы: понимает "1234,56", "1 234.56", "1 234,5".
    /// Возвращает nil, если это не число.
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for sp in [" ", "\u{00A0}", "\u{202F}"] { s = s.replacingOccurrences(of: sp, with: "") }
        s = s.replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty,
              s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              s.filter({ $0 == "." }).count <= 1,
              let v = Double(s), v.isFinite else { return nil }
        return (v * 100).rounded() / 100
    }

    /// Сумма для подстановки в поле при редактировании: "50000" или "1234,56"
    static func editString(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.0f", value) }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
