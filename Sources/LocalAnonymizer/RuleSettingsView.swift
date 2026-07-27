import AnonymizerCore
import SwiftUI

struct RuleSettingsView: View {
    @ObservedObject var viewModel: AnonymizerViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                categoryRules
                Divider()
                exclusionRules
                Divider()
                mandatoryReplacementRules
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Label("Настройки правил анонимизации", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text(
                    "Категории: \(viewModel.settings.enabledCategories.count)"
                        + " из \(AnonymizerEngine.Category.allCases.count)"
                        + " · Исключения: \(viewModel.settings.excludedTerms.count)"
                        + " · Обязательные замены: \(viewModel.settings.mandatoryCompanyTerms.count)"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
    }

    private var categoryRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что обезличивать")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 18) {
                ForEach(AnonymizerEngine.Category.allCases, id: \.self) { category in
                    Toggle(
                        category.displayName,
                        isOn: Binding(
                            get: { viewModel.isCategoryEnabled(category) },
                            set: { viewModel.setCategory(category, enabled: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var exclusionRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Список исключений")
                .font(.subheadline.weight(.semibold))

            Text("Если найденный фрагмент содержит указанное слово или фразу, он останется без изменений.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Например: Платформикс", text: $viewModel.exclusionDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.addExclusion()
                    }

                Button("Добавить") {
                    viewModel.addExclusion()
                }
                .controlSize(.large)
                .disabled(viewModel.exclusionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.settings.excludedTerms.isEmpty {
                Text("Исключения не добавлены")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 30)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.settings.excludedTerms, id: \.self) { term in
                            HStack(spacing: 5) {
                                Text(term)
                                    .lineLimit(1)

                                Button {
                                    viewModel.removeExclusion(term)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Удалить исключение \(term)")
                            }
                            .font(.callout)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 34)
            }
        }
    }

    private var mandatoryReplacementRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Обязательная замена организаций")
                .font(.subheadline.weight(.semibold))

            Text("Эти слова и фразы всегда заменяются как организация. Правило имеет приоритет над категориями и исключениями.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Название организации", text: $viewModel.mandatoryCompanyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.addMandatoryCompanyTerm()
                    }

                Button("Добавить") {
                    viewModel.addMandatoryCompanyTerm()
                }
                .controlSize(.large)
                .disabled(
                    viewModel.mandatoryCompanyDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }

            if viewModel.settings.mandatoryCompanyTerms.isEmpty {
                Text("Обязательные замены не добавлены")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 30)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.settings.mandatoryCompanyTerms, id: \.self) { term in
                            HStack(spacing: 5) {
                                Text(term)
                                    .lineLimit(1)

                                Button {
                                    viewModel.removeMandatoryCompanyTerm(term)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Удалить обязательную замену \(term)")
                            }
                            .font(.callout)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.16))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 34)
            }
        }
    }
}
