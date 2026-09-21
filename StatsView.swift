import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var appState: AppState

    enum Period: String, CaseIterable, Identifiable {
        case month = "Месяц"
        case year = "Год"
        case all = "Всё время"
        var id: String { rawValue }
    }
    @State private var period: Period = .all

    struct Total: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    struct MonthPoint: Identifiable {
        let month: String   // "2026-09"
        let kind: String    // "Доход" / "Расход"
        let value: Double
        var id: String { month + kind }
        /// "2026-09" → "09.26"
        var label: String {
            let parts = month.split(separator: "-")
            guard parts.count == 2 else { return month }
            return "\(parts[1]).\(parts[0].suffix(2))"
        }
    }

    var operations: [OperationRecord] {
        let today = DateFmt.dayString(Date())
        switch period {
        case .all: return appState.data.operations
        case .month:
            let prefix = String(today.prefix(7))
            return appState.data.operations.filter { $0.date.hasPrefix(prefix) }
        case .year:
            let prefix = String(today.prefix(4))
            return appState.data.operations.filter { $0.date.hasPrefix(prefix) }
        }
    }

    func totals(_ ops: [OperationRecord], key: (OperationRecord) -> String, limit: Int) -> [Total] {
        var dict: [String: Double] = [:]
        for op in ops { dict[key(op), default: 0] += op.amount }
        return dict.map { Total(name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0 }
    }

    func monthPoints(_ ops: [OperationRecord]) -> [MonthPoint] {
        var dict: [String: (income: Double, expense: Double)] = [:]
        for op in ops {
            guard op.date.count >= 7 else { continue }
            let m = String(op.date.prefix(7))
            var cur = dict[m] ?? (income: 0, expense: 0)
            if op.isIncome { cur.income += op.amount } else if op.isExpense { cur.expense += op.amount }
            dict[m] = cur
        }
        let months = dict.keys.sorted().suffix(12)
        var points: [MonthPoint] = []
        for m in months {
            let v = dict[m] ?? (income: 0, expense: 0)
            points.append(MonthPoint(month: m, kind: "Доход", value: v.income))
            points.append(MonthPoint(month: m, kind: "Расход", value: v.expense))
        }
        return points
    }

    var body: some View {
        let ops = operations
        let income = ops.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
        let expense = ops.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        let balance = income - expense
        let expenseByCategory = totals(ops.filter { $0.isExpense }, key: { $0.category }, limit: 8)
        let incomeByCategory = totals(ops.filter { $0.isIncome }, key: { $0.category }, limit: 8)
        let byAccount = totals(ops, key: { "\($0.bank) / \($0.account)" }, limit: 10)
        let byPerson = totals(ops.filter { !$0.person.isEmpty }, key: { $0.person }, limit: 8)
        let points = monthPoints(ops)

        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Итоги · \(ops.count) операций") {
                HStack {
                    statBox("Доходы", income, .green)
                    statBox("Расходы", expense, .red)
                    statBox("Баланс", balance, balance >= 0 ? .green : .red)
                }
            }

            if ops.isEmpty {
                Section {
                    Text("За этот период операций нет").foregroundStyle(.secondary)
                }
            } else {
                if period != .month && !points.isEmpty {
                    Section("Доходы и расходы по месяцам") {
                        Chart(points) { p in
                            BarMark(
                                x: .value("Месяц", p.label),
                                y: .value("Сумма", p.value)
                            )
                            .foregroundStyle(by: .value("Тип", p.kind))
                            .position(by: .value("Тип", p.kind))
                        }
                        .chartForegroundStyleScale(["Доход": Color.green, "Расход": Color.red])
                        .frame(height: 200)
                        .padding(.vertical, 6)
                    }
                }

                if !expenseByCategory.isEmpty {
                    Section("Расходы по категориям") { barList(expenseByCategory, color: .red) }
                }
                if !incomeByCategory.isEmpty {
                    Section("Доходы по категориям") { barList(incomeByCategory, color: .green) }
                }
                Section("Обороты по банкам и счетам") { barList(byAccount, color: .accentColor) }
                if !byPerson.isEmpty {
                    Section("Обороты по лицам") { barList(byPerson, color: .purple) }
                }
            }
        }
        .navigationTitle("Статистика")
    }

    func statBox(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(Money.format(value))
                .font(.footnote.monospacedDigit().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    func barList(_ items: [Total], color: Color) -> some View {
        let maxVal = max(items.map { $0.value }.max() ?? 1, 0.01)
        return ForEach(items) { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name.isEmpty ? "—" : item.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(Money.format(item.value)).font(.caption.monospacedDigit())
                }
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.75))
                        .frame(width: max(2, geo.size.width * CGFloat(item.value / maxVal)), height: 8)
                }
                .frame(height: 8)
            }
            .padding(.vertical, 2)
        }
    }
}
