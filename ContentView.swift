import SwiftUI
import UIKit
import Combine

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if appState.isUnlocked {
                MainTabView()
            } else {
                LockView()
            }
            // Закрываем содержимое, когда приложение неактивно — например,
            // в переключателе приложений данные не будут видны на миниатюре.
            if scenePhase != .active {
                PrivacyCover().transition(.opacity)
            }
        }
        .background(ActivityCatcher { appState.registerActivity() })
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in
            appState.registerActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in
            appState.registerActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.checkAutoLock() }
        }
        .alert("Ошибка", isPresented: Binding(
            get: { appState.saveError != nil },
            set: { if !$0 { appState.saveError = nil } }
        )) {
            Button("OK", role: .cancel) { appState.saveError = nil }
        } message: {
            Text(appState.saveError ?? "")
        }
    }
}

struct MainTabView: View {
    @State private var editState: EditState? = nil
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FormView(editState: $editState, onSaved: { selectedTab = 1 })
            }
            .tabItem { Label("Форма", systemImage: "square.and.pencil") }
            .tag(0)

            NavigationStack {
                HistoryView(editState: $editState, goToForm: { selectedTab = 0 })
            }
            .tabItem { Label("История", systemImage: "list.bullet.rectangle") }
            .tag(1)

            NavigationStack {
                StatsView()
            }
            .tabItem { Label("Статистика", systemImage: "chart.bar") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
            .tag(3)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label("О приложении", systemImage: "info.circle") }
            .tag(4)
        }
    }
}
