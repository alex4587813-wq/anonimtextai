import AnonymizerCore
import Foundation

private let engine = AnonymizerEngine()
private var failures: [String] = []

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("[test] PASS: \(message)")
    } else {
        print("[test] FAIL: \(message)")
        failures.append(message)
    }
}

@MainActor
private func checkEqual(_ actual: String, _ expected: String, _ message: String) {
    if actual == expected {
        print("[test] PASS: \(message)")
    } else {
        print("[test] FAIL: \(message)")
        print("[test]   expected: \(expected.debugDescription)")
        print("[test]   actual:   \(actual.debugDescription)")
        failures.append(message)
    }
}

@MainActor
private func testSpecificationExample() {
    let source = """
    Александр Абрамян работает в компании Платформикс.
    Телефон: +7 999 123-45-67
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        [PERSON_001] работает в компании [COMPANY_001].
        Телефон: [PHONE_001]
        """,
        "пример из ТЗ"
    )
    check(result.counts[.person] == 1, "найдено одно ФИО")
    check(result.counts[.company] == 1, "найдена одна организация")
    check(result.counts[.phone] == 1, "найден один телефон")
}

@MainActor
private func testRepeatedValues() {
    let result = engine.anonymize(
        "Напишите на ivan@example.ru. Повторно: IVAN@example.ru"
    )

    checkEqual(
        result.text,
        "Напишите на [EMAIL_001]. Повторно: [EMAIL_001]",
        "одинаковый email получает одинаковый псевдоним"
    )
    check(result.counts[.email] == 2, "оба вхождения email учтены")
}

@MainActor
private func testBroadEmailFormats() {
    let source = """
    Внутренний адрес: user@server
    Кириллица: иванов@компания.рф
    В скобках: <A.Abramyan@platformix.ru>.
    Не адреса: @, @company.ru и user@.
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        Внутренний адрес: [EMAIL_001]
        Кириллица: [EMAIL_002]
        В скобках: <[EMAIL_003]>.
        Не адреса: @, @company.ru и user@.
        """,
        "любой полный фрагмент через @ заменяется целиком"
    )
    check(result.counts[.email] == 3, "найдены нестандартные и кириллические email")
}

@MainActor
private func testCompanyLegalForm() {
    let result = engine.anonymize("Заказчик — ООО «Ромашка»")
    check(result.text == "Заказчик — [COMPANY_001]", "организация с правовой формой")
}

@MainActor
private func testIPValidation() {
    let result = engine.anonymize("Серверы: 192.168.1.10 и 999.168.1.10")
    checkEqual(
        result.text,
        "Серверы: [IP_ADDRESS_001] и 999.168.1.10",
        "валидный IPv4 заменён, невалидный сохранён"
    )
}

@MainActor
private func testWhitespace() {
    let source = "Первый абзац.\n\nТелефон: +7 (999) 123-45-67\n"
    let result = engine.anonymize(source)
    checkEqual(
        result.text,
        "Первый абзац.\n\nТелефон: [PHONE_001]\n",
        "абзацы и переносы строк сохранены"
    )
}

@MainActor
private func testEmptyText() {
    let result = engine.anonymize("")
    check(result.text.isEmpty, "пустой текст остаётся пустым")
    check(result.totalMatches == 0, "в пустом тексте нет совпадений")
}

@MainActor
private func testExcludedWord() {
    let settings = AnonymizationSettings(
        enabledCategories: Set(AnonymizerEngine.Category.allCases),
        excludedTerms: ["Платформикс"],
        mandatoryCompanyTerms: []
    )
    let result = engine.anonymize(
        "Александр Абрамян работает в компании Платформикс.",
        settings: settings
    )

    checkEqual(
        result.text,
        "[PERSON_001] работает в компании Платформикс.",
        "слово из списка исключений не обезличивается"
    )
    check(result.counts[.company] == nil, "исключённая организация не учитывается")
}

@MainActor
private func testExcludedWordInsideFragment() {
    let settings = AnonymizationSettings(
        enabledCategories: Set(AnonymizerEngine.Category.allCases),
        excludedTerms: ["Ромашка"],
        mandatoryCompanyTerms: []
    )
    let result = engine.anonymize("Заказчик — ООО «Ромашка»", settings: settings)

    checkEqual(
        result.text,
        "Заказчик — ООО «Ромашка»",
        "исключение работает внутри составного фрагмента"
    )
}

