import SwiftUI
import UIKit

struct FormView: View {
    @EnvironmentObject var appState: AppState
    @Binding var editState: EditState?
    var onSaved: () -> Void

    @State private var date: Date? = nil
    @State private var time: Date? = nil
    @State private var bankId: UUID? = nil
    @State private var accountId: UUID? = nil
    @State private var opId: UUID? = nil
    @State private var categoryId: UUID? = nil
    @State private var subcategoryId: UUID? = nil
    @State private var personName: String = ""
    @State private var amountText: String = ""
    @State private var comment: String = ""
    @State private var errorText: String = ""
    @State private var showPersonPicker = false
    @State private var savedBanner = false

    var accounts: [Account] {
        guard let bankId else { return [] }
        return appState.data.accounts.filter { $0.bankId == bankId }
    }
    var categories: [Category] {
        guard let opId else { return [] }
        return appState.data.categories.filter { $0.opId == opId }
    }
    var subcategories: [Subcategory] {
        guard let categoryId else { return [] }
        return appState.data.subcategories.filter { $0.catId == categoryId }
    }

    var isEditing: Bool {
        if case .edit = editState { return true }
        return false
    }
    var isDuplicating: Bool {
        if case .duplicate = editState { return true }
        return false
    }

    // Зависимые списки: при РУЧНОЙ смене банка сбрасывается счёт, при смене
    // операции — категория и подкатегория. Сброс сделан в самих привязках,
    // а не через .onChange, иначе при загрузке операции на редактирование
    // .onChange срабатывал позже и стирал только что подставленные значения.
    private var bankBinding: Binding<UUID?> {
        Binding(get: { bankId }, set: { newValue in
            if newValue != bankId { accountId = nil }
            bankId = newValue
        })
    }
    private var opBinding: Binding<UUID?> {
        Binding(get: { opId }, set: { newValue in
            if newValue != opId { categoryId = nil; subcategoryId = nil }
            opId = newValue
        })
    }
    private var categoryBinding: Binding<UUID?> {
        Binding(get: { categoryId }, set: { newValue in
            if newValue != categoryId { subcategoryId = nil }
            categoryId = newValue
        })
    }

