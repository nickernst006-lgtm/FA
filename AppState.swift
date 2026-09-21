import Foundation
import CryptoKit
import Combine

nonisolated enum EditState: Equatable {
    case edit(UUID)
    case duplicate(UUID)
}

@MainActor
final class AppState: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var hasAccount: Bool = false
    @Published var data: AppData = AppData()
    @Published var isBusy: Bool = false
    /// Текст ошибки сохранения — показывается пользователю, а не теряется молча
    @Published var saveError: String? = nil

    private var cryptoKey: SymmetricKey? = nil
    private var lastActivity: Date = Date()
    private var autoLockTimer: Timer?
    private let iterations: Int
    let autoLockSeconds: TimeInterval = 5 * 60

    private static let verifierText = "FINANCE_APP_OK_V1"

    /// Папка с данными. Application Support — внутренняя папка приложения,
    /// она не видна в приложении «Файлы» и через «Поделиться».
    let storageDir: URL
    private var metaURL: URL { storageDir.appendingPathComponent("meta.json") }
    private var dataURL: URL { storageDir.appendingPathComponent("financedata.enc") }

    private nonisolated struct MetaFile: Codable {
        var salt: Data
        var verifier: EncryptedBlob
    }
    private nonisolated struct VerifierPayload: Codable { var check: String }

    /// storageDir и iterations можно подменить только в тестах
    init(storageDir: URL? = nil, iterations: Int = 250_000) {
        self.iterations = iterations
        if let storageDir {
            self.storageDir = storageDir
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storageDir = base.appendingPathComponent("FinanceData", isDirectory: true)
        }
        prepareStorageDir()
        hasAccount = FileManager.default.fileExists(atPath: metaURL.path)
        Self.cleanTemporaryExports()
        startAutoLockMonitor()
    }

    // MARK: - Хранилище

    private func prepareStorageDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDir.path) {
            try? fm.createDirectory(at: storageDir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        excludeFromBackup(storageDir)
    }

    /// Данные НЕ попадают в резервные копии iCloud и компьютера:
    /// они физически существуют только на этом iPhone.
    private func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    /// Запись с шифрованием на уровне iOS (файл недоступен, пока телефон заблокирован)
    /// поверх нашего собственного AES-256.
    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        excludeFromBackup(url)
    }

    /// Удаляет временные Excel-файлы, оставшиеся после экспорта.
    static func cleanTemporaryExports() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension.lowercased() == "xlsx" {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: - Автоблокировка

    func registerActivity() {
        lastActivity = Date()
    }

    /// Проверка бездействия. Вызывается таймером и при возврате в приложение.
    func checkAutoLock() {
        if isUnlocked && Date().timeIntervalSince(lastActivity) > autoLockSeconds {
            lock()
        }
    }

    private func startAutoLockMonitor() {
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkAutoLock()
            }
        }
    }

    // MARK: - Ключ

    private func deriveKeyAsync(password: String, salt: Data) async -> SymmetricKey {
        let iterations = self.iterations
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let key = PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations)
                continuation.resume(returning: key)
            }
        }
    }

    private static func randomSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }

    private func writeMeta(salt: Data, key: SymmetricKey) throws {
        let verifier = try CryptoBox.encrypt(VerifierPayload(check: Self.verifierText), key: key)
        let metaData = try JSONEncoder().encode(MetaFile(salt: salt, verifier: verifier))
        try writeProtected(metaData, to: metaURL)
    }

    /// Проверяет пароль и возвращает ключ, либо nil если пароль неверный
    private func keyIfPasswordCorrect(_ password: String) async -> SymmetricKey? {
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(MetaFile.self, from: metaData) else { return nil }
        let key = await deriveKeyAsync(password: password, salt: meta.salt)
        guard let payload = try? CryptoBox.decrypt(meta.verifier, key: key, as: VerifierPayload.self),
              payload.check == Self.verifierText else { return nil }
        return key
    }

    // MARK: - Вход / создание / смена пароля

    /// Возвращает nil при успехе, иначе — текст ошибки для показа пользователю
    func createPassword(_ password: String) async -> String? {
        guard password.count >= 4 else { return "Пароль должен содержать минимум 4 символа." }
        isBusy = true
        defer { isBusy = false }

        let salt = Self.randomSalt()
        let key = await deriveKeyAsync(password: password, salt: salt)
        do {
            try writeMeta(salt: salt, key: key)
            cryptoKey = key
            data = AppData()
            #if DEBUG
            // Только для облачных скриншот-тестов (см. DemoData.swift)
            if ProcessInfo.processInfo.arguments.contains("-uiTestDemo") {
                data = DemoData.make()
            }
            #endif
            try saveData()
            hasAccount = true
            isUnlocked = true
            registerActivity()
            return nil
        } catch {
            cryptoKey = nil
            return "Не удалось создать пароль: \(error.localizedDescription)"
        }
    }

    func login(_ password: String) async -> String? {
        isBusy = true
        defer { isBusy = false }
        guard let key = await keyIfPasswordCorrect(password) else {
            return "Неверный пароль. Попробуйте снова."
        }
        do {
            cryptoKey = key
            try loadData()
            isUnlocked = true
            registerActivity()
            return nil
        } catch {
            cryptoKey = nil
            return "Пароль верный, но файл данных повреждён или не читается."
        }
    }

    /// Смена пароля: все данные перешифровываются новым ключом с новой «солью».
    func changePassword(old: String, new: String) async -> String? {
        guard new.count >= 4 else { return "Новый пароль должен содержать минимум 4 символа." }
        isBusy = true
        defer { isBusy = false }
        registerActivity()
        guard await keyIfPasswordCorrect(old) != nil else { return "Текущий пароль введён неверно." }

        let newSalt = Self.randomSalt()
        let newKey = await deriveKeyAsync(password: new, salt: newSalt)
        let oldKey = cryptoKey
        do {
            // Данные перешифровываются во временный файл и только потом
            // подменяют основной — старый файл не портится при ошибке записи.
            cryptoKey = newKey
            let tmpData = storageDir.appendingPathComponent("financedata.enc.new")
            let blob = try CryptoBox.encrypt(data, key: newKey)
            try writeProtected(try JSONEncoder().encode(blob), to: tmpData)
            try writeMeta(salt: newSalt, key: newKey)
            if FileManager.default.fileExists(atPath: dataURL.path) {
                _ = try FileManager.default.replaceItemAt(dataURL, withItemAt: tmpData)
            } else {
                try FileManager.default.moveItem(at: tmpData, to: dataURL)
            }
            excludeFromBackup(dataURL)
            registerActivity()
            return nil
        } catch {
            cryptoKey = oldKey
            return "Не удалось сменить пароль: \(error.localizedDescription)"
        }
    }

    func lock() {
        cryptoKey = nil
        data = AppData()
        isUnlocked = false
    }

    // MARK: - Данные

    private func loadData() throws {
        guard let key = cryptoKey else { throw CryptoError.notUnlocked }
        if FileManager.default.fileExists(atPath: dataURL.path) {
            let fileData = try Data(contentsOf: dataURL)
            let blob = try JSONDecoder().decode(EncryptedBlob.self, from: fileData)
            data = try CryptoBox.decrypt(blob, key: key, as: AppData.self)
        } else {
            data = AppData()
        }
    }

    func saveData() throws {
        guard let key = cryptoKey else { throw CryptoError.notUnlocked }
        let blob = try CryptoBox.encrypt(data, key: key)
        try writeProtected(try JSONEncoder().encode(blob), to: dataURL)
    }

    /// Сохранить после любого изменения. При ошибке — сообщение на экране.
    func persist() {
        registerActivity()
        do {
            try saveData()
        } catch {
            saveError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }

    func fullReset() {
        try? FileManager.default.removeItem(at: metaURL)
        try? FileManager.default.removeItem(at: dataURL)
        Self.cleanTemporaryExports()
        cryptoKey = nil
        data = AppData()
        isUnlocked = false
        hasAccount = false
    }
}
