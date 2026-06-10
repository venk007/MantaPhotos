import Foundation

/// 应用内本地化（支持运行时切换语言，独立于系统语言）。
///
/// 关键修复：`Localizable.xcstrings` 经 SwiftPM `.process` 会被**编译**成各语言
/// `<lang>.lproj/Localizable.strings`，并不会以 `.xcstrings` 原文件存在于 bundle 中。
/// 因此优先用 `Bundle.module` 下对应语言子 bundle 的 `localizedString` 读取编译产物；
/// 若 bundle 里恰好保留了原始 `.xcstrings`（`.copy` 资源时）则作为兜底。
struct AppLocalizer {
    static let shared = AppLocalizer()

    /// 原始 xcstrings 解析结果（仅当 bundle 里有 .xcstrings 原文件时非空）。
    private let rawValues: [String: [String: String]]

    private init() {
        rawValues = Self.loadRawXCStrings()
    }

    func localized(_ key: String, language: AppLanguage) -> String {
        let lang = Self.resolvedLanguageCode(language)

        // 1) 编译后的 <lang>.lproj
        if let value = Self.compiledString(forKey: key, languageCode: lang) {
            return value
        }
        // 2) 原始 xcstrings 兜底
        if let value = rawValues[key]?[lang] {
            return value
        }
        if lang != "en", let value = rawValues[key]?["en"] {
            return value
        }
        // 3) 最后回退到 key（即英文源串）
        return key
    }

    private static func resolvedLanguageCode(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    /// 读取指定语言子 bundle 的编译串；缺失返回 nil。
    private static func compiledString(forKey key: String, languageCode: String) -> String? {
        // 不同工具链可能用 "zh-Hans" 或 "zh_Hans" 作为 .lproj 目录名，挨个尝试。
        let candidates: [String]
        switch languageCode {
        case "zh-Hans": candidates = ["zh-Hans", "zh_Hans", "zh-Hant", "zh"]
        default: candidates = [languageCode]
        }

        let sentinel = "\u{1}__missing__\u{1}"
        for code in candidates {
            guard let path = Bundle.module.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
            if value != sentinel {
                return value
            }
        }
        return nil
    }

    private static func loadRawXCStrings() -> [String: [String: String]] {
        guard
            let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
                ?? Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings", subdirectory: "Resources"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = object["strings"] as? [String: Any]
        else {
            return [:]
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
        return parsed
    }
}
