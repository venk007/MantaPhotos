import Foundation

struct AppLocalizer {
    static let shared = AppLocalizer()

    private let values: [String: [String: String]]

    private init() {
        guard
            let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = object["strings"] as? [String: Any]
        else {
            values = [:]
            return
        }

        var parsed: [String: [String: String]] = [:]
        for (key, rawEntry) in strings {
            guard
                let entry = rawEntry as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else { continue }

            var translations: [String: String] = [:]
            for (language, rawLocalization) in localizations {
                guard
                    let localization = rawLocalization as? [String: Any],
                    let stringUnit = localization["stringUnit"] as? [String: Any],
                    let value = stringUnit["value"] as? String
                else { continue }
                translations[language] = value
            }
            parsed[key] = translations
        }
        values = parsed
    }

    func localized(_ key: String, language: AppLanguage) -> String {
        let resolvedLanguage: String
        switch language {
        case .system:
            resolvedLanguage = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        case .zhHans:
            resolvedLanguage = "zh-Hans"
        case .en:
            resolvedLanguage = "en"
        }

        if let value = values[key]?[resolvedLanguage] {
            return value
        }
        if resolvedLanguage != "en", let value = values[key]?["en"] {
            return value
        }
        return key
    }
}
