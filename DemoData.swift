#if DEBUG
import Foundation

/// Демо-данные ТОЛЬКО для автоматических скриншотов в облачных тестах.
/// Код существует лишь в отладочной сборке и включается специальным
/// параметром запуска "-uiTestDemo" — в обычной работе он не срабатывает никогда.
nonisolated enum DemoData {
    static func make() -> AppData {
        var d = AppData()
        let tinkoff = Bank(name: "Тинькофф"), sber = Bank(name: "Сбербанк")
        d.banks = [tinkoff, sber]
        d.accounts = [Account(name: "Основной", bankId: tinkoff.id),
                      Account(name: "Кредитка", bankId: tinkoff.id),
                      Account(name: "Зарплатный", bankId: sber.id)]
        let income = OperationType(name: "Доход"), expense = OperationType(name: "Расход")
        d.optypes = [income, expense]
        let salary = Category(name: "Зарплата", opId: income.id)
        let food = Category(name: "Еда", opId: expense.id)
        let home = Category(name: "Дом", opId: expense.id)
        let transport = Category(name: "Транспорт", opId: expense.id)
        d.categories = [salary, food, home, transport]
        d.subcategories = [Subcategory(name: "Кафе", catId: food.id),
                           Subcategory(name: "Продукты", catId: food.id),
                           Subcategory(name: "Коммуналка", catId: home.id),
                           Subcategory(name: "Такси", catId: transport.id)]
        d.persons = ["Иванов И.И.", "Петрова А.С.", "ООО «Ромашка»"].map { Person(name: $0) }

        var t: Double = 1_700_000_000
        func op(_ date: String, _ time: String, _ bank: String, _ acc: String, _ kind: String,
                _ cat: String, _ sub: String, _ person: String, _ amount: Double, _ comment: String = "") -> OperationRecord {
            t += 1
            return OperationRecord(date: date, time: time, bank: bank, account: acc, operation: kind,
                                   category: cat, subcategory: sub, person: person, amount: amount,
                                   comment: comment, createdAt: t)
        }
        d.operations = [
            op("2026-06-05", "10:00", "Сбербанк", "Зарплатный", "Доход", "Зарплата", "", "ООО «Ромашка»", 120000),
            op("2026-06-12", "19:30", "Тинькофф", "Основной", "Расход", "Еда", "Продукты", "", 8450.40),
            op("2026-07-05", "10:00", "Сбербанк", "Зарплатный", "Доход", "Зарплата", "", "ООО «Ромашка»", 120000),
            op("2026-07-20", "09:15", "Тинькофф", "Кредитка", "Расход", "Дом", "Коммуналка", "", 6230),
            op("2026-08-05", "10:00", "Сбербанк", "Зарплатный", "Доход", "Зарплата", "", "ООО «Ромашка»", 125000),
            op("2026-08-14", "13:40", "Тинькофф", "Основной", "Расход", "Еда", "Кафе", "Петрова А.С.", 2340, "Обед"),
            op("2026-09-05", "10:00", "Сбербанк", "Зарплатный", "Доход", "Зарплата", "", "ООО «Ромашка»", 125000),
            op("2026-09-15", "14:30", "Тинькофф", "Основной", "Расход", "Еда", "Кафе", "Иванов И.И.", 1234.56, "Обед с клиентом"),
            op("2026-09-15", "22:10", "Тинькофф", "Кредитка", "Расход", "Транспорт", "Такси", "", 780),
        ]
        return d
    }
}
#endif
