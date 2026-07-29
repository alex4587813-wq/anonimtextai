import AppKit
import AnonymizerCore
import Foundation
import OSLog
import SwiftUI

@MainActor
final class AnonymizerViewModel: ObservableObject {
    enum Status: Equatable {
        case waiting
        case processing
        case ready(Int)
        case noSensitiveData
        case stale
        case copied
        case error(String)

        var message: String {
            switch self {
            case .waiting:
                return "Вставьте текст"
            case .processing:
                return "Анализ текста…"
            case .ready(let count):
                return "Готово: найдено фрагментов — \(count)"
            case .noSensitiveData:
                return "Чувствительные данные не найдены"
            case .stale:
                return "Исходный текст изменён — выполните обработку повторно"
            case .copied:
                return "Текст скопирован"
            case .error(let message):
                return message
            }
        }

        var symbolName: String {
            switch self {
            case .waiting:
                return "doc.text"
            case .processing:
                return "hourglass"
            case .ready:
                return "checkmark.circle.fill"
            case .noSensitiveData:
                return "checkmark.shield"
            case .stale:
                return "exclamationmark.triangle.fill"
            case .copied:
                return "doc.on.doc.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ready, .noSensitiveData, .copied:
                return .green
            case .stale:
                return .orange
            case .error:
                return .red
            default:
                return .secondary
            }
        }
    }

    @Published var sourceText = "" {
        didSet {
            guard !isReplacingSource, sourceText != oldValue else { return }
            processingGeneration = UUID()
            isProcessing = false
            resultIsCurrent = false
            counts = [:]
            status = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .waiting : .stale
        }
    }

    @Published var anonymizedText = ""
    @Published private(set) var status: Status = .waiting
    @Published private(set) var isProcessing = false
    @Published private(set) var resultIsCurrent = false
    @Published private(set) var counts: [AnonymizerEngine.Category: Int] = [:]
    @Published private(set) var settings: AnonymizationSettings
    @Published var exclusionDraft = ""
    @Published var mandatoryCompanyDraft = ""

