import Foundation
import NaturalLanguage

public struct AnonymizerEngine: Sendable {
    public enum Category: String, CaseIterable, Codable, Hashable, Sendable {
        case person = "PERSON"
        case company = "COMPANY"
        case phone = "PHONE"
        case email = "EMAIL"
        case ipAddress = "IP_ADDRESS"
        case requisites = "REQUISITE"

        public var displayName: String {
            switch self {
            case .person:
                return "ФИО"
            case .company:
                return "Организации"
            case .phone:
                return "Телефоны"
            case .email:
                return "Email"
            case .ipAddress:
                return "IP"
            case .requisites:
                return "Реквизиты"
            }
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let counts: [Category: Int]
        public let totalMatches: Int
    }

    private struct Match: Sendable {
        let range: NSRange
        let category: Category
        let priority: Int
        let value: String
    }

    public init() {}

    public func anonymize(
        _ text: String,
        settings: AnonymizationSettings = .standard
    ) -> Result {
        guard !text.isEmpty else {
            return Result(text: "", counts: [:], totalMatches: 0)
        }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var matches: [Match] = []

        matches += regexMatches(
            in: text,
            pattern: #"(?i)(?<![\p{L}\p{N}._%+\-])[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-ZА-ЯЁ]{2,}(?![\p{L}\p{N}_\-])"#,
            category: .email,
            priority: 200
        )

        matches += regexMatches(
            in: text,
            pattern: #"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"#,
            category: .ipAddress,
            priority: 195
        ).filter { match in
            match.value.split(separator: ".").allSatisfy { part in
                guard let number = Int(part) else { return false }
                return (0...255).contains(number)
            }
        }

        matches += regexMatches(
            in: text,
            pattern: #"(?<![\p{L}\d])(?:\+7|8)[ \t\-()]*(?:\d[ \t\-()]*){10}(?!\d)"#,
            category: .phone,
            priority: 190
        )

        matches += requisiteMatches(in: text)

        matches += regexMatches(
            in: text,
            pattern: #"(?iu)\b(?:ООО|ПАО|АО|ОАО|ЗАО|ИП|АНО|НКО|ФГУП|ГУП|МУП|ГК)[ \t]+(?:[«"“][^»"”\n]{2,80}[»"”]|[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*(?:[ \t]+[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*){0,3})"#,
            category: .company,
            priority: 70
        )

        matches += regexMatches(
            in: text,
            pattern: #"(?iu)\b(?:компания|компании|организация|организации)[ \t]+([«"“][^»"”\n]{2,80}[»"”]|[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*(?:[ \t]+[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*){0,2})"#,
            category: .company,
            priority: 65,
            captureGroup: 1
        )

        matches += naturalLanguageMatches(in: text)
        matches += personHeuristicMatches(in: text)

        let normalizedExclusions = settings.excludedTerms
            .map(canonicalizeForExclusion)
            .filter { !$0.isEmpty }

        matches = matches.filter { match in
            settings.enabledCategories.contains(match.category)
                && !isExcluded(match.value, normalizedExclusions: normalizedExclusions)
        }

        matches += replacementTermMatches(
            in: text,
            terms: settings.mandatoryCompanyTerms
        )

        let accepted = resolveOverlaps(matches, within: fullRange)
        var placeholders: [Category: [String: String]] = [:]
        var counters: [Category: Int] = [:]
        var replacements: [(range: NSRange, placeholder: String, category: Category)] = []

        for match in accepted.sorted(by: { $0.range.location < $1.range.location }) {
            let canonicalValue = canonicalize(match.value)
            let placeholder: String

            if let existing = placeholders[match.category]?[canonicalValue] {
                placeholder = existing
            } else {
                let number = (counters[match.category] ?? 0) + 1
                counters[match.category] = number
                placeholder = String(format: "[%@_%03d]", match.category.rawValue, number)
                placeholders[match.category, default: [:]][canonicalValue] = placeholder
            }

            replacements.append((match.range, placeholder, match.category))
        }

        let mutableText = NSMutableString(string: text)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutableText.replaceCharacters(in: replacement.range, with: replacement.placeholder)
        }

