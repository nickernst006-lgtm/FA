import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var deleteBankTarget: Bank? = nil
    @State private var deleteOpTarget: OperationType? = nil
    @State private var deleteCatTarget: Category? = nil
    @State private var deleteSubTarget: Subcategory? = nil
    @State private var deleteAccTarget: Account? = nil
    @State private var deletePersonTarget: Person? = nil

    private func exists(_ name: String, in names: [String]) -> Bool {
        names.contains { $0.compare(name, options: [.caseInsensitive]) == .orderedSame }
    }

    private func sortedByName<T>(_ items: [T], _ name: (T) -> String) -> [T] {
        items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Text("Переименование меняет название и в уже сохранённых операциях. Удаление из справочника сохранённые операции не затрагивает.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Банки и счета") {
                ForEach(appState.data.banks) { bank in
                    bankGroup(bank)
                }
                AddRow(placeholder: "Новый банк") { name in
                    guard !exists(name, in: appState.data.banks.map(\.name)) else { return }
                    appState.data.banks.append(Bank(name: name))
                    appState.persist()
                }
            }

            Section("Операции, категории, подкатегории") {
                ForEach(appState.data.optypes) { op in
                    opGroup(op)
                }
                AddRow(placeholder: "Новая операция (напр. Расход)") { name in
                    guard !exists(name, in: appState.data.optypes.map(\.name)) else { return }
                    appState.data.optypes.append(OperationType(name: name))
                    appState.persist()
                }
            }

            Section("Лица") {
                ForEach(sortedByName(appState.data.persons, { $0.name })) { p in
                    EditableRow(name: p.name, onRename: { renamePerson(p, to: $0) },
                                onDelete: { deletePersonTarget = p })
                }
                AddRow(placeholder: "Новое лицо") { name in
                    guard !exists(name, in: appState.data.persons.map(\.name)) else { return }
                    appState.data.persons.append(Person(name: name))
                    appState.persist()
                }
            }
        }
        .navigationTitle("Настройки")
        .alert("Удалить банк?", isPresented: Binding(get: { deleteBankTarget != nil }, set: { if !$0 { deleteBankTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let bank = deleteBankTarget {
                    appState.data.accounts.removeAll { $0.bankId == bank.id }
                    appState.data.banks.removeAll { $0.id == bank.id }
                    appState.persist()
                }
                deleteBankTarget = nil
            }
        } message: { Text("Банк будет удалён вместе со всеми его счетами. Уже сохранённые операции не изменятся.") }
        .alert("Удалить операцию?", isPresented: Binding(get: { deleteOpTarget != nil }, set: { if !$0 { deleteOpTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let op = deleteOpTarget {
                    let catIds = Set(appState.data.categories.filter { $0.opId == op.id }.map(\.id))
                    appState.data.subcategories.removeAll { catIds.contains($0.catId) }
                    appState.data.categories.removeAll { $0.opId == op.id }
                    appState.data.optypes.removeAll { $0.id == op.id }
                    appState.persist()
                }
                deleteOpTarget = nil
            }
        } message: { Text("Операция будет удалена вместе со всеми категориями и подкатегориями внутри неё. Уже сохранённые операции не изменятся.") }
        .alert("Удалить категорию?", isPresented: Binding(get: { deleteCatTarget != nil }, set: { if !$0 { deleteCatTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let cat = deleteCatTarget {
                    appState.data.subcategories.removeAll { $0.catId == cat.id }
                    appState.data.categories.removeAll { $0.id == cat.id }
                    appState.persist()
                }
                deleteCatTarget = nil
            }
        } message: { Text("Категория будет удалена вместе с подкатегориями. Уже сохранённые операции не изменятся.") }
        .alert("Удалить подкатегорию?", isPresented: Binding(get: { deleteSubTarget != nil }, set: { if !$0 { deleteSubTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let sub = deleteSubTarget {
                    appState.data.subcategories.removeAll { $0.id == sub.id }
                    appState.persist()
                }
                deleteSubTarget = nil
            }
        } message: { Text("Подкатегория будет удалена. Уже сохранённые операции не изменятся.") }
        .alert("Удалить счёт?", isPresented: Binding(get: { deleteAccTarget != nil }, set: { if !$0 { deleteAccTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let acc = deleteAccTarget {
                    appState.data.accounts.removeAll { $0.id == acc.id }
                    appState.persist()
                }
                deleteAccTarget = nil
            }
        } message: { Text("Счёт будет удалён. Уже сохранённые операции не изменятся.") }
        .alert("Удалить лицо?", isPresented: Binding(get: { deletePersonTarget != nil }, set: { if !$0 { deletePersonTarget = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let p = deletePersonTarget {
                    appState.data.persons.removeAll { $0.id == p.id }
                    appState.persist()
                }
                deletePersonTarget = nil
            }
        } message: { Text("Лицо будет удалено из справочника. Уже сохранённые операции не изменятся.") }
    }

    // MARK: - Группы

    @ViewBuilder
    private func bankGroup(_ bank: Bank) -> some View {
        let accs = appState.data.accounts.filter { $0.bankId == bank.id }
        DisclosureGroup {
            ForEach(accs) { acc in
                EditableRow(name: acc.name, onRename: { renameAccount(acc, in: bank, to: $0) },
                            onDelete: { deleteAccTarget = acc })
            }
            AddRow(placeholder: "Новый счёт") { name in
                guard !exists(name, in: accs.map(\.name)) else { return }
                appState.data.accounts.append(Account(name: name, bankId: bank.id))
                appState.persist()
            }
        } label: {
            EditableRow(name: bank.name, subtitle: "\(accs.count)",
                        onRename: { renameBank(bank, to: $0) },
                        onDelete: { deleteBankTarget = bank })
        }
    }

    @ViewBuilder
    private func opGroup(_ op: OperationType) -> some View {
        let cats = appState.data.categories.filter { $0.opId == op.id }
        DisclosureGroup {
            ForEach(cats) { cat in
                categoryGroup(cat, in: op)
            }
            AddRow(placeholder: "Новая категория") { name in
                guard !exists(name, in: cats.map(\.name)) else { return }
                appState.data.categories.append(Category(name: name, opId: op.id))
                appState.persist()
            }
        } label: {
            EditableRow(name: op.name, subtitle: "\(cats.count)",
                        onRename: { renameOp(op, to: $0) },
                        onDelete: { deleteOpTarget = op })
        }
    }

    @ViewBuilder
    private func categoryGroup(_ cat: Category, in op: OperationType) -> some View {
        let subs = appState.data.subcategories.filter { $0.catId == cat.id }
        DisclosureGroup {
            ForEach(subs) { sub in
                EditableRow(name: sub.name, onRename: { renameSub(sub, in: cat, op: op, to: $0) },
                            onDelete: { deleteSubTarget = sub })
            }
            AddRow(placeholder: "Новая подкатегория") { name in
                guard !exists(name, in: subs.map(\.name)) else { return }
                appState.data.subcategories.append(Subcategory(name: name, catId: cat.id))
                appState.persist()
            }
        } label: {
            EditableRow(name: cat.name, subtitle: "\(subs.count)",
                        onRename: { renameCategory(cat, in: op, to: $0) },
                        onDelete: { deleteCatTarget = cat })
        }
    }

    // MARK: - Переименование (со всеми сохранёнными операциями)

    private func renameBank(_ bank: Bank, to newName: String) {
        var d = appState.data
        guard let idx = d.banks.firstIndex(where: { $0.id == bank.id }) else { return }
        let old = d.banks[idx].name
        d.banks[idx].name = newName
        for i in d.operations.indices where d.operations[i].bank == old {
            d.operations[i].bank = newName
        }
        appState.data = d
        appState.persist()
    }

    private func renameAccount(_ acc: Account, in bank: Bank, to newName: String) {
        var d = appState.data
        guard let idx = d.accounts.firstIndex(where: { $0.id == acc.id }) else { return }
        let old = d.accounts[idx].name
        let bankName = d.banks.first(where: { $0.id == bank.id })?.name ?? bank.name
        d.accounts[idx].name = newName
        for i in d.operations.indices
        where d.operations[i].bank == bankName && d.operations[i].account == old {
            d.operations[i].account = newName
        }
        appState.data = d
        appState.persist()
    }

    private func renameOp(_ op: OperationType, to newName: String) {
        var d = appState.data
        guard let idx = d.optypes.firstIndex(where: { $0.id == op.id }) else { return }
        let old = d.optypes[idx].name
        d.optypes[idx].name = newName
        for i in d.operations.indices where d.operations[i].operation == old {
            d.operations[i].operation = newName
        }
        appState.data = d
        appState.persist()
    }

    private func renameCategory(_ cat: Category, in op: OperationType, to newName: String) {
        var d = appState.data
        guard let idx = d.categories.firstIndex(where: { $0.id == cat.id }) else { return }
        let old = d.categories[idx].name
        let opName = d.optypes.first(where: { $0.id == op.id })?.name ?? op.name
        d.categories[idx].name = newName
        for i in d.operations.indices
        where d.operations[i].operation == opName && d.operations[i].category == old {
            d.operations[i].category = newName
        }
        appState.data = d
        appState.persist()
    }

    private func renameSub(_ sub: Subcategory, in cat: Category, op: OperationType, to newName: String) {
        var d = appState.data
        guard let idx = d.subcategories.firstIndex(where: { $0.id == sub.id }) else { return }
        let old = d.subcategories[idx].name
        let opName = d.optypes.first(where: { $0.id == op.id })?.name ?? op.name
        let catName = d.categories.first(where: { $0.id == cat.id })?.name ?? cat.name
        d.subcategories[idx].name = newName
        for i in d.operations.indices
        where d.operations[i].operation == opName
            && d.operations[i].category == catName
            && d.operations[i].subcategory == old {
            d.operations[i].subcategory = newName
        }
        appState.data = d
        appState.persist()
    }

    private func renamePerson(_ p: Person, to newName: String) {
        var d = appState.data
        guard let idx = d.persons.firstIndex(where: { $0.id == p.id }) else { return }
        let old = d.persons[idx].name
        d.persons[idx].name = newName
        for i in d.operations.indices where d.operations[i].person == old {
            d.operations[i].person = newName
        }
        appState.data = d
        appState.persist()
    }
}
