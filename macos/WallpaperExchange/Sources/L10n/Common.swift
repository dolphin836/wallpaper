import Foundation

// Shared strings used across multiple pages (generic buttons, the Settings
// language section). Page-specific strings live in their own namespace
// files. The four instances share one memberwise init, so a missing
// translation fails the build.

struct CommonStrings {
    let cancel: String
    let confirm: String
    let retry: String
    let done: String
    let language: String
    let languageSystem: String
    let languageFootnote: String
}

private let commonEN = CommonStrings(
    cancel: "Cancel",
    confirm: "Confirm",
    retry: "Try again",
    done: "Done",
    language: "Language",
    languageSystem: "System default",
    languageFootnote: "Applies immediately. Category, tag, and collection names follow this language too."
)

private let commonZhCN = CommonStrings(
    cancel: "取消",
    confirm: "确认",
    retry: "重试",
    done: "完成",
    language: "语言",
    languageSystem: "跟随系统",
    languageFootnote: "立即生效。分类、标签和合集名称也会跟随此语言。"
)

private let commonZhTW = CommonStrings(
    cancel: "取消",
    confirm: "確認",
    retry: "重試",
    done: "完成",
    language: "語言",
    languageSystem: "跟隨系統",
    languageFootnote: "立即生效。分類、標籤與合輯名稱也會跟隨此語言。"
)

private let commonJA = CommonStrings(
    cancel: "キャンセル",
    confirm: "確認",
    retry: "再試行",
    done: "完了",
    language: "言語",
    languageSystem: "システムに従う",
    languageFootnote: "すぐに反映されます。カテゴリ・タグ・コレクション名もこの言語に従います。"
)

extension L10n {
    static var common: CommonStrings {
        switch lang {
        case .en: commonEN
        case .zhCN: commonZhCN
        case .zhTW: commonZhTW
        case .ja: commonJA
        }
    }
}
