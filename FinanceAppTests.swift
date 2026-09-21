import XCTest
import CryptoKit
@testable import FinanceApp

// Юнит-тесты логики приложения. Запускаются в облаке (GitHub Actions)
// на настоящем Mac с Xcode — без iPhone и без установки.

final class CryptoTests: XCTestCase {

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Официальный тестовый вектор RFC 7914 (раздел 11) для PBKDF2-HMAC-SHA256
    func testPBKDF2_RFC7914Vector() {
        let out = PBKDF2.deriveBytes(password: "passwd", salt: Data("salt".utf8), iterations: 1, keyLength: 64)
        XCTAssertEqual(hex(out), "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
    }

    /// Широко известный вектор: "password" / "salt" / 4096 итераций
    func testPBKDF2_4096Iterations() {
        let out = PBKDF2.deriveBytes(password: "password", salt: Data("salt".utf8), iterations: 4096, keyLength: 32)
        XCTAssertEqual(hex(out), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    /// Кириллический пароль — сверено с Python hashlib.pbkdf2_hmac
    func testPBKDF2_Cyrillic() {
        let out = PBKDF2.deriveBytes(password: "Пароль_кириллица", salt: Data("salt_kir".utf8), iterations: 5000, keyLength: 32)
        XCTAssertEqual(hex(out), "f0e1588eadc8344e4d660a6f1cbebbfb889f09a918006a93618171c54657cf55")
    }

    /// Сколько реально длится вывод ключа с боевыми параметрами (для информации)
    func testPBKDF2_ProductionSpeed() {
        let start = Date()
        _ = PBKDF2.deriveKey(password: "test1234", salt: Data(repeating: 7, count: 16), iterations: 250_000)
        let seconds = Date().timeIntervalSince(start)
        print("PBKDF2 250 000 итераций: \(String(format: "%.2f", seconds)) с")
        XCTAssertLessThan(seconds, 30)
    }

    func testEncryptDecryptRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        var data = AppData()
        data.banks = [Bank(name: "Тинькофф")]
        data.operations = [OperationRecord(date: "2026-09-15", time: "14:30", bank: "Тинькофф", account: "Основной",
                                           operation: "Расход", category: "Еда", subcategory: "Кафе",
                                           person: "Иванов", amount: 1234.56, comment: "тест \"&<>'", createdAt: 1)]
        let blob = try CryptoBox.encrypt(data, key: key)
        let back = try CryptoBox.decrypt(blob, key: key, as: AppData.self)
        XCTAssertEqual(back, data)

        // Зашифрованный блоб не содержит открытого текста
        XCTAssertNil(String(data: blob.combined, encoding: .utf8)?.range(of: "Тинькофф"))
    }

    func testDecryptWithWrongKeyFails() throws {
        let blob = try CryptoBox.encrypt(AppData(), key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try CryptoBox.decrypt(blob, key: SymmetricKey(size: .bits256), as: AppData.self))
    }

    func testTamperedDataFails() throws {
        let key = SymmetricKey(size: .bits256)
        var blob = try CryptoBox.encrypt(AppData(), key: key)
        var bytes = [UInt8](blob.combined)
        bytes[bytes.count - 1] ^= 0xFF
        blob.combined = Data(bytes)
        XCTAssertThrowsError(try CryptoBox.decrypt(blob, key: key, as: AppData.self))
    }
}

final class FormattingTests: XCTestCase {

    func testMoneyParse() {
        XCTAssertEqual(Money.parse("1234,56"), 1234.56)
        XCTAssertEqual(Money.parse("1234.56"), 1234.56)
        XCTAssertEqual(Money.parse("1 234,5"), 1234.5)
        XCTAssertEqual(Money.parse("1\u{00A0}000"), 1000)
        XCTAssertEqual(Money.parse(" 50000 "), 50000)
        XCTAssertEqual(Money.parse("0,01"), 0.01)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse("1,2,3"))
        XCTAssertNil(Money.parse("-5"))
        XCTAssertNil(Money.parse("1e5"))
    }

    func testMoneyEditString() {
        XCTAssertEqual(Money.editString(50000), "50000")
        XCTAssertEqual(Money.editString(1234.56), "1234,56")
        XCTAssertEqual(Money.parse(Money.editString(1234.5)), 1234.5)
    }

    func testMoneyFormat() {
        let s = Money.format(1234.5)
        XCTAssertTrue(s.hasSuffix(",50"), s)
        XCTAssertTrue(s.hasPrefix("1"), s)
    }

    func testDateRoundTrip() {
        let d = DateFmt.day(from: "2026-09-15")
        XCTAssertNotNil(d)
        XCTAssertEqual(DateFmt.dayString(d!), "2026-09-15")
        let t = DateFmt.time(from: "07:05")
        XCTAssertNotNil(t)
        XCTAssertEqual(DateFmt.timeString(t!), "07:05")
        XCTAssertNil(DateFmt.day(from: ""))
        XCTAssertEqual(DateFmt.display("2026-09-15"), "15.09.2026")
        XCTAssertEqual(DateFmt.monthTitle("2026-09"), "Сентябрь 2026")
    }

    func testIncomeExpenseDetection() {
        var r = OperationRecord(date: "2026-01-01", time: "", bank: "", account: "", operation: "Доход",
                                category: "", subcategory: "", person: "", amount: 1, comment: "", createdAt: 0)
        XCTAssertTrue(r.isIncome); XCTAssertFalse(r.isExpense)
        r.operation = "расход"
        XCTAssertTrue(r.isExpense); XCTAssertFalse(r.isIncome)
    }
}

final class XLSXTests: XCTestCase {