@MainActor
private func testDisabledCategory() {
    var categories = Set(AnonymizerEngine.Category.allCases)
    categories.remove(.phone)
    let settings = AnonymizationSettings(
        enabledCategories: categories,
        excludedTerms: []
    )
    let result = engine.anonymize(
        "Телефон: +7 999 123-45-67, email: ivan@example.ru",
        settings: settings
    )

    checkEqual(
        result.text,
        "Телефон: +7 999 123-45-67, email: [EMAIL_001]",
        "отключённая категория не обезличивается"
    )
}

@MainActor
private func testDefaultMandatoryCompanies() {
    let result = engine.anonymize(
        "СИЛА, Платформикс и Базовые решения участвуют в проекте."
    )

    checkEqual(
        result.text,
        "[COMPANY_001], [COMPANY_002] и [COMPANY_003] участвуют в проекте.",
        "компании по умолчанию заменяются без контекста"
    )
}

@MainActor
private func testMandatoryReplacementHasHighestPriority() {
    let settings = AnonymizationSettings(
        enabledCategories: [],
        excludedTerms: ["Платформикс"],
        mandatoryCompanyTerms: ["Платформикс"]
    )
    let result = engine.anonymize("Платформикс", settings: settings)

    checkEqual(
        result.text,
        "[COMPANY_001]",
        "обязательная замена имеет приоритет над отключённой категорией и исключением"
    )
}

@MainActor
private func testMandatoryReplacementUsesWordBoundaries() {
    let settings = AnonymizationSettings(
        enabledCategories: [],
        excludedTerms: [],
        mandatoryCompanyTerms: ["СИЛА"]
    )
    let result = engine.anonymize("УСИЛАТЬ и СИЛА", settings: settings)

    checkEqual(
        result.text,
        "УСИЛАТЬ и [COMPANY_001]",
        "обязательный термин не заменяется внутри другого слова"
    )
}

@MainActor
private func testReplacementMaskMatchesWordEndings() {
    let settings = AnonymizationSettings(
        enabledCategories: [],
        excludedTerms: [],
        mandatoryCompanyTerms: ["Иванов*"]
    )
    let result = engine.anonymize(
        "Иванов, Иванову и Ивановым; Иван и Псевдоиванов.",
        settings: settings
    )

    checkEqual(
        result.text,
        "[COMPANY_001], [COMPANY_002] и [COMPANY_003]; Иван и Псевдоиванов.",
        "маска со звёздочкой учитывает окончания и границу слова"
    )
}

@MainActor
private func testInvalidReplacementMasksAreIgnored() {
    let settings = AnonymizationSettings(
        enabledCategories: [],
        excludedTerms: [],
        mandatoryCompanyTerms: ["*", "Ива*нов"]
    )
    let source = "Иванов и Иван"
    let result = engine.anonymize(source, settings: settings)

    checkEqual(
        result.text,
        source,
        "некорректные маски не заменяют текст"
    )
}

@MainActor
private func testFullNamesDoNotCrossLineBreaks() {
    let source = """
    Серова Татьяна
    Силаева Ирина
    Черноглазова Ольга

    Полыгаева Татьяна
    Солодовникова Ксения
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        [PERSON_001]
        [PERSON_002]
        [PERSON_003]

        [PERSON_004]
        [PERSON_005]
        """,
        "ФИО распознаются отдельно на каждой строке"
    )
    check(result.counts[.person] == 5, "найдены все пять ФИО")
}

@MainActor
private func testAbbreviatedRussianNames() {
    let source = """
    А.Ковешников
    А. Майборода
    Ковешников А.
    А.А. Майборода
    Майборода А.А.
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        [PERSON_001]
        [PERSON_002]
        [PERSON_003]
        [PERSON_004]
        [PERSON_005]
        """,
        "сокращённые ФИО с одним или двумя инициалами обезличиваются"
    )
}

@MainActor
private func testFullNameWithUncommonSurnameEnding() {
    let source = """
    Алексей Майборода
    Майборода Алексей
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        [PERSON_001]
        [PERSON_002]
        """,
        "полное ФИО распознаётся независимо от окончания фамилии"
    )
}