    private let engine = AnonymizerEngine()
    private let logger = Logger(subsystem: "ru.platformix.LocalAnonymizer", category: "application")
    private let defaults: UserDefaults
    private var isReplacingSource = false
    private var processingGeneration = UUID()
    private var copyFeedbackGeneration = UUID()
    private static let settingsKey = "anonymizationSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.settingsKey),
           let savedSettings = try? JSONDecoder().decode(AnonymizationSettings.self, from: data) {
            settings = savedSettings
        } else {
            settings = .standard
        }
    }

    var canCopy: Bool {
        resultIsCurrent && !anonymizedText.isEmpty && !isProcessing
    }

    var entitySummary: String? {
        let items = AnonymizerEngine.Category.allCases.compactMap { category -> String? in
            guard let count = counts[category], count > 0 else { return nil }
            return "\(category.displayName): \(count)"
        }
        return items.isEmpty ? nil : items.joined(separator: " · ")
    }

    func isCategoryEnabled(_ category: AnonymizerEngine.Category) -> Bool {
        settings.enabledCategories.contains(category)
    }

    func setCategory(_ category: AnonymizerEngine.Category, enabled: Bool) {
        var updatedSettings = settings
        if enabled {
            updatedSettings.enabledCategories.insert(category)
        } else {
            updatedSettings.enabledCategories.remove(category)
        }
        settings = updatedSettings
        saveSettingsAndInvalidateResult()
        logger.info(
            "Category setting changed, enabled categories: \(updatedSettings.enabledCategories.count, privacy: .public)"
        )
    }

    func addExclusion() {
        let term = exclusionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        let alreadyExists = settings.excludedTerms.contains {
            $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !alreadyExists else {
            exclusionDraft = ""
            return
        }

        var updatedSettings = settings
        updatedSettings.excludedTerms.append(term)
        settings = updatedSettings
        exclusionDraft = ""
        saveSettingsAndInvalidateResult()
        logger.info(
            "Exclusion added, total exclusions: \(updatedSettings.excludedTerms.count, privacy: .public)"
        )
    }

    func removeExclusion(_ term: String) {
        var updatedSettings = settings
        updatedSettings.excludedTerms.removeAll { $0 == term }
        guard updatedSettings != settings else { return }

        settings = updatedSettings
        saveSettingsAndInvalidateResult()
        logger.info(
            "Exclusion removed, total exclusions: \(updatedSettings.excludedTerms.count, privacy: .public)"
        )
    }

    func addMandatoryCompanyTerm() {
        let term = mandatoryCompanyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        let alreadyExists = settings.mandatoryCompanyTerms.contains {
            $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !alreadyExists else {
            mandatoryCompanyDraft = ""
            return
        }

        var updatedSettings = settings
        updatedSettings.mandatoryCompanyTerms.append(term)
        settings = updatedSettings
        mandatoryCompanyDraft = ""
        saveSettingsAndInvalidateResult()
        logger.info(
            "Replacement term added, total terms: \(updatedSettings.mandatoryCompanyTerms.count, privacy: .public)"
        )
    }

    func removeMandatoryCompanyTerm(_ term: String) {
        var updatedSettings = settings
        updatedSettings.mandatoryCompanyTerms.removeAll { $0 == term }
        guard updatedSettings != settings else { return }

        settings = updatedSettings
        saveSettingsAndInvalidateResult()
        logger.info(
            "Replacement term removed, total terms: \(updatedSettings.mandatoryCompanyTerms.count, privacy: .public)"
        )
    }

    func pasteAndProcess() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            status = .error("В буфере обмена нет текста")
            logger.notice("Paste skipped: clipboard has no text")
            return
        }

        isReplacingSource = true
        sourceText = clipboardText
        isReplacingSource = false
        logger.info("Text pasted, characters: \(clipboardText.count, privacy: .public)")
        processSource()
    }

    func processSource() {
        let text = sourceText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .waiting
            resultIsCurrent = false
            return
        }

        let generation = UUID()
        let currentSettings = settings
        processingGeneration = generation
        isProcessing = true
        resultIsCurrent = false
        status = .processing
        logger.info("Anonymization started, characters: \(text.count, privacy: .public)")

        Task {
            let result = await Task.detached(priority: .userInitiated) { [engine] in
                engine.anonymize(text, settings: currentSettings)
            }.value

            guard generation == processingGeneration else {
                logger.notice("Outdated anonymization result discarded")
                return
            }

            anonymizedText = result.text
            counts = result.counts
            resultIsCurrent = true
            isProcessing = false

            if result.totalMatches == 0 {
                status = .noSensitiveData
            } else {
                status = .ready(result.totalMatches)
            }

            logger.info("Anonymization completed, fragments: \(result.totalMatches, privacy: .public)")
        }
    }

    func copyResult() {
        guard canCopy else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.setString(anonymizedText, forType: .string) {
            status = .copied
            logger.info("Anonymized text copied, characters: \(self.anonymizedText.count, privacy: .public)")

            let feedbackGeneration = UUID()
            copyFeedbackGeneration = feedbackGeneration

            Task { [weak self] in
                try? await Task<Never, Never>.sleep(nanoseconds: 1_800_000_000)
                guard let self,
                      self.copyFeedbackGeneration == feedbackGeneration,
                      self.status == .copied,
                      self.resultIsCurrent else {
                    return
                }

                let totalMatches = self.counts.values.reduce(0, +)
                self.status = totalMatches == 0
                    ? .noSensitiveData
                    : .ready(totalMatches)
            }
        } else {
            status = .error("Не удалось записать текст в буфер обмена")
            logger.error("Failed to write anonymized text to clipboard")
        }
    }

    private func saveSettingsAndInvalidateResult() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        } else {
            logger.error("Failed to encode anonymization settings")
        }

        processingGeneration = UUID()
        isProcessing = false
        resultIsCurrent = false
        counts = [:]

        if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .waiting
        } else {
            status = .stale
        }
    }
}
