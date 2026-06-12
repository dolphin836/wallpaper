import Foundation

// Strings for the sign in / register modal (AuthView). The four
// instances share one memberwise init, so a missing translation
// fails the build.

struct AuthStrings {
    let createAccount: String
    let signIn: String
    let registerTitle: String
    let loginTitle: String
    let registerSubtitle: String
    let loginSubtitle: String
    let creatingAccount: String
    let signingIn: String
    let close: String
    let usernameLabel: String
    let emailLabel: String
    let passwordLabel: String
    let passwordHintNew: String
    let haveAccount: String
    let newHere: String
    let createOne: String
    let usernameLength: String
    let invalidEmail: String
    let passwordTooShort: String
    let wrongCredentials: String
    let alreadyTaken: String
    let checkFields: String
    let networkError: String
    let badResponse: String
}

private let authEN = AuthStrings(
    createAccount: "Create account",
    signIn: "Sign in",
    registerTitle: "Join the exchange.",
    loginTitle: "Welcome back.",
    registerSubtitle: "Get 10 coins to start collecting, downloading, and sharing wallpapers.",
    loginSubtitle: "Use your Wallpaper Exchange account without leaving the Mac app.",
    creatingAccount: "Creating account",
    signingIn: "Signing in",
    close: "Close",
    usernameLabel: "Username",
    emailLabel: "Email",
    passwordLabel: "Password",
    passwordHintNew: "At least 8 characters",
    haveAccount: "Already have an account?",
    newHere: "New here?",
    createOne: "Create one",
    usernameLength: "Username must be 3 to 32 characters.",
    invalidEmail: "Enter a valid email address.",
    passwordTooShort: "Password must be at least 8 characters.",
    wrongCredentials: "Email or password is incorrect.",
    alreadyTaken: "Username or email is already taken.",
    checkFields: "Check the fields and try again.",
    networkError: "Network error. Check your connection and try again.",
    badResponse: "The server response could not be read."
)

private let authZhCN = AuthStrings(
    createAccount: "创建账号",
    signIn: "登录",
    registerTitle: "加入壁纸交换站。",
    loginTitle: "欢迎回来。",
    registerSubtitle: "注册即送 10 金币，开始收藏、下载和分享壁纸。",
    loginSubtitle: "无需离开 Mac 应用，直接使用你的 Wallpaper Exchange 账号。",
    creatingAccount: "正在创建账号",
    signingIn: "正在登录",
    close: "关闭",
    usernameLabel: "用户名",
    emailLabel: "邮箱",
    passwordLabel: "密码",
    passwordHintNew: "至少 8 个字符",
    haveAccount: "已经有账号？",
    newHere: "第一次来？",
    createOne: "注册一个",
    usernameLength: "用户名长度需为 3 到 32 个字符。",
    invalidEmail: "请输入有效的邮箱地址。",
    passwordTooShort: "密码至少需要 8 个字符。",
    wrongCredentials: "邮箱或密码不正确。",
    alreadyTaken: "用户名或邮箱已被占用。",
    checkFields: "请检查填写内容后重试。",
    networkError: "网络错误，请检查连接后重试。",
    badResponse: "无法解析服务器响应。"
)

private let authZhTW = AuthStrings(
    createAccount: "建立帳號",
    signIn: "登入",
    registerTitle: "加入桌布交換站。",
    loginTitle: "歡迎回來。",
    registerSubtitle: "註冊即送 10 金幣，開始收藏、下載與分享桌布。",
    loginSubtitle: "不必離開 Mac 應用程式，直接使用你的 Wallpaper Exchange 帳號。",
    creatingAccount: "正在建立帳號",
    signingIn: "正在登入",
    close: "關閉",
    usernameLabel: "使用者名稱",
    emailLabel: "電子郵件",
    passwordLabel: "密碼",
    passwordHintNew: "至少 8 個字元",
    haveAccount: "已經有帳號？",
    newHere: "第一次來？",
    createOne: "註冊一個",
    usernameLength: "使用者名稱長度需為 3 到 32 個字元。",
    invalidEmail: "請輸入有效的電子郵件地址。",
    passwordTooShort: "密碼至少需要 8 個字元。",
    wrongCredentials: "電子郵件或密碼不正確。",
    alreadyTaken: "使用者名稱或電子郵件已被使用。",
    checkFields: "請檢查欄位內容後再試一次。",
    networkError: "網路錯誤，請檢查連線後再試一次。",
    badResponse: "無法解析伺服器回應。"
)

private let authJA = AuthStrings(
    createAccount: "新規登録",
    signIn: "ログイン",
    registerTitle: "壁紙の交換所へようこそ。",
    loginTitle: "おかえりなさい。",
    registerSubtitle: "登録すると 10 コインがもらえて、壁紙の収集・ダウンロード・シェアを始められます。",
    loginSubtitle: "Mac アプリを離れずに Wallpaper Exchange アカウントを使えます。",
    creatingAccount: "アカウントを作成中",
    signingIn: "ログイン中",
    close: "閉じる",
    usernameLabel: "ユーザー名",
    emailLabel: "メールアドレス",
    passwordLabel: "パスワード",
    passwordHintNew: "8 文字以上",
    haveAccount: "すでにアカウントをお持ちですか？",
    newHere: "はじめてですか？",
    createOne: "新規登録",
    usernameLength: "ユーザー名は 3〜32 文字で入力してください。",
    invalidEmail: "有効なメールアドレスを入力してください。",
    passwordTooShort: "パスワードは 8 文字以上にしてください。",
    wrongCredentials: "メールアドレスまたはパスワードが正しくありません。",
    alreadyTaken: "そのユーザー名またはメールアドレスは既に使われています。",
    checkFields: "入力内容を確認してもう一度お試しください。",
    networkError: "ネットワークエラーです。接続を確認してもう一度お試しください。",
    badResponse: "サーバーの応答を読み取れませんでした。"
)

extension L10n {
    static var auth: AuthStrings {
        switch lang {
        case .en: authEN
        case .zhCN: authZhCN
        case .zhTW: authZhTW
        case .ja: authJA
        }
    }
}