@MainActor
private func testReplacementTermsDoNotSplitStructuredData() {
    let settings = AnonymizationSettings(
        enabledCategories: Set(AnonymizerEngine.Category.allCases),
        excludedTerms: [],
        mandatoryCompanyTerms: [
            "platformix.ru",
            "+7 999 123-45-67",
            "192.168.1.10",
        ]
    )
    let source = """
    Dell-OPM-Request@platformix.ru
    +7 999 123-45-67
    192.168.1.10
    """
    let result = engine.anonymize(source, settings: settings)

    checkEqual(
        result.text,
        """
        [EMAIL_001]
        [PHONE_001]
        [IP_ADDRESS_001]
        """,
        "замена слов не разделяет email, телефон и IP"
    )
}

@MainActor
private func testOldSettingsReceiveDefaultMandatoryTerms() {
    let oldJSON = """
    {
      "enabledCategories": ["PERSON", "COMPANY"],
      "excludedTerms": ["Тест"]
    }
    """
    let decoded = try? JSONDecoder().decode(
        AnonymizationSettings.self,
        from: Data(oldJSON.utf8)
    )

    check(
        decoded?.mandatoryCompanyTerms == AnonymizationSettings.defaultMandatoryCompanyTerms,
        "старые настройки дополнены обязательными компаниями по умолчанию"
    )
    check(
        decoded?.enabledCategories.contains(.requisites) == true,
        "категория реквизитов включена при миграции старых настроек"
    )
}

@MainActor
private func testCompanyRequisites() {
    let source = """
    ИНН: 7707083893
    КПП: 773601001
    ОГРН: 1027700132195
    ОГРНИП: 304500116000157
    ОКПО: 12345678
    БИК: 044525225
    р/с: 40702810900000012345
    к/с: 30101810400000000225
    Юридический адрес: 123456, г. Москва, ул. Ленина, д. 10
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        ИНН: [REQUISITE_001]
        КПП: [REQUISITE_002]
        ОГРН: [REQUISITE_003]
        ОГРНИП: [REQUISITE_004]
        ОКПО: [REQUISITE_005]
        БИК: [REQUISITE_006]
        р/с: [REQUISITE_007]
        к/с: [REQUISITE_008]
        Юридический адрес: [REQUISITE_009]
        """,
        "корпоративные реквизиты и адрес обезличиваются"
    )
    check(result.counts[.requisites] == 9, "учтены все корпоративные реквизиты")
}

@MainActor
private func testPersonalRequisites() {
    let source = """
    СНИЛС: 123-456-789 01
    Паспорт: серия 4510 № 123456
    """
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        """
        СНИЛС: [REQUISITE_001]
        Паспорт: серия [REQUISITE_002]
        """,
        "СНИЛС и паспортные данные обезличиваются"
    )
}

@MainActor
private func testRequisitesCanBeDisabled() {
    var categories = Set(AnonymizerEngine.Category.allCases)
    categories.remove(.requisites)
    let settings = AnonymizationSettings(
        enabledCategories: categories,
        excludedTerms: [],
        mandatoryCompanyTerms: []
    )
    let source = "ИНН: 7707083893\nАдрес: 123456, г. Москва, ул. Ленина, д. 10"
    let result = engine.anonymize(source, settings: settings)

    checkEqual(
        result.text,
        source,
        "отключённая категория реквизитов не изменяет текст"
    )
}

@MainActor
private func testUnlabeledNumberIsNotARequisite() {
    let source = "Номер заявки: 7707083893"
    let result = engine.anonymize(source)

    checkEqual(
        result.text,
        source,
        "неподписанное число не считается реквизитом"
    )
}

testSpecificationExample()
testRepeatedValues()
testBroadEmailFormats()
testCompanyLegalForm()
testIPValidation()
testWhitespace()
testEmptyText()
testExcludedWord()
testExcludedWordInsideFragment()
testDisabledCategory()
testDefaultMandatoryCompanies()
testMandatoryReplacementHasHighestPriority()
testMandatoryReplacementUsesWordBoundaries()
testReplacementMaskMatchesWordEndings()
testInvalidReplacementMasksAreIgnored()
testFullNamesDoNotCrossLineBreaks()
testAbbreviatedRussianNames()
testFullNameWithUncommonSurnameEnding()
testReplacementTermsDoNotSplitStructuredData()
testOldSettingsReceiveDefaultMandatoryTerms()
testCompanyRequisites()
testPersonalRequisites()
testRequisitesCanBeDisabled()
testUnlabeledNumberIsNotARequisite()

if failures.isEmpty {
    print("[test] Все проверки пройдены")
    exit(EXIT_SUCCESS)
} else {
    print("[test] Ошибок: \(failures.count)")
    exit(EXIT_FAILURE)
}
