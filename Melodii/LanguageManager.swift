import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable {
    case system = "跟随系统"
    case chinese = "简体中文"
    case english = "English"

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.current.identifier
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
        }
    }

    var currentLocale: Locale { Locale(identifier: currentLanguage.localeIdentifier) }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .system
    }

    func setLanguage(_ lang: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentLanguage = lang
        }
    }
}
