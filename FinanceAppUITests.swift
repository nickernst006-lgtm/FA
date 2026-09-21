import XCTest

// UI-тесты: запускают приложение в симуляторе iPhone в облаке, «нажимают»
// кнопки как человек и сохраняют скриншоты каждого экрана.

final class FinanceAppUITests: XCTestCase {

    private let password = "test1234"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Создаёт пароль при первом запуске или входит, если пароль уже есть
    @MainActor
    private func unlock(_ app: XCUIApplication, screenshotPrefix: String? = nil) {
        let setup1 = app.secureTextFields["setupPassword1"]
        let login = app.secureTextFields["loginPassword"]
        let appeared = setup1.waitForExistence(timeout: 10) || login.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "не появился экран пароля")

        if setup1.exists {
            if let p = screenshotPrefix { snap(app, "\(p)_Создание_пароля") }
            setup1.tap()
            setup1.typeText(password)
            let setup2 = app.secureTextFields["setupPassword2"]
            setup2.tap()
            setup2.typeText(password)
            app.buttons["setupSubmit"].tap()
        } else {
            if let p = screenshotPrefix { snap(app, "\(p)_Вход") }
            login.tap()
            login.typeText(password)
            app.buttons["loginSubmit"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Форма"].waitForExistence(timeout: 60), "не открылся главный экран")
    }

    /// Тест 1: проходит по всем вкладкам и делает скриншоты
    @MainActor
    func test1_AllScreensScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo"]
        app.launch()
        unlock(app, screenshotPrefix: "01")

        snap(app, "02_Форма")

        app.tabBars.buttons["История"].tap()
        _ = app.staticTexts["15.09.2026"].waitForExistence(timeout: 5)
        snap(app, "03_История")

        app.tabBars.buttons["Статистика"].tap()
        sleep(1)
        snap(app, "04_Статистика")
        app.swipeUp()
        snap(app, "05_Статистика_ниже")

        app.tabBars.buttons["Настройки"].tap()
        sleep(1)
        snap(app, "06_Настройки")

        app.tabBars.buttons["О приложении"].tap()
        sleep(1)
        snap(app, "07_О_приложении")

        // Блокировка вручную и повторный вход
        app.buttons["Заблокировать сейчас"].tap()
        XCTAssertTrue(app.secureTextFields["loginPassword"].waitForExistence(timeout: 5), "не заблокировалось")
        snap(app, "08_Заблокировано")
        let login = app.secureTextFields["loginPassword"]
        login.tap()
        login.typeText("wrong-password")
        app.buttons["loginSubmit"].tap()
        XCTAssertTrue(app.staticTexts["Неверный пароль. Попробуйте снова."].waitForExistence(timeout: 30))
        snap(app, "09_Неверный_пароль")
        login.tap()
        login.typeText(password)
        app.buttons["loginSubmit"].tap()
        XCTAssertTrue(app.tabBars.buttons["Форма"].waitForExistence(timeout: 60))
    }

    /// Тест 2: заполняет форму как пользователь и проверяет, что операция сохранилась
    @MainActor
    func test2_AddOperationThroughForm() throws {
        let app = XCUIApplication()
        app.launch()
        unlock(app)

        app.tabBars.buttons["Форма"].tap()

        // Дата
        app.buttons["Выбрать"].firstMatch.tap()

        // Банк → Счёт (зависимый список)
        choose(app, picker: "Банк", option: "Тинькофф")
        choose(app, picker: "Счёт", option: "Основной")
        // Операция → Категория → Подкатегория
        choose(app, picker: "Операция", option: "Расход")
        choose(app, picker: "Категория", option: "Еда")
        choose(app, picker: "Подкатегория", option: "Продукты")

        // Лицо через поиск
        app.buttons["personButton"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Petr")   // латиницей не найдётся — проверим кнопку «Добавить»
        snap(app, "10_Поиск_лица")
        app.buttons["Отмена"].firstMatch.tap()

        // Сумма
        let amount = app.textFields["amountField"]
        amount.tap()
        amount.typeText("1500,50")
        snap(app, "11_Форма_заполнена")

        let done = app.buttons["Готово"].firstMatch
        if done.exists && done.isHittable { done.tap() }
        let save = app.buttons["saveButton"]
        if !save.isHittable { app.swipeUp() }
        save.tap()

        XCTAssertTrue(app.staticTexts["Операция сохранена"].waitForExistence(timeout: 5)
                      || app.otherElements["Операция сохранена"].exists,
                      "не появилось подтверждение сохранения")
        snap(app, "12_Сохранено")

        app.tabBars.buttons["История"].tap()
        let found = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '500,50'")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 5), "новая операция не появилась в истории")
        snap(app, "13_История_с_новой_операцией")
    }

    /// Выбор значения в выпадающем списке формы
    @MainActor
    private func choose(_ app: XCUIApplication, picker: String, option: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "нет списка \(picker)")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "в списке \(picker) нет «\(option)»")
        item.tap()
    }
}