    var body: some View {
        Form {
            if editState != nil {
                Section {
                    HStack {
                        Label(isEditing ? "Редактирование операции" : "Копия операции",
                              systemImage: isEditing ? "pencil" : "doc.on.doc")
                            .font(.footnote).foregroundStyle(Color.accentColor)
                        Spacer()
                        Button("Отменить") { resetAll() }
                            .font(.footnote)
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("Когда") {
                OptionalPickerField(label: "Дата", value: $date, placeholder: "Выбрать") { b in
                    DatePicker("", selection: b, displayedComponents: .date).labelsHidden()
                }
                OptionalPickerField(label: "Время", value: $time, placeholder: "Выбрать") { b in
                    DatePicker("", selection: b, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }

            Section("Откуда") {
                Picker("Банк", selection: bankBinding) {
                    Text("— выберите —").tag(UUID?.none)
                    ForEach(appState.data.banks) { b in
                        Text(b.name).tag(Optional(b.id))
                    }
                }
                Picker("Счёт", selection: $accountId) {
                    Text(accounts.isEmpty && bankId != nil ? "— нет счетов —" : "— выберите —").tag(UUID?.none)
                    ForEach(accounts) { a in
                        Text(a.name).tag(Optional(a.id))
                    }
                }
                .disabled(bankId == nil)
            }

            Section("Что") {
                Picker("Операция", selection: opBinding) {
                    Text("— выберите —").tag(UUID?.none)
                    ForEach(appState.data.optypes) { o in
                        Text(o.name).tag(Optional(o.id))
                    }
                }
                Picker("Категория", selection: categoryBinding) {
                    Text(categories.isEmpty && opId != nil ? "— нет категорий —" : "— выберите —").tag(UUID?.none)
                    ForEach(categories) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                .disabled(opId == nil)
                Picker("Подкатегория", selection: $subcategoryId) {
                    Text(subcategories.isEmpty && categoryId != nil ? "— нет подкатегорий —" : "— выберите —").tag(UUID?.none)
                    ForEach(subcategories) { s in
                        Text(s.name).tag(Optional(s.id))
                    }
                }
                .disabled(categoryId == nil)

                Button {
                    showPersonPicker = true
                } label: {
                    HStack {
                        Text("Лицо").foregroundStyle(.primary)
                        Spacer()
                        Text(personName.isEmpty ? "Не выбрано" : personName)
                            .foregroundStyle(personName.isEmpty ? Color.secondary : Color.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("personButton")
            }

            Section("Сколько") {
                HStack {
                    TextField("Сумма", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                        .accessibilityIdentifier("amountField")
                    Text("₽").foregroundStyle(.secondary)
                }
                TextField("Комментарий (необязательно)", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
            }

            if !errorText.isEmpty {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button(action: save) {
                    Text(isEditing ? "Сохранить изменения" : (isDuplicating ? "Сохранить как новую" : "Сохранить"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("saveButton")
            }
        }
        .navigationTitle(isEditing ? "Редактирование" : "Новая операция")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { hideKeyboard() }
            }
        }
        .overlay(alignment: .top) {
            if savedBanner {
                Label("Операция сохранена", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .foregroundStyle(.green)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showPersonPicker) {
            PersonPickerView(selectedName: $personName)
                .environmentObject(appState)
        }
        .onAppear { loadFromEditStateIfNeeded() }
        .onChange(of: editState) { _, _ in loadFromEditStateIfNeeded() }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func loadFromEditStateIfNeeded() {
        guard let editState else { return }
        let targetId: UUID
        switch editState {
        case .edit(let id): targetId = id
        case .duplicate(let id): targetId = id
        }
        guard let rec = appState.data.operations.first(where: { $0.id == targetId }) else { return }
        fillForm(from: rec)
    }

    func fillForm(from rec: OperationRecord) {
        date = DateFmt.day(from: rec.date)
        time = DateFmt.time(from: rec.time)
        // Прямое присваивание @State (минуя привязки) — зависимые поля не сбрасываются
        let bank = appState.data.banks.first(where: { $0.name == rec.bank })
        bankId = bank?.id
        accountId = appState.data.accounts.first(where: { $0.name == rec.account && $0.bankId == bank?.id })?.id
        let op = appState.data.optypes.first(where: { $0.name == rec.operation })
        opId = op?.id
        let cat = appState.data.categories.first(where: { $0.name == rec.category && $0.opId == op?.id })
        categoryId = cat?.id
        subcategoryId = appState.data.subcategories.first(where: { $0.name == rec.subcategory && $0.catId == cat?.id })?.id
        personName = rec.person
        amountText = Money.editString(rec.amount)
        comment = rec.comment
        errorText = ""

        var lost: [String] = []
        if bankId == nil { lost.append("банк «\(rec.bank)»") }
        if accountId == nil { lost.append("счёт «\(rec.account)»") }
        if opId == nil { lost.append("операция «\(rec.operation)»") }
        if categoryId == nil { lost.append("категория «\(rec.category)»") }
        if !rec.subcategory.isEmpty && subcategoryId == nil { lost.append("подкатегория «\(rec.subcategory)»") }
        if !lost.isEmpty {
            errorText = "В справочниках больше нет: " + lost.joined(separator: ", ") + ". Выберите заново."
        }
    }

    func resetAll() {
        editState = nil
        date = nil; time = nil
        bankId = nil; accountId = nil
        opId = nil; categoryId = nil; subcategoryId = nil
        personName = ""; amountText = ""; comment = ""
        errorText = ""
    }

    func save() {
        errorText = ""
        var missing: [String] = []

        if date == nil { missing.append("Дата") }
        let bank = bankId.flatMap { id in appState.data.banks.first(where: { $0.id == id }) }
        if bank == nil { missing.append("Банк") }
        let account = accountId.flatMap { id in appState.data.accounts.first(where: { $0.id == id }) }
        if account == nil { missing.append("Счёт") }
        let op = opId.flatMap { id in appState.data.optypes.first(where: { $0.id == id }) }
        if op == nil { missing.append("Операция") }
        let category = categoryId.flatMap { id in appState.data.categories.first(where: { $0.id == id }) }
        if category == nil { missing.append("Категория") }
        let subcategory = subcategoryId.flatMap { id in appState.data.subcategories.first(where: { $0.id == id }) }

        let amount = Money.parse(amountText)
        if amount == nil || amount! <= 0 { missing.append("Сумма") }

        guard missing.isEmpty, let date, let bank, let account, let op, let category, let amount else {
            errorText = "Заполните обязательные поля: " + missing.joined(separator: ", ")
            return
        }

        let dateStr = DateFmt.dayString(date)
        let timeStr = time.map { DateFmt.timeString($0) } ?? ""
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        func makeRecord(id: UUID = UUID(), createdAt: Double = Date().timeIntervalSince1970) -> OperationRecord {
            OperationRecord(id: id, date: dateStr, time: timeStr, bank: bank.name, account: account.name,
                            operation: op.name, category: category.name, subcategory: subcategory?.name ?? "",
                            person: personName, amount: amount, comment: trimmedComment, createdAt: createdAt)
        }

        switch editState {
        case .edit(let id):
            if let idx = appState.data.operations.firstIndex(where: { $0.id == id }) {
                let createdAt = appState.data.operations[idx].createdAt
                appState.data.operations[idx] = makeRecord(id: id, createdAt: createdAt)
            }
            appState.persist()
            resetAll()
            onSaved()
        case .duplicate:
            appState.data.operations.append(makeRecord())
            appState.persist()
            resetAll()
            onSaved()
        case nil:
            appState.data.operations.append(makeRecord())
            appState.persist()
            // Для быстрого ввода серии операций оставляем дату, банк, счёт и операцию,
            // очищаем только сумму, лицо и комментарий.
            amountText = ""; comment = ""; personName = ""
            showSavedBanner()
        }
    }

    private func showSavedBanner() {
        withAnimation { savedBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { savedBanner = false }
        }
    }
}

/// Экран выбора лица с живым поиском по буквам и добавлением нового лица
struct PersonPickerView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedName: String
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var filtered: [Person] {
        let sorted = appState.data.persons.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if trimmedQuery.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var exactMatchExists: Bool {
        appState.data.persons.contains { $0.name.compare(trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedName.isEmpty {
                    Button("Очистить выбор", role: .destructive) {
                        selectedName = ""
                        dismiss()
                    }
                }
                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Button {
                        appState.data.persons.append(Person(name: trimmedQuery))
                        appState.persist()
                        selectedName = trimmedQuery
                        dismiss()
                    } label: {
                        Label("Добавить «\(trimmedQuery)» в справочник", systemImage: "person.badge.plus")
                    }
                }
                ForEach(filtered) { p in
                    Button {
                        selectedName = p.name
                        dismiss()
                    } label: {
                        HStack {
                            Text(p.name).foregroundStyle(.primary)
                            Spacer()
                            if p.name == selectedName {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                if filtered.isEmpty && trimmedQuery.isEmpty {
                    Text("Справочник лиц пуст. Начните вводить имя в поиске, чтобы добавить.")
                        .foregroundStyle(.secondary).font(.footnote)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по имени")
            .navigationTitle("Выберите лицо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
