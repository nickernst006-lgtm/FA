import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Поле даты/времени, которое по умолчанию ПУСТОЕ (nil) и заполняется только
/// вручную — по требованию: "всегда ввожу дату и время вручную".
struct OptionalPickerField<Content: View>: View {
    let label: String
    @Binding var value: Date?
    let placeholder: String
    let pickerContent: (Binding<Date>) -> Content

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let v = value {
                pickerContent(Binding(get: { v }, set: { value = $0 }))
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить \(label.lowercased())")
            } else {
                Button(placeholder) {
                    value = Date()
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Системное меню "Поделиться" для экспорта файла.
/// После закрытия меню временный файл удаляется — расшифрованные данные
/// не остаются лежать на диске.
struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        let url = fileURL
        let finish = onFinish
        vc.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
            finish()
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Обёртка, чтобы показывать лист экспорта через .sheet(item:)
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Отслеживание активности для автоблокировки

/// Распознаватель, который только «замечает» касание и сразу отказывается от него,
/// поэтому никак не мешает кнопкам, спискам и полям ввода.
final class TouchObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouch: (() -> Void)?

    /// Настройка «невмешательства»: касания проходят дальше без задержек
    func configurePassThrough() {
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch?()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Невидимый вид, который вешает TouchObserverRecognizer на всё окно приложения.
struct ActivityCatcher: UIViewRepresentable {
    let onActivity: () -> Void

    final class CatcherView: UIView {
        var onActivity: (() -> Void)?
        private var installed: TouchObserverRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, installed == nil else { return }
            let rec = TouchObserverRecognizer(target: nil, action: nil)
            rec.configurePassThrough()
            rec.onTouch = { [weak self] in self?.onActivity?() }
            window.addGestureRecognizer(rec)
            installed = rec
        }
    }

    func makeUIView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.onActivity = onActivity
        return v
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        uiView.onActivity = onActivity
    }
}

/// Экран-заглушка: закрывает данные в переключателе приложений
/// и когда приложение неактивно.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                AppBadge(size: 64)
                Text("Учёт операций").font(.headline)
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }
}

/// Значок приложения внутри интерфейса
struct AppBadge: View {
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.35, blue: 0.85),
                                              Color(red: 0.09, green: 0.62, blue: 0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Text("₽")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Справочники

/// Строка справочника с переименованием и удалением
struct EditableRow: View {
    let name: String
    var subtitle: String? = nil
    var onRename: (String) -> Void
    var onDelete: () -> Void
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            if isEditing {
                TextField("Название", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                Button("Готово", action: commit)
                    .buttonStyle(.borderless)
            } else {
                Text(name)
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button {
                    editText = name
                    isEditing = true
                    focused = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Переименовать \(name)")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Удалить \(name)")
            }
        }
    }

    private func commit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != name { onRename(trimmed) }
        isEditing = false
    }
}

/// Строка добавления нового значения в справочник
struct AddRow: View {
    let placeholder: String
    var onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .submitLabel(.done)
                .onSubmit(add)
            Button("Добавить", action: add)
                .buttonStyle(.borderless)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        text = ""
    }
}