    private func u32(_ d: [UInt8], _ i: Int) -> UInt32 {
        UInt32(d[i]) | UInt32(d[i+1]) << 8 | UInt32(d[i+2]) << 16 | UInt32(d[i+3]) << 24
    }
    private func u16(_ d: [UInt8], _ i: Int) -> Int {
        Int(d[i]) | Int(d[i+1]) << 8
    }

    func testXLSXStructure() throws {
        let ops = [
            OperationRecord(date: "2026-09-15", time: "14:30", bank: "Тинькофф", account: "Тест \"кавычки\" & <теги>",
                            operation: "Расход", category: "Еда", subcategory: "апостроф'тест",
                            person: "Иванов", amount: 1234.56, comment: "", createdAt: 1),
            OperationRecord(date: "2026-09-14", time: "", bank: "Сбер", account: "Зарплатный",
                            operation: "Доход", category: "Зарплата", subcategory: "",
                            person: "", amount: 50000, comment: "", createdAt: 2),
        ]
        let bytes = [UInt8](XLSXExporter.buildXLSX(operations: ops))

        // Начало: сигнатура локального заголовка ZIP "PK\3\4"
        XCTAssertEqual(u32(bytes, 0), 0x04034b50)

        // Конец: запись End Of Central Directory (22 байта)
        let eocd = bytes.count - 22
        XCTAssertEqual(u32(bytes, eocd), 0x06054b50)
        XCTAssertEqual(u16(bytes, eocd + 10), 6, "должно быть 6 файлов внутри xlsx")
        let cdSize = Int(u32(bytes, eocd + 12))
        let cdOffset = Int(u32(bytes, eocd + 16))
        XCTAssertEqual(cdOffset + cdSize, eocd, "центральный каталог должен заканчиваться прямо перед EOCD")

        // Проходим центральный каталог и проверяем, что каждый файл найден по смещению
        var p = cdOffset
        var names: [String] = []
        var sheetXML = ""
        for _ in 0..<6 {
            XCTAssertEqual(u32(bytes, p), 0x02014b50)
            let size = Int(u32(bytes, p + 20))
            let nameLen = u16(bytes, p + 28)
            let localOffset = Int(u32(bytes, p + 42))
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            names.append(name)
            XCTAssertEqual(u32(bytes, localOffset), 0x04034b50, "локальный заголовок \(name)")
            let localNameLen = u16(bytes, localOffset + 26)
            let dataStart = localOffset + 30 + localNameLen
            let content = String(decoding: bytes[dataStart..<(dataStart + size)], as: UTF8.self)
            XCTAssertTrue(content.hasPrefix("<?xml"), "\(name) должен начинаться с <?xml")
            if name == "xl/worksheets/sheet1.xml" { sheetXML = content }
            p += 46 + nameLen
        }
        XCTAssertEqual(Set(names), ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                    "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"])

