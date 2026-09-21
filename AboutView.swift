import SwiftUI

struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @State private var showResetSheet = false
    @State private var resetConfirmText = ""
    @State private var showChangePassword = false

    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.1"
        return v
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppBadge(size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Учёт операций").font(.title3.bold())
                        Text("Версия \(appVersion) · работает без интернета").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Безопасность") {
                Button {
                    appState.lock()
                } label: {
                    Label("Заблокировать сейчас", systemImage: "lock.fill")
                }
                Button {
                    showChangePassword = true
                } label: {
                    Label("Сменить пароль", systemImage: "key.fill")
                }
            }

            Section("Автономность") {
                Text("Это полностью нативное приложение. В коде нет ни одного сетевого запроса — оно не использует интернет, серверы или облако ни в каком виде.")
            }
            Section("Хранение данных") {
                Text("Все данные хранятся во внутренней папке приложения на этом iPhone. Другие приложения не могут её прочитать, она не видна в «Файлах».")
                Text("Данные намеренно исключены из резервных копий iCloud и компьютера — они существуют только на этом телефоне. Ваша резервная копия — экспорт в Excel.")
            }
            Section("Шифрование") {
                Text("Перед записью на диск все данные шифруются AES-256-GCM. Ключ выводится из вашего пароля через PBKDF2 (250 000 итераций, SHA-256). Сам пароль нигде не хранится.")
                Text("Дополнительно iOS шифрует файлы своим ключом, пока телефон заблокирован (защита класса «Complete»).")
            }
            Section("Доступ и блокировка") {
                Text("Приложение блокируется через 5 минут бездействия — ключ удаляется из памяти. В переключателе приложений содержимое скрыто заставкой.")
            }
            Section("Экспорт") {
                Text("Единственный способ вывести данные — экспорт в Excel в разделе «История». Временный файл удаляется сразу после закрытия меню «Поделиться».")
            }

            Section("Полный сброс приложения") {
                Text("Удаляет абсолютно всё: все операции, справочники и пароль. Действие нельзя отменить.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Сбросить всё приложение", role: .destructive) {
                    resetConfirmText = ""
                    showResetSheet = true
                }
            }
        }
        .navigationTitle("О приложении")
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showResetSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Это уничтожит АБСОЛЮТНО всё: все операции, справочники и пароль. Восстановление невозможно.")
                    Text("Чтобы подтвердить, введите слово УДАЛИТЬ заглавными буквами.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Введите УДАЛИТЬ", text: $resetConfirmText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Удалить всё") {
                        appState.fullReset()
                        showResetSheet = false
                    }
                    .disabled(resetConfirmText.trimmingCharacters(in: .whitespaces) != "УДАЛИТЬ")
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    Spacer()
                }
                .padding()
                .navigationTitle("Подтверждение")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showResetSheet = false }
                    }
                }
            }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var oldPw = ""
    @State private var newPw1 = ""
    @State private var newPw2 = ""
    @State private var errorText = ""
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Текущий пароль", text: $oldPw)
                }
                Section {
                    SecureField("Новый пароль (мин. 4 символа)", text: $newPw1)
                    SecureField("Повторите новый пароль", text: $newPw2)
                } footer: {
                    Text("Все данные будут перешифрованы новым ключом. Забытый пароль восстановить невозможно.")
                }
                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }
                if done {
                    Section { Label("Пароль изменён", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            if appState.isBusy { ProgressView() }
                            Text(appState.isBusy ? "Перешифровка…" : "Сменить пароль")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(appState.isBusy || done || oldPw.isEmpty || newPw1.isEmpty)
                }
            }
            .navigationTitle("Смена пароля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done ? "Готово" : "Отмена") { dismiss() }
                }
            }
            .interactiveDismissDisabled(appState.isBusy)
        }
    }

    func submit() {
        errorText = ""
        guard newPw1 == newPw2 else { errorText = "Новые пароли не совпадают."; return }
        guard newPw1 != oldPw else { errorText = "Новый пароль совпадает с текущим."; return }
        let old = oldPw, new = newPw1
        Task {
            if let err = await appState.changePassword(old: old, new: new) {
                errorText = err
            } else {
                oldPw = ""; newPw1 = ""; newPw2 = ""
                done = true
            }
        }
    }
}
