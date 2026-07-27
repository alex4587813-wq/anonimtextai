import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AnonymizerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            processingStatus
            RuleSettingsView(viewModel: viewModel)

            HSplitView {
                textPanel(
                    title: "Исходный текст",
                    text: $viewModel.sourceText,
                    placeholder: "Вставьте сюда текст с чувствительными данными…"
                ) {
                    sourceActions
                }

                textPanel(
                    title: "Обезличенный текст",
                    text: $viewModel.anonymizedText,
                    placeholder: "Здесь появится результат обработки"
                ) {
                    resultActions
                }
            }
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var processingStatus: some View {
        if viewModel.isProcessing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Обработка текста…")
                    .font(.callout)
            }
            .frame(minHeight: 22)
            .transition(.opacity)
        } else if viewModel.resultIsCurrent {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(
                    "Обработано символов: \(viewModel.sourceText.count.formatted())"
                        + " · Очищено фрагментов: \(viewModel.counts.values.reduce(0, +).formatted())"
                )
                .font(.callout.weight(.medium))

                Spacer()

                if let summary = viewModel.entitySummary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Чувствительные данные не найдены")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 22)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Локальный анонимизатор")
                .font(.title.weight(.bold))

            Text("Текст обрабатывается локально на вашем компьютере и не отправляется в интернет.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func textPanel<Footer: View>(
        title: String,
        text: Binding<String>,
        placeholder: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)

                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 4, y: 1)

            footer()
        }
        .padding(1)
        .frame(minWidth: 360)
    }

    private var sourceActions: some View {
        HStack {
            Button("Вставить из буфера") {
                viewModel.pasteAndProcess()
            }
            .controlSize(.large)

            Button("Обезличить") {
                viewModel.processSource()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)

            Spacer()
        }
    }

    private var resultActions: some View {
        HStack {
            Text("Проверьте результат перед передачей во внешний сервис.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.copyResult()
            } label: {
                Label(
                    viewModel.status == .copied ? "Скопировано" : "Скопировать",
                    systemImage: viewModel.status == .copied
                        ? "checkmark"
                        : "doc.on.doc"
                )
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .buttonStyle(.borderedProminent)
            .tint(viewModel.status == .copied ? .green : .accentColor)
            .controlSize(.large)
            .disabled(!viewModel.canCopy)
            .animation(.easeInOut(duration: 0.2), value: viewModel.status)
        }
    }
}
