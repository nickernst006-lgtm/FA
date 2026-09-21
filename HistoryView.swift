import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @Binding var editState: EditState?
    var goToForm: () -> Void

    @State private var filterBankId: UUID? = nil
    @State private var filterCategoryName: String = ""
    @State private var filterFrom: Date? = nil
    @State private var filterTo: Date? = nil
    @State private var searchText: String = ""
    @State private var filtersExpanded = false
    @State private var showClearConfirm = false
    @State private var exportFile: ExportFile? = nil
    @State private var deleteTarget: OperationRecord? = nil

    var hasActiveFilters: Bool {
        filterBankId != nil || !filterCategoryName.isEmpty || filterFrom != nil || filterTo != nil
    }

    var filteredSorted: [OperationRecord] {
        var items = appState.data.operations

        if let filterBankId, let bank = appState.data.banks.first(where: { $0.id == filterBankId }) {
            items = items.filter { $0.bank == bank.name }
        }
        if !filterCategoryName.isEmpty {
            items = items.filter { $0.category == filterCategoryName }
        }
        if let from = filterFrom {
            let s = DateFmt.dayString(from)
            items = items.filter { $0.date >= s }
        }
        if let to = filterTo {
            let s = DateFmt.dayString(to)
            items = items.filter { $0.date <= s }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter { r in
                [r.person, r.comment, r.category, r.subcategory, r.bank, r.account, r.operation]
                    .contains { $0.localizedCaseInsensitiveContains(q) }
                || Money.format(r.amount).contains(q)
            }
        }

        return items.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            if a.time != b.time { return a.time > b.time }
            return a.createdAt > b.createdAt
        }
    }

    struct DayGroup: Identifiable {
        let day: String
        var items: [OperationRecord]
        var id: String { day }
    }

    /// Операции, сгруппированные по дням (новые сверху)
    func groupByDay(_ sorted: [OperationRecord]) -> [DayGroup] {
        var result: [DayGroup] = []
        for rec in sorted {
            if let last = result.last, last.day == rec.date {
                result[result.count - 1].items.append(rec)
            } else {
                result.append(DayGroup(day: rec.date, items: [rec]))
            }
        }
        return result
    }

    var categoryNames: [String] {
        Array(Set(appState.data.categories.map { $0.name }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let items = filteredSorted
        let groups = groupByDay(items)
        List {
            Section {
                DisclosureGroup(isExpanded: $filtersExpanded) {
                    Picker("Банк", selection: $filterBankId) {
                        Text("Все").tag(UUID?.none)
                        ForEach(appState.data.banks) { b in Text(b.name).tag(Optional(b.id)) }
                    }
                    Picker("Категория", selection: $filterCategoryName) {
                        Text("Все").tag("")
                        ForEach(categoryNames, id: \.self) { c in Text(c).tag(c) }
                    }
                    OptionalPickerField(label: "Дата с", value: $filterFrom, placeholder: "Не выбрано") { b in
                        DatePicker("", selection: b, displayedComponents: .date).labelsHidden()
                    }
                    OptionalPickerField(label: "Дата по", value: $filterTo, placeholder: "Не выбрано") { b in
                        DatePicker("", selection: b, displayedComponents: .date).labelsHidden()
                    }
                    if hasActiveFilters {
                        Button("Сбросить фильтры", role: .destructive) {
                            filterBankId = nil; filterCategoryName = ""; filterFrom = nil; filterTo = nil
                        }
                    }
                } label: {
                    Label(hasActiveFilters ? "Фильтры (включены)" : "Фильтры",
                          systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }

            if items.isEmpty {
                Section {
                    Text(appState.data.operations.isEmpty ? "Операций пока нет" : "Записей не найдено")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    summaryRow(items)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { rec in
                            RecordRow(
                                rec: rec,
                                onEdit: { edit(rec) },
                                onDuplicate: { duplicate(rec) },
                                onDelete: { deleteTarget = rec }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteTarget = rec } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { edit(rec) } label: { Label("Изменить", systemImage: "pencil") }
                                    .tint(.blue)
                                Button { duplicate(rec) } label: { Label("Копия", systemImage: "doc.on.doc") }
                                    .tint(.orange)
                            }
                        }
                    } header: {
                        Text(DateFmt.display(group.day))
                    }
                }
            }

            Section {
                Button {
                    export(appState.data.operations)
                } label: {
                    Label("Экспорт всех в Excel (\(appState.data.operations.count))", systemImage: "square.and.arrow.up")
                }
                .disabled(appState.data.operations.isEmpty)
                if hasActiveFilters || !searchText.isEmpty {
                    Button {
                        export(items)
                    } label: {
                        Label("Экспорт найденных (\(items.count))", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(items.isEmpty)
                }
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("Очистить базу", systemImage: "trash")
                }
                .disabled(appState.data.operations.isEmpty)
            }
        }
        .navigationTitle("История")
        .searchable(text: $searchText, prompt: "Лицо, комментарий, сумма…")
        .alert("Удалить запись?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Отмена", role: .cancel) { deleteTarget = nil }
            Button("Удалить", role: .destructive) {
                if let t = deleteTarget {
                    appState.data.operations.removeAll { $0.id == t.id }
                    if editState == .edit(t.id) || editState == .duplicate(t.id) { editState = nil }
                    appState.persist()
                }
                deleteTarget = nil
            }
        } message: {
            Text("Эта операция будет удалена без возможности восстановления.")
        }
        .alert("Очистить базу?", isPresented: $showClearConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                appState.data.operations.removeAll()
                editState = nil
                appState.persist()
            }
        } message: {
            Text("Будут безвозвратно удалены все \(appState.data.operations.count) операций. Справочники останутся. Сначала сделайте экспорт в Excel, если данные нужны.")
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(fileURL: file.url) { exportFile = nil }
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    func summaryRow(_ items: [OperationRecord]) -> some View {
        let income = items.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
        let expense = items.filter { $0.isExpense }.reduce(0) { $0 + $1.amount }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Записей").font(.caption2).foregroundStyle(.secondary)
                Text("\(items.count)").font(.subheadline.bold())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Доходы").font(.caption2).foregroundStyle(.secondary)
                Text("+" + Money.format(income)).font(.subheadline.monospacedDigit()).foregroundStyle(.green)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("Расходы").font(.caption2).foregroundStyle(.secondary)
                Text("−" + Money.format(expense)).font(.subheadline.monospacedDigit()).foregroundStyle(.red)
            }
            .padding(.leading, 12)
        }
    }

    func edit(_ rec: OperationRecord) {
        editState = .edit(rec.id)
        goToForm()
    }

    func duplicate(_ rec: OperationRecord) {
        editState = .duplicate(rec.id)
        goToForm()
    }

    func export(_ operations: [OperationRecord]) {
        guard !operations.isEmpty else { return }
        let sorted = operations.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.time != b.time { return a.time < b.time }
            return a.createdAt < b.createdAt
        }
        let xlsxData = XLSXExporter.buildXLSX(operations: sorted)
        let filename = "operations_\(DateFmt.fileStamp(Date())).xlsx"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try xlsxData.write(to: tmpURL, options: [.atomic, .completeFileProtection])
            exportFile = ExportFile(url: tmpURL)
        } catch {
            appState.saveError = "Не удалось подготовить файл Excel: \(error.localizedDescription)"
        }
    }
}

struct RecordRow: View {
    let rec: OperationRecord
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var amountColor: Color {
        rec.isIncome ? .green : (rec.isExpense ? .red : .primary)
    }
    var amountSign: String {
        rec.isIncome ? "+" : (rec.isExpense ? "−" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rec.category)\(rec.subcategory.isEmpty ? "" : " · " + rec.subcategory)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(rec.time.isEmpty ? "" : rec.time + " · ")\(rec.bank) / \(rec.account) · \(rec.operation)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !rec.person.isEmpty {
                        Label(rec.person, systemImage: "person").font(.caption)
                    }
                    if !rec.comment.isEmpty {
                        Text(rec.comment).italic().font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(amountSign + Money.format(rec.amount))
                    .font(.body.monospacedDigit().bold())
                    .foregroundStyle(amountColor)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 18) {
                Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
                Button(action: onDuplicate) { Label("Копия", systemImage: "doc.on.doc") }
                Button(role: .destructive, action: onDelete) { Label("Удалить", systemImage: "trash") }
                    .foregroundStyle(.red)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