        // Содержимое листа: экранирование и формат суммы
        XCTAssertTrue(sheetXML.contains("Тест &quot;кавычки&quot; &amp; &lt;теги&gt;"))
        XCTAssertTrue(sheetXML.contains("апостроф&apos;тест"))
        XCTAssertTrue(sheetXML.contains("<v>1234.56</v>"))
        XCTAssertTrue(sheetXML.contains("<v>50000.00</v>"))
        XCTAssertTrue(sheetXML.contains("<dimension ref=\"A1:J3\"/>"))
    }
}

@MainActor
final class AppStateTests: XCTestCase {

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FinanceTest-\(UUID().uuidString)")
    }

    private func sampleOp(_ amount: Double) -> OperationRecord {
        OperationRecord(date: "2026-09-15", time: "10:00", bank: "Банк", account: "Счёт", operation: "Расход",
                        category: "Еда", subcategory: "", person: "", amount: amount, comment: "", createdAt: 1)
    }

    func testFullLifecycle() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 1. Первый запуск — пароля нет
        let s1 = AppState(storageDir: dir, iterations: 1000)
        XCTAssertFalse(s1.hasAccount)

        // 2. Слишком короткий пароль отклоняется
        let short = await s1.createPassword("123")
        XCTAssertNotNil(short)

        // 3. Создание пароля и сохранение операции
        let created = await s1.createPassword("secret1")
        XCTAssertNil(created)
        XCTAssertTrue(s1.isUnlocked)
        s1.data.operations.append(sampleOp(100))
        s1.persist()
        XCTAssertNil(s1.saveError)

        // 4. Файлы исключены из резервных копий
        let dataFile = dir.appendingPathComponent("financedata.enc")
        let values = try dataFile.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        // 5. Блокировка стирает данные из памяти
        s1.lock()
        XCTAssertFalse(s1.isUnlocked)
        XCTAssertTrue(s1.data.operations.isEmpty)

        // 6. «Перезапуск» приложения: неверный пароль не пускает
        let s2 = AppState(storageDir: dir, iterations: 1000)
        XCTAssertTrue(s2.hasAccount)
        let wrong = await s2.login("wrong")
        XCTAssertNotNil(wrong)
        XCTAssertFalse(s2.isUnlocked)

        // 7. Верный пароль восстанавливает данные
        let ok = await s2.login("secret1")
        XCTAssertNil(ok)
        XCTAssertEqual(s2.data.operations.count, 1)
        XCTAssertEqual(s2.data.operations.first?.amount, 100)

        // 8. Смена пароля: старый больше не подходит, данные целы
        let badOld = await s2.changePassword(old: "nope", new: "newpass")
        XCTAssertNotNil(badOld)
        let changed = await s2.changePassword(old: "secret1", new: "newpass")
        XCTAssertNil(changed)
        s2.data.operations.append(sampleOp(200))
        s2.persist()

        let s3 = AppState(storageDir: dir, iterations: 1000)
        let oldFails = await s3.login("secret1")
        XCTAssertNotNil(oldFails)
        let newWorks = await s3.login("newpass")
        XCTAssertNil(newWorks)
        XCTAssertEqual(s3.data.operations.map(\.amount), [100, 200])

        // 9. Полный сброс удаляет всё
        s3.fullReset()
        XCTAssertFalse(s3.hasAccount)
        let s4 = AppState(storageDir: dir, iterations: 1000)
        XCTAssertFalse(s4.hasAccount)
    }

    func testAutoLockAfterInactivity() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = AppState(storageDir: dir, iterations: 1000)
        _ = await s.createPassword("secret1")
        XCTAssertTrue(s.isUnlocked)
        s.checkAutoLock()
        XCTAssertTrue(s.isUnlocked, "сразу после активности блокироваться не должно")
    }
}
