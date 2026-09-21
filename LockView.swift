import SwiftUI

struct LockView: View {
    @EnvironmentObject var appState: AppState
    @State private var pw1 = ""
    @State private var pw2 = ""
    @State private var loginPw = ""
    @State private var errorText = ""

    private enum Field { case pw1, pw2, login }
    @FocusState private var focus: Field?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    AppBadge(size: 56)
                    if appState.hasAccount {
                        loginForm
                    } else {
                        setupForm
                    }
                }
                .padding(24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(24)
                .frame(maxWidth: 480)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            focus = appState.hasAccount ? .login : .pw1
        }
    }

    var setupForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Создайте пароль").font(.title3.bold())
            Text("Этот пароль защищает все данные шифрованием AES-256. Он нигде не хранится.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Восстановить забытый пароль невозможно. Данные будут потеряны безвозвратно.")
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            SecureField("Придумайте пароль (мин. 4 символа)", text: $pw1)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .pw1)
                .submitLabel(.next)
                .onSubmit { focus = .pw2 }
                .accessibilityIdentifier("setupPassword1")
            SecureField("Повторите пароль", text: $pw2)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .pw2)
                .submitLabel(.go)
                .onSubmit(submitSetup)
                .accessibilityIdentifier("setupPassword2")

            if !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            Button(action: submitSetup) {
                HStack {
                    if appState.isBusy { ProgressView().tint(.white) }
                    Text(appState.isBusy ? "Шифрование…" : "Создать и войти")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.isBusy)
            .accessibilityIdentifier("setupSubmit")
        }
    }

    var loginForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Введите пароль").font(.title3.bold())
            Text("Данные зашифрованы. Введите пароль для доступа.")
                .font(.footnote).foregroundStyle(.secondary)

            SecureField("Пароль", text: $loginPw)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .login)
                .submitLabel(.go)
                .onSubmit(submitLogin)
                .accessibilityIdentifier("loginPassword")

            if !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            Button(action: submitLogin) {
                HStack {
                    if appState.isBusy { ProgressView().tint(.white) }
                    Text(appState.isBusy ? "Проверка…" : "Войти")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.isBusy || loginPw.isEmpty)
            .accessibilityIdentifier("loginSubmit")
        }
    }

    func submitSetup() {
        guard !appState.isBusy else { return }
        errorText = ""
        if pw1.count < 4 { errorText = "Пароль должен содержать минимум 4 символа."; return }
        if pw1 != pw2 { errorText = "Пароли не совпадают."; return }
        let password = pw1
        Task {
            if let err = await appState.createPassword(password) {
                errorText = err
            } else {
                pw1 = ""; pw2 = ""
            }
        }
    }

    func submitLogin() {
        guard !appState.isBusy, !loginPw.isEmpty else { return }
        errorText = ""
        let password = loginPw
        Task {
            if let err = await appState.login(password) {
                errorText = err
                loginPw = ""
            } else {
                loginPw = ""
            }
        }
    }
}