        var counts: [Category: Int] = [:]
        for replacement in replacements {
            counts[replacement.category, default: 0] += 1
        }

        return Result(
            text: mutableText as String,
            counts: counts,
            totalMatches: replacements.count
        )
    }

    private func regexMatches(
        in text: String,
        pattern: String,
        category: Category,
        priority: Int,
        captureGroup: Int = 0
    ) -> [Match] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        return expression.matches(in: text, range: fullRange).compactMap { result in
            guard captureGroup < result.numberOfRanges else { return nil }
            let range = result.range(at: captureGroup)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return Match(
                range: range,
                category: category,
                priority: priority,
                value: source.substring(with: range)
            )
        }
    }

    private func naturalLanguageMatches(in text: String) -> [Match] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let fullRange = text.startIndex..<text.endIndex
        var matches: [Match] = []

        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let category: Category
            let priority: Int

            switch tag {
            case .personalName:
                category = .person
                priority = 55
            case .organizationName:
                category = .company
                priority = 60
            default:
                return true
            }

            let nsRange = NSRange(range, in: text)
            guard nsRange.length > 1 else { return true }
            matches.append(
                Match(
                    range: nsRange,
                    category: category,
                    priority: priority,
                    value: String(text[range])
                )
            )
            return true
        }

        return matches
    }

    private func requisiteMatches(in text: String) -> [Match] {
        var matches: [Match] = []

        let labeledPatterns = [
            #"(?iu)\bИНН[ \t]*[:№\-]?[ \t]*(\d{12}|\d{10})(?!\d)"#,
            #"(?iu)\bКПП[ \t]*[:№\-]?[ \t]*(\d{9})(?!\d)"#,
            #"(?iu)\bОГРНИП[ \t]*[:№\-]?[ \t]*(\d{15})(?!\d)"#,
            #"(?iu)\bОГРН[ \t]*[:№\-]?[ \t]*(\d{13})(?!\d)"#,
            #"(?iu)\bОКПО[ \t]*[:№\-]?[ \t]*(\d{10}|\d{8})(?!\d)"#,
            #"(?iu)\bБИК[ \t]*[:№\-]?[ \t]*(\d{9})(?!\d)"#,
            #"(?iu)\b(?:р[\\/]?с|расч[её]тный[ \t]+сч[её]т|к[\\/]?с|корреспондентский[ \t]+сч[её]т)[ \t]*[:№\-]?[ \t]*(\d{20})(?!\d)"#,
            #"(?iu)\bСНИЛС[ \t]*[:№\-]?[ \t]*(\d{3}[\- ]?\d{3}[\- ]?\d{3}[ \-]?\d{2})(?!\d)"#,
            #"(?iu)\b(?:паспорт(?:ные[ \t]+данные)?|серия[ \t]+и[ \t]+номер[ \t]+паспорта)[ \t]*[:\-]?[ \t]*(?:серия[ \t]*)?(\d{4}[ \t\-]*(?:№|номер)?[ \t]*\d{6})(?!\d)"#,
        ]

        for pattern in labeledPatterns {
            matches += regexMatches(
                in: text,
                pattern: pattern,
                category: .requisites,
                priority: 180,
                captureGroup: 1
            )
        }

        let addressPatterns = [
            #"(?iu)\b(?:юридический|фактический|почтовый)[ \t]+адрес[ \t]*[:\-—]?[ \t]+([^\r\n;]{8,240})"#,
            #"(?iu)\b(?:адрес(?:[ \t]+регистрации)?|место[ \t]+нахождения)[ \t]*[:\-—][ \t]*([^\r\n;]{8,240})"#,
        ]

        for pattern in addressPatterns {
            matches += regexMatches(
                in: text,
                pattern: pattern,
                category: .requisites,
                priority: 185,
                captureGroup: 1
            )
        }

        return matches
    }

    private func replacementTermMatches(
        in text: String,
        terms: [String]
    ) -> [Match] {
        terms.flatMap { term -> [Match] in
            let rawTokens = term
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)

            guard !rawTokens.isEmpty else { return [] }

            var tokenPatterns: [String] = []
            for token in rawTokens {
                guard let pattern = replacementTokenPattern(String(token)) else {
                    return []
                }
                tokenPatterns.append(pattern)
            }

            let phrasePattern = tokenPatterns.joined(separator: #"[ \t]+"#)
            let pattern = #"(?iu)(?<![\p{L}\p{N}])"# + phrasePattern + #"(?![\p{L}\p{N}])"#

            return regexMatches(
                in: text,
                pattern: pattern,
                category: .company,
                priority: 120
            )
        }
    }

    private func replacementTokenPattern(_ token: String) -> String? {
        guard !token.isEmpty else { return nil }

        if token.hasSuffix("*") {
            let prefix = String(token.dropLast())
            guard !prefix.isEmpty, !prefix.contains("*") else { return nil }
            return NSRegularExpression.escapedPattern(for: prefix)
                + #"[\p{L}\p{M}\p{N}_-]*"#
        }

        guard !token.contains("*") else { return nil }
        return NSRegularExpression.escapedPattern(for: token)
    }

    private func personHeuristicMatches(in text: String) -> [Match] {
        var matches = regexMatches(
            in: text,
            pattern: #"(?u)(?<![\p{L}\p{N}])(?:[А-ЯЁ]\.[ \t]*){1,2}[А-ЯЁ][а-яё\-]{2,30}(?![\p{L}\p{N}])"#,
            category: .person,
            priority: 80
        )

        matches += regexMatches(
            in: text,
            pattern: #"(?u)(?<![\p{L}\p{N}])[А-ЯЁ][а-яё\-]{2,30}[ \t]+[А-ЯЁ]\.(?:[ \t]*[А-ЯЁ]\.)?(?![\p{L}\p{N}])"#,
            category: .person,
            priority: 80
        )

        let fullNameCandidates = regexMatches(
            in: text,
            pattern: #"(?u)(?<![\p{L}\p{N}])[А-ЯЁ][а-яё\-]{1,30}(?:[ \t]+[А-ЯЁ][а-яё\-]{1,30}){1,2}(?![\p{L}\p{N}])"#,
            category: .person,
            priority: 62
        )

        matches += fullNameCandidates.filter { looksLikeRussianPersonName($0.value) }
        return matches
    }

    private func looksLikeRussianPersonName(_ value: String) -> Bool {
        let words = value
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }

        guard (2...3).contains(words.count) else { return false }

        let firstNameCount = words.filter { Self.commonFirstNames.contains($0) }.count
        let hasFirstName = firstNameCount > 0
        let hasSurname = words.contains { word in
            Self.surnameEndings.contains { word.hasSuffix($0) }
        }
        let hasPatronymic = words.contains { word in
            Self.patronymicEndings.contains { word.hasSuffix($0) }
        }

        if words.count == 2 && firstNameCount == 1 {
            return true
        }

        return (hasFirstName && hasSurname)
            || (words.count == 3 && hasFirstName && hasPatronymic)
    }

    private func resolveOverlaps(_ matches: [Match], within fullRange: NSRange) -> [Match] {
        let uniqueMatches = Dictionary(
            grouping: matches.filter { NSIntersectionRange($0.range, fullRange).length == $0.range.length },
            by: { "\($0.range.location):\($0.range.length):\($0.category.rawValue)" }
        ).compactMap { $0.value.max(by: { $0.priority < $1.priority }) }

        let ranked = uniqueMatches.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            if $0.range.length != $1.range.length {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }

        var accepted: [Match] = []
        for candidate in ranked {
            let overlaps = accepted.contains {
                NSIntersectionRange($0.range, candidate.range).length > 0
            }
            if !overlaps {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    private func canonicalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func canonicalizeForExclusion(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ru_RU")
        )
        let separated = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(separated)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func isExcluded(
        _ value: String,
        normalizedExclusions: [String]
    ) -> Bool {
        let normalizedValue = canonicalizeForExclusion(value)
        let paddedValue = " \(normalizedValue) "

        return normalizedExclusions.contains { exclusion in
            normalizedValue == exclusion || paddedValue.contains(" \(exclusion) ")
        }
    }

    private static let patronymicEndings = [
        "ович", "евич", "ич", "овна", "евна", "ична", "инична"
    ]

    private static let surnameEndings = [
        "ов", "ев", "ёв", "ин", "ын", "ова", "ева", "ёва", "ина", "ына",
        "ский", "цкий", "ской", "цкой", "ская", "цкая", "ян", "янц",
        "енко", "ко", "ук", "юк", "ич", "ец", "дзе", "швили"
    ]

    private static let commonFirstNames: Set<String> = [
        "александр", "алексей", "алёна", "анастасия", "анатолий", "андрей",
        "анна", "антон", "аркадий", "артём", "борис", "вадим", "валентин",
        "валентина", "валерий", "василий", "вера", "виктор", "виктория",
        "виталий", "владимир", "владислав", "вячеслав", "галина", "геннадий",
        "георгий", "григорий", "дарья", "денис", "дмитрий", "евгений",
        "евгения", "екатерина", "елена", "елизавета", "иван", "игорь",
        "илья", "инна", "ирина", "кирилл", "константин", "ксения", "лариса",
        "лев", "лидия", "любовь", "людмила", "максим", "маргарита", "марина",
        "мария", "михаил", "надежда", "наталья", "никита", "николай", "нина",
        "олег", "ольга", "павел", "пётр", "полина", "роман", "светлана",
        "семён", "сергей", "софия", "станислав", "степан", "тамара", "татьяна",
        "тимофей", "фёдор", "юлия", "юрий", "яна", "ярослав"
    ]
}

public struct AnonymizationSettings: Codable, Equatable, Sendable {
    public var enabledCategories: Set<AnonymizerEngine.Category>
    public var excludedTerms: [String]
    public var mandatoryCompanyTerms: [String]

    public init(
        enabledCategories: Set<AnonymizerEngine.Category>,
        excludedTerms: [String],
        mandatoryCompanyTerms: [String] = Self.defaultMandatoryCompanyTerms
    ) {
        self.enabledCategories = enabledCategories
        self.excludedTerms = excludedTerms
        self.mandatoryCompanyTerms = mandatoryCompanyTerms
    }

    public static let defaultMandatoryCompanyTerms = [
        "СИЛА",
        "Платформикс",
        "Базовые решения"
    ]

    public static let standard = AnonymizationSettings(
        enabledCategories: Set(AnonymizerEngine.Category.allCases),
        excludedTerms: [],
        mandatoryCompanyTerms: defaultMandatoryCompanyTerms
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case enabledCategories
        case excludedTerms
        case mandatoryCompanyTerms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        enabledCategories = try container.decode(
            Set<AnonymizerEngine.Category>.self,
            forKey: .enabledCategories
        )
        if schemaVersion < 2 {
            enabledCategories.insert(.requisites)
        }
        excludedTerms = try container.decodeIfPresent(
            [String].self,
            forKey: .excludedTerms
        ) ?? []
        mandatoryCompanyTerms = try container.decodeIfPresent(
            [String].self,
            forKey: .mandatoryCompanyTerms
        ) ?? Self.defaultMandatoryCompanyTerms
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .schemaVersion)
        try container.encode(enabledCategories, forKey: .enabledCategories)
        try container.encode(excludedTerms, forKey: .excludedTerms)
        try container.encode(mandatoryCompanyTerms, forKey: .mandatoryCompanyTerms)
    }
}
