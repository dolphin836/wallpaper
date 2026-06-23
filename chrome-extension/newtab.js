(function () {
  const API_BASE = "https://wallpaperexchange.com/api/v1";
  const SITE_BASE = "https://wallpaperexchange.com";
  const SETTINGS_KEY = "wallpaperExchangeNewTabSettings";
  const CACHE_KEY = "wallpaperExchangeNewTabCache";
  const SESSION_KEY = "wallpaperExchangeChromeSession";
  const SESSION_STAMP_KEY = "wallpaperExchangeChromeSessionStamp";
  const SESSION_TTL_MS = 30 * 60 * 1000;
  const MAX_QUICK_LINKS = 10;

  const extensionVersion = getExtensionVersion();

  const DEFAULT_SETTINGS = {
    source: "weekly",
    collectionId: null,
    collectionTitle: "",
    wallpaperId: null,
    token: "",
    user: null,
    language: "auto",
    randomEnabled: false,
    randomIntervalMinutes: 15,
    showClock: true,
    showSearch: true,
    showQuickLinks: true,
    quickLinks: []
  };

  const COPY = {
    en: {
      title: "Wallpaper Exchange",
      settings: "Settings",
      like: "Like",
      liked: "Liked",
      favorite: "Save",
      favorited: "Saved",
      download: "Download",
      downloaded: "Got it",
      searchLabel: "Search the web",
      searchPlaceholder: "Search the web or enter a website",
      panelKicker: "Wallpaper Exchange",
      panelTitle: "New tab settings",
      sourceTitle: "Wallpaper source",
      sourceWeekly: "Weekly Picks",
      sourceWeeklyHint: "Curated every week",
      sourceFavorites: "My Favorites",
      sourceAuthHint: "Sign in required",
      sourceCollection: "My Collection",
      sourceCollectionHint: "Choose one collection",
      collectionLabel: "Collection",
      reload: "Reload",
      refresh: "Refresh",
      wallpaperListTitle: "Wallpapers",
      randomTitle: "Random wallpaper",
      randomEnable: "Enable random",
      randomHint: "Randomly picks from the current source.",
      randomInterval: "Interval",
      intervalNewTab: "Every new tab",
      languageTitle: "Language",
      languageLabel: "Interface language",
      languageAuto: "Follow browser",
      widgetsTitle: "Widgets",
      clockWidget: "Clock",
      clockHint: "Uses your browser format.",
      searchWidget: "Search",
      searchHint: "Search or enter a website.",
      quickLinksWidget: "Quick links",
      quickLinksHint: "Show shortcuts below search.",
      quickLinksTitle: "Quick links",
      quickLinkName: "Name",
      quickLinkUrl: "URL",
      quickLinkNamePlaceholder: "Wallpaper Exchange",
      quickLinkUrlPlaceholder: "wallpaperexchange.com",
      addQuickLink: "Add",
      addShortcut: "Add shortcut",
      deleteQuickLink: "Remove",
      noQuickLinks: "No quick links yet.",
      quickLinkInvalid: "Enter a valid website.",
      quickLinkLimit: "You can add up to {count} links.",
      accountTitle: "Account",
      accountPrompt: "Sign in to use favorites, collections, likes, and downloads.",
      openAuth: "Sign in or create account",
      signOut: "Sign out",
      aboutTitle: "About",
      versionLabel: "Version",
      openWebsite: "Open website",
      terms: "Terms",
      privacy: "Privacy",
      dmca: "DMCA",
      authKicker: "Wallpaper Exchange",
      authTitle: "Account",
      login: "Sign in",
      register: "Register",
      username: "Username",
      email: "Email",
      password: "Password",
      legalNote: "By creating an account you agree to the site terms and privacy policy.",
      loading: "Loading wallpapers...",
      loadingCollections: "Loading collections...",
      noWallpapers: "No wallpapers here yet.",
      noCollections: "No collections yet.",
      chooseCollection: "Choose a collection first.",
      signInToUse: "Sign in to use this source.",
      usingCache: "Using the last loaded wallpaper set.",
      highQualityFailed: "The high quality image did not load. Showing the preview.",
      authRequired: "Sign in first.",
      emailPasswordRequired: "Enter your email and password.",
      usernameRequired: "Enter a username.",
      signingIn: "Signing in...",
      creatingAccount: "Creating account...",
      authFailed: "Account request failed.",
      signedIn: "Signed in.",
      signedOut: "Signed out.",
      insufficientCoins: "Not enough coins.",
      downloadFailed: "Download failed.",
      downloadDone: "Download started.",
      actionFailed: "Action failed.",
      collectionCount: "{count} wallpapers",
      coins: "{count} coins",
      live: "Live",
      dynamic: "Dynamic",
      video: "Video"
    },
    zh: {
      title: "Wallpaper Exchange",
      settings: "设置",
      like: "点赞",
      liked: "已点赞",
      favorite: "收藏",
      favorited: "已收藏",
      download: "下载",
      downloaded: "已获取",
      searchLabel: "搜索网页",
      searchPlaceholder: "搜索网页或输入网址",
      panelKicker: "Wallpaper Exchange",
      panelTitle: "新标签页设置",
      sourceTitle: "壁纸来源",
      sourceWeekly: "每周推荐",
      sourceWeeklyHint: "每周精选",
      sourceFavorites: "我的收藏",
      sourceAuthHint: "需要登录",
      sourceCollection: "我的合集",
      sourceCollectionHint: "选择一个合集",
      collectionLabel: "合集",
      reload: "重新加载",
      refresh: "刷新",
      wallpaperListTitle: "壁纸列表",
      randomTitle: "随机壁纸",
      randomEnable: "启用随机",
      randomHint: "从当前来源里随机选择壁纸。",
      randomInterval: "切换时间",
      intervalNewTab: "每次新标签页",
      languageTitle: "语言",
      languageLabel: "界面语言",
      languageAuto: "跟随浏览器",
      widgetsTitle: "小组件",
      clockWidget: "时钟",
      clockHint: "使用浏览器默认格式。",
      searchWidget: "搜索",
      searchHint: "搜索或输入网址。",
      quickLinksWidget: "常用网址",
      quickLinksHint: "在搜索框下面显示常用网址。",
      quickLinksTitle: "常用网址",
      quickLinkName: "名称",
      quickLinkUrl: "网址",
      quickLinkNamePlaceholder: "Wallpaper Exchange",
      quickLinkUrlPlaceholder: "wallpaperexchange.com",
      addQuickLink: "添加",
      addShortcut: "添加网址",
      deleteQuickLink: "删除",
      noQuickLinks: "还没有常用网址。",
      quickLinkInvalid: "请输入有效的网址。",
      quickLinkLimit: "最多可以添加 {count} 个网址。",
      accountTitle: "登录/注册",
      accountPrompt: "登录后可以使用收藏、合集、点赞和下载。",
      openAuth: "登录或注册",
      signOut: "退出登录",
      aboutTitle: "其他信息",
      versionLabel: "当前版本",
      openWebsite: "打开官网",
      terms: "服务条款",
      privacy: "隐私政策",
      dmca: "DMCA",
      authKicker: "Wallpaper Exchange",
      authTitle: "账号",
      login: "登录",
      register: "注册",
      username: "用户名",
      email: "邮箱",
      password: "密码",
      legalNote: "创建账号即表示你同意官网的服务条款和隐私政策。",
      loading: "正在加载壁纸...",
      loadingCollections: "正在加载合集...",
      noWallpapers: "这里还没有壁纸。",
      noCollections: "还没有合集。",
      chooseCollection: "请先选择一个合集。",
      signInToUse: "登录后才能使用这个来源。",
      usingCache: "正在使用上一次加载的壁纸列表。",
      highQualityFailed: "高清图片加载失败，当前显示预览图。",
      authRequired: "请先登录。",
      emailPasswordRequired: "请输入邮箱和密码。",
      usernameRequired: "请输入用户名。",
      signingIn: "正在登录...",
      creatingAccount: "正在创建账号...",
      authFailed: "账号请求失败。",
      signedIn: "已登录。",
      signedOut: "已退出登录。",
      insufficientCoins: "金币不足。",
      downloadFailed: "下载失败。",
      downloadDone: "已开始下载。",
      actionFailed: "操作失败。",
      collectionCount: "{count} 张壁纸",
      coins: "{count} 金币",
      live: "动态",
      dynamic: "动态",
      video: "视频"
    }
  };

  COPY["zh-CN"] = COPY.zh;
  COPY["zh-TW"] = {
    ...COPY.zh,
    settings: "設定",
    liked: "已按讚",
    searchLabel: "搜尋網頁",
    searchPlaceholder: "搜尋網頁或輸入網址",
    panelTitle: "新分頁設定",
    sourceTitle: "桌布來源",
    sourceWeekly: "每週推薦",
    sourceWeeklyHint: "每週精選",
    sourceFavorites: "我的收藏",
    sourceAuthHint: "需要登入",
    sourceCollection: "我的合集",
    sourceCollectionHint: "選擇一個合集",
    collectionLabel: "合集",
    reload: "重新載入",
    wallpaperListTitle: "桌布列表",
    randomTitle: "隨機桌布",
    randomEnable: "啟用隨機",
    randomHint: "從目前來源隨機選擇桌布。",
    randomInterval: "切換時間",
    intervalNewTab: "每次新分頁",
    languageTitle: "語言",
    languageAuto: "跟隨瀏覽器",
    widgetsTitle: "小工具",
    clockHint: "使用瀏覽器預設格式。",
    searchHint: "搜尋或輸入網址。",
    quickLinksWidget: "常用網址",
    quickLinksHint: "在搜尋框下方顯示常用網址。",
    quickLinksTitle: "常用網址",
    quickLinkName: "名稱",
    quickLinkUrl: "網址",
    quickLinkNamePlaceholder: "Wallpaper Exchange",
    quickLinkUrlPlaceholder: "wallpaperexchange.com",
    addQuickLink: "加入",
    addShortcut: "加入網址",
    deleteQuickLink: "刪除",
    noQuickLinks: "還沒有常用網址。",
    quickLinkInvalid: "請輸入有效的網址。",
    quickLinkLimit: "最多可以加入 {count} 個網址。",
    accountTitle: "登入/註冊",
    accountPrompt: "登入後可以使用收藏、合集、按讚和下載。",
    openAuth: "登入或註冊",
    signOut: "登出",
    aboutTitle: "其他資訊",
    versionLabel: "目前版本",
    openWebsite: "開啟官網",
    terms: "服務條款",
    privacy: "隱私政策",
    authTitle: "帳號",
    login: "登入",
    username: "使用者名稱",
    password: "密碼",
    legalNote: "建立帳號即表示你同意官網的服務條款和隱私政策。",
    loading: "正在載入桌布...",
    loadingCollections: "正在載入合集...",
    noWallpapers: "這裡還沒有桌布。",
    noCollections: "還沒有合集。",
    chooseCollection: "請先選擇一個合集。",
    signInToUse: "登入後才能使用這個來源。",
    usingCache: "正在使用上一次載入的桌布列表。",
    highQualityFailed: "高清圖片載入失敗，目前顯示預覽圖。",
    authRequired: "請先登入。",
    emailPasswordRequired: "請輸入信箱和密碼。",
    signingIn: "正在登入...",
    signedIn: "已登入。",
    signedOut: "已登出。",
    downloadDone: "已開始下載。",
    collectionCount: "{count} 張桌布",
    coins: "{count} 金幣",
    live: "動態"
  };
  COPY.ja = {
    ...COPY.en,
    settings: "設定",
    like: "いいね",
    liked: "いいね済み",
    favorite: "保存",
    favorited: "保存済み",
    download: "ダウンロード",
    downloaded: "取得済み",
    searchLabel: "ウェブを検索",
    searchPlaceholder: "検索またはURLを入力",
    panelTitle: "新しいタブの設定",
    sourceTitle: "壁紙ソース",
    sourceWeekly: "週間おすすめ",
    sourceWeeklyHint: "毎週のセレクト",
    sourceFavorites: "お気に入り",
    sourceAuthHint: "ログインが必要",
    sourceCollection: "マイコレクション",
    sourceCollectionHint: "コレクションを選択",
    collectionLabel: "コレクション",
    reload: "再読み込み",
    refresh: "更新",
    wallpaperListTitle: "壁紙一覧",
    randomTitle: "ランダム壁紙",
    randomEnable: "ランダムを有効化",
    randomHint: "現在のソースからランダムに選びます。",
    randomInterval: "間隔",
    intervalNewTab: "新しいタブごと",
    languageTitle: "言語",
    languageLabel: "表示言語",
    languageAuto: "ブラウザに合わせる",
    widgetsTitle: "ウィジェット",
    clockWidget: "時計",
    clockHint: "ブラウザの形式を使用します。",
    searchWidget: "検索",
    searchHint: "検索またはURLを入力します。",
    quickLinksWidget: "よく使うサイト",
    quickLinksHint: "検索欄の下にショートカットを表示します。",
    quickLinksTitle: "よく使うサイト",
    quickLinkName: "名前",
    quickLinkUrl: "URL",
    quickLinkNamePlaceholder: "Wallpaper Exchange",
    quickLinkUrlPlaceholder: "wallpaperexchange.com",
    addQuickLink: "追加",
    addShortcut: "ショートカットを追加",
    deleteQuickLink: "削除",
    noQuickLinks: "まだショートカットはありません。",
    quickLinkInvalid: "有効なURLを入力してください。",
    quickLinkLimit: "{count} 件まで追加できます。",
    accountTitle: "アカウント",
    accountPrompt: "ログインすると、お気に入り、コレクション、いいね、ダウンロードを使えます。",
    openAuth: "ログインまたは登録",
    signOut: "ログアウト",
    aboutTitle: "情報",
    versionLabel: "バージョン",
    openWebsite: "Webサイトを開く",
    terms: "利用規約",
    privacy: "プライバシー",
    authTitle: "アカウント",
    login: "ログイン",
    register: "登録",
    username: "ユーザー名",
    email: "メール",
    password: "パスワード",
    legalNote: "アカウントを作成すると、サイトの利用規約とプライバシーポリシーに同意したものとします。",
    loading: "壁紙を読み込み中...",
    loadingCollections: "コレクションを読み込み中...",
    noWallpapers: "まだ壁紙がありません。",
    noCollections: "まだコレクションがありません。",
    chooseCollection: "先にコレクションを選択してください。",
    signInToUse: "このソースを使うにはログインしてください。",
    usingCache: "前回読み込んだ壁紙セットを表示しています。",
    highQualityFailed: "高画質画像を読み込めませんでした。プレビューを表示しています。",
    authRequired: "先にログインしてください。",
    emailPasswordRequired: "メールとパスワードを入力してください。",
    usernameRequired: "ユーザー名を入力してください。",
    signingIn: "ログイン中...",
    creatingAccount: "アカウント作成中...",
    authFailed: "アカウント処理に失敗しました。",
    signedIn: "ログインしました。",
    signedOut: "ログアウトしました。",
    insufficientCoins: "コインが足りません。",
    downloadFailed: "ダウンロードに失敗しました。",
    downloadDone: "ダウンロードを開始しました。",
    actionFailed: "操作に失敗しました。",
    collectionCount: "{count} 枚の壁紙",
    coins: "{count} コイン",
    live: "ライブ",
    dynamic: "ダイナミック",
    video: "動画"
  };

  const elements = {
    stage: document.getElementById("stage"),
    base: document.getElementById("wallpaperBase"),
    image: document.getElementById("wallpaperImage"),
    video: document.getElementById("wallpaperVideo"),
    widgetLayer: document.getElementById("widgetLayer"),
    clock: document.getElementById("clock"),
    searchForm: document.getElementById("searchForm"),
    searchInput: document.getElementById("searchInput"),
    quickLinks: document.getElementById("quickLinks"),
    settingsButton: document.getElementById("settingsButton"),
    authActions: document.getElementById("authActions"),
    likeButton: document.getElementById("likeButton"),
    favoriteButton: document.getElementById("favoriteButton"),
    downloadButton: document.getElementById("downloadButton"),
    panel: document.getElementById("settingsPanel"),
    closeSettingsButton: document.getElementById("closeSettingsButton"),
    sourceCards: Array.from(document.querySelectorAll(".source-card")),
    collectionPicker: document.getElementById("collectionPicker"),
    collectionsList: document.getElementById("collectionsList"),
    reloadCollectionsButton: document.getElementById("reloadCollectionsButton"),
    reloadSourceButton: document.getElementById("reloadSourceButton"),
    wallpaperList: document.getElementById("wallpaperList"),
    randomToggle: document.getElementById("randomToggle"),
    randomIntervalSelect: document.getElementById("randomIntervalSelect"),
    languageSelect: document.getElementById("languageSelect"),
    clockToggle: document.getElementById("clockToggle"),
    searchToggle: document.getElementById("searchToggle"),
    quickLinksToggle: document.getElementById("quickLinksToggle"),
    quickLinkModal: document.getElementById("quickLinkModal"),
    closeQuickLinkButton: document.getElementById("closeQuickLinkButton"),
    quickLinkForm: document.getElementById("quickLinkForm"),
    quickLinkNameInput: document.getElementById("quickLinkNameInput"),
    quickLinkUrlInput: document.getElementById("quickLinkUrlInput"),
    addQuickLinkButton: document.getElementById("addQuickLinkButton"),
    quickLinkStatusLine: document.getElementById("quickLinkStatusLine"),
    accountPrompt: document.getElementById("accountPrompt"),
    openAuthButton: document.getElementById("openAuthButton"),
    accountCard: document.getElementById("accountCard"),
    accountAvatar: document.getElementById("accountAvatar"),
    accountName: document.getElementById("accountName"),
    accountCoins: document.getElementById("accountCoins"),
    signOutButton: document.getElementById("signOutButton"),
    versionText: document.getElementById("versionText"),
    statusLine: document.getElementById("statusLine"),
    authModal: document.getElementById("authModal"),
    closeAuthButton: document.getElementById("closeAuthButton"),
    authForm: document.getElementById("authForm"),
    authTabs: Array.from(document.querySelectorAll(".auth-tab")),
    usernameLabel: document.getElementById("usernameLabel"),
    usernameInput: document.getElementById("usernameInput"),
    emailInput: document.getElementById("emailInput"),
    passwordInput: document.getElementById("passwordInput"),
    authSubmitButton: document.getElementById("authSubmitButton"),
    authStatusLine: document.getElementById("authStatusLine")
  };

  const state = {
    settings: { ...DEFAULT_SETTINGS },
    items: [],
    collections: [],
    current: null,
    sourceLabel: "",
    loadingToken: 0,
    randomTimer: null,
    authMode: "login",
    sessionId: ""
  };

  document.addEventListener("DOMContentLoaded", init);

  async function init() {
    state.settings = normalizeSettings(await getStored(SETTINGS_KEY));
    if (state.settings.language === "zh") {
      state.settings.language = "zh-CN";
    }
    if (!isSignedIn() && state.settings.source !== "weekly") {
      state.settings.source = "weekly";
      state.settings.collectionId = null;
      state.settings.collectionTitle = "";
      state.settings.wallpaperId = null;
    }
    state.sessionId = await getSessionID();
    elements.versionText.textContent = extensionVersion;
    updateDeviceAspect();
    bindEvents();
    applyLocale();
    renderSettings();
    updateClock();
    setInterval(updateClock, 1000);
    track("chrome_newtab_open");
    await loadSource({ preferCached: true });
  }

  function bindEvents() {
    window.addEventListener("resize", updateDeviceAspect);
    elements.searchForm.addEventListener("submit", handleSearch);
    elements.settingsButton.addEventListener("click", () => {
      const open = !elements.panel.classList.contains("is-open");
      setPanelOpen(open);
      if (open) track("chrome_settings_open");
    });
    elements.closeSettingsButton.addEventListener("click", () => setPanelOpen(false));
    elements.likeButton.addEventListener("click", () => toggleEngagement("like"));
    elements.favoriteButton.addEventListener("click", () => toggleEngagement("favorite"));
    elements.downloadButton.addEventListener("click", downloadCurrentWallpaper);
    elements.reloadCollectionsButton.addEventListener("click", () => loadCollections({ force: true }));
    elements.reloadSourceButton.addEventListener("click", () => loadSource({ force: true }));
    elements.openAuthButton.addEventListener("click", () => openAuthModal("login"));
    elements.signOutButton.addEventListener("click", signOut);
    elements.closeAuthButton.addEventListener("click", closeAuthModal);
    elements.authForm.addEventListener("submit", handleAuthSubmit);

    elements.sourceCards.forEach((button) => {
      button.addEventListener("click", async () => {
        const source = button.dataset.source;
        if (!source || button.disabled || source === state.settings.source) return;
        state.settings.source = source;
        state.settings.wallpaperId = null;
        if (source !== "collection") {
          state.settings.collectionId = null;
          state.settings.collectionTitle = "";
        }
        await saveSettings();
        renderSettings();
        track("chrome_source_change", { source });
        await loadSource();
      });
    });

    elements.randomToggle.addEventListener("change", async () => {
      state.settings.randomEnabled = elements.randomToggle.checked;
      await saveSettings();
      scheduleRandomTimer();
      if (state.settings.randomEnabled) {
        shuffleWallpaper({ trackEvent: true });
      }
      renderSettings();
    });

    elements.randomIntervalSelect.addEventListener("change", async () => {
      state.settings.randomIntervalMinutes = Number(elements.randomIntervalSelect.value) || 0;
      await saveSettings();
      scheduleRandomTimer();
      track("chrome_random_interval_change", { minutes: state.settings.randomIntervalMinutes });
    });

    elements.languageSelect.addEventListener("change", async () => {
      state.settings.language = elements.languageSelect.value;
      await saveSettings();
      applyLocale();
      renderSettings();
      if (isSignedIn()) {
        await loadCollections({ force: true });
      }
      await loadSource({ force: true });
      track("chrome_language_change", { language: state.settings.language });
    });

    elements.clockToggle.addEventListener("change", () => updateWidgetSetting("showClock", elements.clockToggle.checked));
    elements.searchToggle.addEventListener("change", () => updateWidgetSetting("showSearch", elements.searchToggle.checked));
    elements.quickLinksToggle.addEventListener("change", () => updateWidgetSetting("showQuickLinks", elements.quickLinksToggle.checked));
    elements.quickLinkForm.addEventListener("submit", handleQuickLinkSubmit);
    elements.closeQuickLinkButton.addEventListener("click", closeQuickLinkModal);

    elements.authTabs.forEach((button) => {
      button.addEventListener("click", () => setAuthMode(button.dataset.mode || "login"));
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        if (!elements.quickLinkModal.hidden) closeQuickLinkModal();
        else if (!elements.authModal.hidden) closeAuthModal();
        else setPanelOpen(false);
      }
    });

    document.addEventListener("pointerdown", (event) => {
      if (!elements.panel.classList.contains("is-open") || !elements.authModal.hidden || !elements.quickLinkModal.hidden) return;
      const target = event.target;
      if (elements.panel.contains(target) || elements.settingsButton.contains(target)) return;
      setPanelOpen(false);
    });

    elements.quickLinkModal.addEventListener("pointerdown", (event) => {
      if (event.target === elements.quickLinkModal) closeQuickLinkModal();
    });

    elements.authModal.addEventListener("pointerdown", (event) => {
      if (event.target === elements.authModal) closeAuthModal();
    });
  }

  async function updateWidgetSetting(key, value) {
    state.settings[key] = value;
    await saveSettings();
    renderWidgets();
    track("chrome_widget_toggle", { key, value });
  }

  async function loadSource({ preferCached = false, force = false } = {}) {
    const token = ++state.loadingToken;
    setStatus(t("loading"));
    renderWallpaperList({ loading: true });
    elements.stage.classList.add("is-loading");

    const cacheKey = sourceCacheKey();
    if (preferCached) {
      const cache = await getStored(CACHE_KEY);
      const cached = cache && cache[cacheKey];
      if (cached && Array.isArray(cached.items) && cached.items.length > 0) {
        setItems(cached.items, { label: cached.label, fromCache: true });
      }
    }

    try {
      const loaded = await fetchItemsForCurrentSource({ force });
      if (token !== state.loadingToken) return;
      if (!loaded.items.length) throw new Error(t("noWallpapers"));
      setItems(loaded.items, { label: loaded.label });
      const cache = (await getStored(CACHE_KEY)) || {};
      cache[sourceCacheKey()] = {
        label: loaded.label,
        items: loaded.items,
        savedAt: Date.now()
      };
      await setStored(CACHE_KEY, cache);
      setStatus("");
    } catch (error) {
      if (token !== state.loadingToken) return;
      const cache = await getStored(CACHE_KEY);
      const cached = cache && cache[cacheKey];
      if (cached && Array.isArray(cached.items) && cached.items.length > 0) {
        setItems(cached.items, { label: cached.label || sourceName(), fromCache: true });
        setStatus(t("usingCache"));
      } else {
        state.items = [];
        renderWallpaperList();
        setStatus(error.message || t("noWallpapers"));
        elements.stage.classList.remove("is-loading");
      }
    }
  }

  async function fetchItemsForCurrentSource() {
    if (!isSignedIn() && state.settings.source !== "weekly") {
      state.settings.source = "weekly";
      await saveSettings();
      renderSettings();
    }

    if (state.settings.source === "favorites") {
      requireSignIn();
      const page = await apiFetch("/users/me/favorites?limit=80");
      return { label: t("sourceFavorites"), items: normalizeItems(page) };
    }

    if (state.settings.source === "collection") {
      requireSignIn();
      await loadCollections();
      if (!state.settings.collectionId) throw new Error(t("chooseCollection"));
      const page = await apiFetch(`/collections/${state.settings.collectionId}/wallpapers?limit=80`);
      return {
        label: state.settings.collectionTitle || t("sourceCollection"),
        items: normalizeItems(page)
      };
    }

    const weekly = await apiFetch("/weekly-picks/current");
    const week = weekly && weekly.week ? ` W${weekly.week}` : "";
    return {
      label: `${t("sourceWeekly")}${week}`,
      items: Array.isArray(weekly && weekly.picks) ? weekly.picks : []
    };
  }

  function setItems(items, options = {}) {
    state.items = items.filter((item) => item && item.id && getBestImage(item));
    state.sourceLabel = options.label || sourceName();

    if (!state.items.length) {
      renderWallpaperList();
      setStatus(t("noWallpapers"));
      elements.stage.classList.remove("is-loading");
      return;
    }

    let index = 0;
    if (state.settings.randomEnabled) {
      index = randomIndex();
    } else if (state.settings.wallpaperId) {
      const found = state.items.findIndex((item) => item.id === state.settings.wallpaperId);
      index = found >= 0 ? found : 0;
    }
    showWallpaperAt(index, { persistSelection: !state.settings.randomEnabled, trackView: true });
    renderWallpaperList();
    scheduleRandomTimer();
  }

  function showWallpaperAt(index, options = {}) {
    if (!state.items.length) return;
    const safeIndex = wrap(index, state.items.length);
    state.current = state.items[safeIndex];
    if (options.persistSelection) {
      state.settings.wallpaperId = state.current.id;
      saveSettings();
    }
    paintWallpaper(state.current);
    renderWallpaperList();
    renderActionButtons();
    if (options.trackView) {
      track("chrome_wallpaper_view", {
        wallpaper_id: state.current.id,
        source: state.settings.source,
        collection_id: state.settings.collectionId || null
      });
    }
  }

  function shuffleWallpaper(options = {}) {
    if (state.items.length <= 1) return;
    let next = randomIndex();
    if (state.current) {
      while (state.items[next] && state.items[next].id === state.current.id) {
        next = randomIndex();
      }
    }
    showWallpaperAt(next, { trackView: true });
    if (options.trackEvent) {
      track("chrome_random_shuffle", { source: state.settings.source });
    }
  }

  function paintWallpaper(wallpaper) {
    const videoSrc = getVideoSource(wallpaper);
    const highSrc = getBestStillImage(wallpaper);
    const softSrc = wallpaper.thumb_url || wallpaper.preview_url || highSrc;
    const color = sanitizeColor(wallpaper.dominant_color) || "#101316";

    elements.base.style.backgroundColor = color;
    elements.stage.classList.add("is-loading");
    elements.video.pause();
    elements.video.classList.remove("is-ready");
    elements.video.onloadeddata = null;
    elements.video.onerror = null;

    if (softSrc && elements.image.src !== softSrc) {
      elements.image.classList.remove("is-ready");
      elements.image.classList.add("is-soft");
      elements.image.src = softSrc;
      requestAnimationFrame(() => elements.image.classList.add("is-ready"));
    }

    if (videoSrc) {
      if (elements.video.currentSrc !== videoSrc && elements.video.src !== videoSrc) {
        elements.video.src = videoSrc;
        elements.video.load();
      }

      const showVideo = () => {
        if (state.current !== wallpaper) return;
        elements.stage.classList.remove("is-loading");
        elements.video.classList.add("is-ready");
        elements.video.play().catch(() => {
          if (state.current !== wallpaper) return;
          elements.video.classList.remove("is-ready");
          elements.stage.classList.remove("is-loading");
        });
      };

      elements.video.onloadeddata = showVideo;
      elements.video.onerror = () => {
        if (state.current !== wallpaper) return;
        elements.image.classList.remove("is-soft");
        elements.image.classList.add("is-ready");
        elements.stage.classList.remove("is-loading");
      };

      if (elements.video.readyState >= 2) {
        showVideo();
      } else {
        elements.video.play().catch(() => {
          // Chrome may wait for enough media data; onloadeddata handles it.
        });
      }
      return;
    }

    elements.video.removeAttribute("src");
    elements.video.load();

    if (!highSrc) {
      elements.stage.classList.remove("is-loading");
      return;
    }

    const loader = new Image();
    loader.decoding = "async";
    loader.onload = () => {
      if (state.current !== wallpaper) return;
      elements.image.src = highSrc;
      elements.image.classList.remove("is-soft");
      elements.image.classList.add("is-ready");
      elements.stage.classList.remove("is-loading");
    };
    loader.onerror = () => {
      if (state.current !== wallpaper) return;
      elements.image.classList.remove("is-soft");
      elements.image.classList.add("is-ready");
      elements.stage.classList.remove("is-loading");
      setStatus(t("highQualityFailed"));
    };
    loader.src = highSrc;
  }

  async function loadCollections({ force = false } = {}) {
    if (!isSignedIn()) {
      state.collections = [];
      renderCollections();
      return;
    }
    if (!force && state.collections.length) {
      ensureSelectedCollection();
      renderCollections();
      return;
    }
    setStatus(t("loadingCollections"));
    try {
      const collections = await apiFetch("/users/me/collections?limit=80");
      state.collections = Array.isArray(collections) ? collections : [];
      ensureSelectedCollection();
      renderCollections();
      setStatus("");
    } catch (error) {
      state.collections = [];
      renderCollections();
      setStatus(error.message || t("noCollections"));
    }
  }

  function ensureSelectedCollection() {
    if (!state.collections.length) {
      state.settings.collectionId = null;
      state.settings.collectionTitle = "";
      return;
    }
    const selected = state.collections.find((item) => item.id === state.settings.collectionId);
    if (selected) {
      state.settings.collectionTitle = localizedCollectionTitle(selected);
      return;
    }
    const first = state.collections[0];
    state.settings.collectionId = first.id;
    state.settings.collectionTitle = localizedCollectionTitle(first);
    saveSettings();
  }

  function renderSettings() {
    const signedIn = isSignedIn();
    elements.sourceCards.forEach((button) => {
      const source = button.dataset.source;
      const needsAuth = source === "favorites" || source === "collection";
      const active = source === state.settings.source;
      button.disabled = needsAuth && !signedIn;
      button.setAttribute("aria-checked", active ? "true" : "false");
      button.setAttribute("aria-disabled", button.disabled ? "true" : "false");
    });

    elements.collectionPicker.hidden = state.settings.source !== "collection" || !signedIn;
    elements.randomToggle.checked = Boolean(state.settings.randomEnabled);
    elements.randomIntervalSelect.value = String(state.settings.randomIntervalMinutes);
    elements.languageSelect.value = state.settings.language || "auto";
    elements.clockToggle.checked = Boolean(state.settings.showClock);
    elements.searchToggle.checked = Boolean(state.settings.showSearch);
    elements.quickLinksToggle.checked = Boolean(state.settings.showQuickLinks);
    renderWidgets();
    renderAccount();
    renderActionButtons();
    renderCollections();
  }

  function renderWidgets() {
    elements.clock.hidden = !state.settings.showClock;
    elements.searchForm.hidden = !state.settings.showSearch;
    renderQuickLinks();
    elements.widgetLayer.classList.toggle(
      "is-empty",
      !state.settings.showClock && !state.settings.showSearch && !state.settings.showQuickLinks
    );
  }

  function renderQuickLinks() {
    elements.quickLinks.hidden = !state.settings.showQuickLinks;
    elements.quickLinks.replaceChildren();
    if (!state.settings.showQuickLinks) return;

    state.settings.quickLinks.forEach((link) => {
      const tile = document.createElement("div");
      tile.className = "quick-link-tile";
      tile.setAttribute("role", "button");
      tile.setAttribute("aria-label", link.title);
      tile.tabIndex = 0;
      tile.title = link.title;

      const icon = document.createElement("span");
      icon.className = "quick-link-icon";
      const favicon = document.createElement("img");
      favicon.src = faviconURL(link.url);
      favicon.alt = "";
      favicon.loading = "lazy";
      favicon.decoding = "async";
      favicon.onerror = () => favicon.remove();
      icon.textContent = initialsFor(link.title || link.url);
      icon.appendChild(favicon);

      const label = document.createElement("span");
      label.className = "quick-link-label";
      label.textContent = link.title;

      tile.append(icon, label);
      const openLink = () => {
        track("chrome_quick_link_open", { url_host: hostFor(link.url) });
        window.location.href = link.url;
      };
      tile.addEventListener("click", openLink);
      tile.addEventListener("keydown", (event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        openLink();
      });

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "quick-link-delete";
      remove.textContent = "x";
      remove.setAttribute("aria-label", `${t("deleteQuickLink")} ${link.title}`);
      remove.title = t("deleteQuickLink");
      remove.addEventListener("click", (event) => {
        event.stopPropagation();
        removeQuickLink(link.id);
      });
      remove.addEventListener("keydown", (event) => {
        event.stopPropagation();
      });
      tile.appendChild(remove);
      elements.quickLinks.appendChild(tile);
    });

    if (state.settings.quickLinks.length < MAX_QUICK_LINKS) {
      const addTile = document.createElement("div");
      addTile.className = "quick-link-tile quick-link-add";
      addTile.setAttribute("role", "button");
      addTile.setAttribute("aria-label", t("addShortcut"));
      addTile.tabIndex = 0;
      addTile.title = t("addShortcut");
      const icon = document.createElement("span");
      icon.className = "quick-link-icon";
      icon.textContent = "+";
      const label = document.createElement("span");
      label.className = "quick-link-label";
      label.textContent = t("addShortcut");
      addTile.append(icon, label);
      const openAdd = () => {
        openQuickLinkModal();
        track("chrome_quick_link_add_open");
      };
      addTile.addEventListener("click", openAdd);
      addTile.addEventListener("keydown", (event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        event.preventDefault();
        openAdd();
      });
      elements.quickLinks.appendChild(addTile);
    }
  }

  function renderAccount() {
    const user = state.settings.user;
    const signedIn = isSignedIn();
    elements.accountPrompt.hidden = signedIn;
    elements.accountCard.hidden = !signedIn;
    if (!signedIn || !user) return;

    const name = user.nickname || user.username || "Wallpaper Exchange";
    elements.accountName.textContent = name;
    elements.accountCoins.textContent = formatTemplate(t("coins"), { count: user.coins || 0 });
    elements.accountAvatar.replaceChildren();
    if (user.avatar_url) {
      const img = document.createElement("img");
      img.src = user.avatar_url;
      img.alt = "";
      img.decoding = "async";
      elements.accountAvatar.appendChild(img);
    } else {
      elements.accountAvatar.textContent = name.charAt(0).toUpperCase();
    }
  }

  function renderActionButtons() {
    const signedIn = isSignedIn();
    elements.authActions.hidden = !signedIn;
    if (!signedIn) return;

    const wallpaper = state.current || {};
    setDockButton(elements.likeButton, wallpaper.is_liked ? t("liked") : t("like"), wallpaper.is_liked ? "♥" : "♡");
    setDockButton(elements.favoriteButton, wallpaper.is_favorited ? t("favorited") : t("favorite"), wallpaper.is_favorited ? "★" : "☆");
    setDockButton(elements.downloadButton, wallpaper.is_downloaded ? t("downloaded") : t("download"), "⇩");
    elements.likeButton.classList.toggle("is-active", Boolean(wallpaper.is_liked));
    elements.likeButton.classList.toggle("is-liked", Boolean(wallpaper.is_liked));
    elements.favoriteButton.classList.toggle("is-active", Boolean(wallpaper.is_favorited));
    elements.favoriteButton.classList.toggle("is-favorited", Boolean(wallpaper.is_favorited));
    elements.downloadButton.classList.toggle("is-active", Boolean(wallpaper.is_downloaded));
    elements.downloadButton.classList.toggle("is-downloaded", Boolean(wallpaper.is_downloaded));
  }

  function renderCollections() {
    elements.collectionsList.replaceChildren();
    if (state.settings.source !== "collection" || !isSignedIn()) return;
    if (!state.collections.length) {
      elements.collectionsList.appendChild(emptyNode(t("noCollections")));
      return;
    }

    state.collections.forEach((collection) => {
      const collectionTitle = localizedCollectionTitle(collection);
      const button = document.createElement("button");
      button.type = "button";
      button.className = `collection-item${collection.id === state.settings.collectionId ? " is-selected" : ""}`;
      const title = document.createElement("span");
      title.className = "item-title";
      title.textContent = collectionTitle;
      const meta = document.createElement("span");
      meta.className = "item-meta";
      meta.textContent = formatTemplate(t("collectionCount"), { count: collection.wallpaper_count || 0 });
      button.append(title, meta);
      button.addEventListener("click", async () => {
        state.settings.collectionId = collection.id;
        state.settings.collectionTitle = collectionTitle;
        state.settings.wallpaperId = null;
        await saveSettings();
        renderCollections();
        track("chrome_collection_select", { collection_id: collection.id });
        await loadSource();
      });
      elements.collectionsList.appendChild(button);
    });
  }

  function renderWallpaperList(options = {}) {
    elements.wallpaperList.replaceChildren();
    if (options.loading) {
      elements.wallpaperList.appendChild(emptyNode(t("loading")));
      return;
    }
    if (!state.items.length) {
      elements.wallpaperList.appendChild(emptyNode(t("noWallpapers")));
      return;
    }

    state.items.forEach((item, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `wallpaper-item${state.current && item.id === state.current.id ? " is-selected" : ""}`;
      button.setAttribute("aria-label", item.title || "Wallpaper");
      const thumb = document.createElement("div");
      thumb.className = "wallpaper-thumb";
      const img = document.createElement("img");
      img.loading = "lazy";
      img.decoding = "async";
      img.src = item.thumb_url || item.preview_url || getBestStillImage(item) || getVideoSource(item);
      img.alt = "";
      thumb.appendChild(img);

      const chips = wallpaperChipStrip(item);
      button.append(thumb, chips);
      button.addEventListener("click", async () => {
        state.settings.randomEnabled = false;
        state.settings.wallpaperId = item.id;
        await saveSettings();
        renderSettings();
        scheduleRandomTimer();
        showWallpaperAt(index, { persistSelection: true, trackView: true });
        track("chrome_wallpaper_select", { wallpaper_id: item.id, source: state.settings.source });
      });
      elements.wallpaperList.appendChild(button);
    });
  }

  function wallpaperChipStrip(wallpaper) {
    const strip = document.createElement("div");
    strip.className = "wallpaper-chip-strip";

    const resolution = resolutionLabel(wallpaper);
    if (resolution) {
      strip.appendChild(wallpaperChip(resolution));
    }
    if (isLiveWallpaper(wallpaper)) {
      strip.appendChild(wallpaperChip(t("live"), "is-live"));
    }
    return strip;
  }

  function wallpaperChip(label, tone = "") {
    const chip = document.createElement("span");
    chip.className = `wallpaper-chip${tone ? ` ${tone}` : ""}`;
    chip.textContent = label;
    return chip;
  }

  function emptyNode(text) {
    const div = document.createElement("div");
    div.className = "empty-state";
    div.textContent = text;
    return div;
  }

  async function handleQuickLinkSubmit(event) {
    event.preventDefault();
    const url = normalizeURL(elements.quickLinkUrlInput.value);
    if (!url) {
      elements.quickLinkStatusLine.textContent = t("quickLinkInvalid");
      elements.quickLinkUrlInput.focus();
      return;
    }

    const existingIndex = state.settings.quickLinks.findIndex((link) => link.url === url);
    if (existingIndex < 0 && state.settings.quickLinks.length >= MAX_QUICK_LINKS) {
      elements.quickLinkStatusLine.textContent = formatTemplate(t("quickLinkLimit"), { count: MAX_QUICK_LINKS });
      return;
    }

    const fallbackTitle = displayURL(url);
    const title = (elements.quickLinkNameInput.value.trim() || fallbackTitle).slice(0, 28);
    const nextLink = {
      id: existingIndex >= 0 ? state.settings.quickLinks[existingIndex].id : newID(),
      title,
      url
    };

    if (existingIndex >= 0) {
      state.settings.quickLinks.splice(existingIndex, 1, nextLink);
    } else {
      state.settings.quickLinks.push(nextLink);
    }

    await saveSettings();
    elements.quickLinkForm.reset();
    renderQuickLinks();
    closeQuickLinkModal();
    setStatus("");
    track(existingIndex >= 0 ? "chrome_quick_link_update" : "chrome_quick_link_add", { url_host: hostFor(url) });
  }

  async function removeQuickLink(id) {
    const link = state.settings.quickLinks.find((item) => item.id === id);
    state.settings.quickLinks = state.settings.quickLinks.filter((item) => item.id !== id);
    await saveSettings();
    renderQuickLinks();
    track("chrome_quick_link_remove", { url_host: link ? hostFor(link.url) : "" });
  }

  async function toggleEngagement(type) {
    if (!state.current) return;
    if (!isSignedIn()) {
      openAuthModal("login");
      setStatus(t("authRequired"));
      return;
    }

    const isLike = type === "like";
    const key = isLike ? "is_liked" : "is_favorited";
    const button = isLike ? elements.likeButton : elements.favoriteButton;
    const active = Boolean(state.current[key]);
    button.disabled = true;
    try {
      await apiFetch(`/wallpapers/${state.current.id}/${isLike ? "like" : "favorite"}`, {
        method: active ? "DELETE" : "POST"
      });
      state.current[key] = !active;
      const existing = state.items.find((item) => item.id === state.current.id);
      if (existing) existing[key] = state.current[key];
      renderActionButtons();
      track(isLike ? "chrome_wallpaper_like" : "chrome_wallpaper_favorite", {
        wallpaper_id: state.current.id,
        active: state.current[key]
      });
    } catch (error) {
      setStatus(error.message || t("actionFailed"));
    } finally {
      button.disabled = false;
    }
  }

  async function downloadCurrentWallpaper() {
    if (!state.current) return;
    if (!isSignedIn()) {
      openAuthModal("login");
      setStatus(t("authRequired"));
      return;
    }

    elements.downloadButton.disabled = true;
    try {
      const response = await fetch(`${API_BASE}/wallpapers/${state.current.id}/download`, {
        headers: {
          Authorization: `Bearer ${state.settings.token}`,
          "Accept-Language": currentLocale()
        },
        credentials: "omit"
      });
      if (response.status === 402) {
        setStatus(t("insufficientCoins"));
        return;
      }
      if (!response.ok) {
        setStatus(t("downloadFailed"));
        return;
      }

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `wallpaper_${state.current.id}.${extensionFor(state.current)}`;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);

      state.current.is_downloaded = true;
      const existing = state.items.find((item) => item.id === state.current.id);
      if (existing) existing.is_downloaded = true;
      renderActionButtons();
      await refreshCoins();
      setStatus(t("downloadDone"));
      track("chrome_wallpaper_download", { wallpaper_id: state.current.id });
    } catch (_error) {
      setStatus(t("downloadFailed"));
    } finally {
      elements.downloadButton.disabled = false;
    }
  }

  async function refreshCoins() {
    if (!isSignedIn()) return;
    try {
      const data = await apiFetch("/users/me/coins");
      state.settings.user = { ...state.settings.user, coins: data.coins || 0 };
      await saveSettings();
      renderAccount();
    } catch (_error) {
      // Coin refresh is helpful, not required for the action to succeed.
    }
  }

  function openAuthModal(mode) {
    setAuthMode(mode || "login");
    elements.authModal.hidden = false;
    elements.authStatusLine.textContent = "";
    setTimeout(() => {
      if (state.authMode === "register") elements.usernameInput.focus();
      else elements.emailInput.focus();
    }, 0);
    track("chrome_auth_modal_open", { mode: state.authMode });
  }

  function closeAuthModal() {
    elements.authModal.hidden = true;
    elements.authForm.reset();
    elements.authStatusLine.textContent = "";
  }

  function openQuickLinkModal() {
    if (state.settings.quickLinks.length >= MAX_QUICK_LINKS) {
      setStatus(formatTemplate(t("quickLinkLimit"), { count: MAX_QUICK_LINKS }));
      return;
    }
    setPanelOpen(false);
    elements.quickLinkModal.hidden = false;
    elements.quickLinkStatusLine.textContent = "";
    requestAnimationFrame(() => elements.quickLinkUrlInput.focus());
  }

  function closeQuickLinkModal() {
    elements.quickLinkModal.hidden = true;
    elements.quickLinkForm.reset();
    elements.quickLinkStatusLine.textContent = "";
  }

  function setAuthMode(mode) {
    state.authMode = mode === "register" ? "register" : "login";
    elements.authTabs.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.mode === state.authMode);
    });
    elements.usernameLabel.hidden = state.authMode !== "register";
    elements.authSubmitButton.textContent = state.authMode === "register" ? t("register") : t("login");
  }

  async function handleAuthSubmit(event) {
    event.preventDefault();
    const email = elements.emailInput.value.trim();
    const password = elements.passwordInput.value;
    const username = elements.usernameInput.value.trim();

    if (!email || !password) {
      elements.authStatusLine.textContent = t("emailPasswordRequired");
      return;
    }
    if (state.authMode === "register" && !username) {
      elements.authStatusLine.textContent = t("usernameRequired");
      return;
    }

    elements.authSubmitButton.disabled = true;
    elements.authStatusLine.textContent = state.authMode === "register" ? t("creatingAccount") : t("signingIn");
    try {
      const body = state.authMode === "register"
        ? { username, email, password }
        : { email, password };
      const data = await apiFetch(state.authMode === "register" ? "/auth/register" : "/auth/login", {
        method: "POST",
        body,
        skipAuth: true
      });
      state.settings.token = data.token || "";
      state.settings.user = data.user || null;
      await saveSettings();
      closeAuthModal();
      renderSettings();
      await loadCollections({ force: true });
      await loadSource();
      setStatus(t("signedIn"));
      track(state.authMode === "register" ? "chrome_register_success" : "chrome_login_success");
    } catch (error) {
      elements.authStatusLine.textContent = error.message || t("authFailed");
    } finally {
      elements.authSubmitButton.disabled = false;
    }
  }

  async function signOut() {
    state.settings.token = "";
    state.settings.user = null;
    state.settings.collectionId = null;
    state.settings.collectionTitle = "";
    state.settings.wallpaperId = null;
    state.settings.source = "weekly";
    state.collections = [];
    await saveSettings();
    renderSettings();
    await loadSource();
    setStatus(t("signedOut"));
    track("chrome_logout");
  }

  function handleSearch(event) {
    event.preventDefault();
    const query = elements.searchInput.value.trim();
    if (!query) return;
    track("chrome_search", { has_query: true });

    const hasProtocol = /^[a-z][a-z0-9+.-]*:\/\//i.test(query);
    const looksLikeDomain = /^[^\s]+\.[^\s]{2,}$/.test(query);
    if (hasProtocol) {
      window.location.href = query;
      return;
    }
    if (looksLikeDomain) {
      window.location.href = `https://${query}`;
      return;
    }
    window.location.href = `https://www.google.com/search?q=${encodeURIComponent(query)}`;
  }

  function setPanelOpen(open) {
    elements.panel.classList.toggle("is-open", open);
    elements.panel.setAttribute("aria-hidden", open ? "false" : "true");
    elements.settingsButton.setAttribute("aria-expanded", open ? "true" : "false");
  }

  function scheduleRandomTimer() {
    if (state.randomTimer) {
      clearInterval(state.randomTimer);
      state.randomTimer = null;
    }
    if (!state.settings.randomEnabled || !state.settings.randomIntervalMinutes) return;
    state.randomTimer = setInterval(() => {
      shuffleWallpaper({ trackEvent: true });
    }, state.settings.randomIntervalMinutes * 60 * 1000);
  }

  function applyLocale() {
    const locale = currentLocale();
    document.documentElement.lang = locale;
    document.title = t("title");
    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const key = node.getAttribute("data-i18n");
      if (key) node.textContent = t(key);
    });
    setDockButton(elements.settingsButton, t("settings"), "⚙");
    elements.searchInput.placeholder = t("searchPlaceholder");
    elements.quickLinks.setAttribute("aria-label", t("quickLinksTitle"));
    elements.quickLinkNameInput.placeholder = t("quickLinkNamePlaceholder");
    elements.quickLinkUrlInput.placeholder = t("quickLinkUrlPlaceholder");
    setAuthMode(state.authMode);
    renderQuickLinks();
    renderActionButtons();
  }

  function updateClock() {
    const now = new Date();
    elements.clock.textContent = now.toLocaleTimeString(undefined, {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    });
    elements.clock.dateTime = now.toISOString();
  }

  function sourceName() {
    if (state.settings.source === "favorites") return t("sourceFavorites");
    if (state.settings.source === "collection") return state.settings.collectionTitle || t("sourceCollection");
    return t("sourceWeekly");
  }

  function sourceCacheKey() {
    return `${state.settings.source}:${state.settings.collectionId || "all"}`;
  }

  function updateDeviceAspect() {
    const width = (window.screen && window.screen.width) || window.innerWidth || 16;
    const height = (window.screen && window.screen.height) || window.innerHeight || 9;
    document.documentElement.style.setProperty("--device-aspect", `${Math.max(1, width)} / ${Math.max(1, height)}`);
  }

  function normalizeItems(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function normalizeSettings(stored) {
    const settings = { ...DEFAULT_SETTINGS, ...(stored || {}) };
    settings.showQuickLinks = settings.showQuickLinks !== false;
    settings.quickLinks = sanitizeQuickLinks(settings.quickLinks);
    return settings;
  }

  function sanitizeQuickLinks(value) {
    if (!Array.isArray(value)) return [];
    const seen = new Set();
    const links = [];
    value.forEach((item) => {
      const url = normalizeURL(item && item.url);
      if (!url || seen.has(url) || links.length >= MAX_QUICK_LINKS) return;
      seen.add(url);
      const title = String((item && item.title) || displayURL(url)).trim().slice(0, 28) || displayURL(url);
      links.push({
        id: String((item && item.id) || newID()),
        title,
        url
      });
    });
    return links;
  }

  function requireSignIn() {
    if (!isSignedIn()) {
      openAuthModal("login");
      throw new Error(t("signInToUse"));
    }
  }

  function isSignedIn() {
    return Boolean(state.settings.token && state.settings.user);
  }

  function getBestImage(wallpaper) {
    return getBestStillImage(wallpaper) || getVideoSource(wallpaper);
  }

  function getBestStillImage(wallpaper) {
    if (!wallpaper) return "";
    if (getVideoSource(wallpaper)) {
      return wallpaper.preview_url || wallpaper.thumb_url || "";
    }
    return wallpaper.original_url || wallpaper.preview_url || wallpaper.thumb_url || "";
  }

  function getVideoSource(wallpaper) {
    if (!wallpaper) return "";
    const preview = String(wallpaper.preview_video_url || "").trim();
    if (preview) return preview;
    const original = String(wallpaper.original_url || "").trim();
    const fileType = String(wallpaper.file_type || "").toLowerCase();
    if (original && fileType.startsWith("video/")) return original;
    if (/\.(mp4|webm|mov)(?:$|\?)/i.test(original)) return original;
    return "";
  }

  function isLiveWallpaper(wallpaper) {
    return Boolean(getVideoSource(wallpaper) || (wallpaper && wallpaper.is_dynamic));
  }

  function resolutionLabel(wallpaper) {
    if (!wallpaper) return "";
    const px = Math.max(Number(wallpaper.width) || 0, Number(wallpaper.height) || 0);
    if (px >= 7680) return "8K";
    if (px >= 3840) return "4K";
    if (px >= 2560) return "2K";
    if (px >= 1920) return "1080P";
    if (px >= 1280) return "720P";
    return "";
  }

  function localizedCollectionTitle(collection) {
    if (!collection) return t("sourceCollection");
    const i18nTitle = pickLocalizedValue(collection.title_i18n || collection.titleI18n);
    return i18nTitle || collection.title || t("sourceCollection");
  }

  function pickLocalizedValue(value) {
    if (!value) return "";
    let dict = value;
    if (typeof value === "string") {
      try {
        dict = JSON.parse(value);
      } catch (_error) {
        return "";
      }
    }
    if (!dict || typeof dict !== "object") return "";
    const locale = currentLocale();
    return dict[locale] || dict[locale.toLowerCase()] || dict.en || dict["zh-CN"] || "";
  }

  function formatWallpaperDetails(wallpaper) {
    const parts = [];
    if (wallpaper.width && wallpaper.height) parts.push(`${wallpaper.width} x ${wallpaper.height}`);
    if (wallpaper.file_size) parts.push(formatBytes(wallpaper.file_size));
    if (wallpaper.preview_video_url || String(wallpaper.file_type || "").startsWith("video/")) parts.push(t("video"));
    else if (wallpaper.is_dynamic) parts.push(t("dynamic"));
    return parts.filter(Boolean).join("  ");
  }

  function formatBytes(value) {
    const bytes = Number(value) || 0;
    if (bytes <= 0) return "";
    const units = ["B", "KB", "MB", "GB"];
    let size = bytes;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return `${size >= 10 || unit === 0 ? Math.round(size) : size.toFixed(1)} ${units[unit]}`;
  }

  function normalizeURL(value) {
    const raw = String(value || "").trim();
    if (!raw) return "";
    const withProtocol = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `https://${raw}`;
    try {
      const url = new URL(withProtocol);
      if (url.protocol !== "http:" && url.protocol !== "https:") return "";
      if (!url.hostname || !url.hostname.includes(".")) return "";
      url.hash = "";
      return url.href;
    } catch (_error) {
      return "";
    }
  }

  function displayURL(value) {
    try {
      const url = new URL(value);
      return url.hostname.replace(/^www\./i, "");
    } catch (_error) {
      return String(value || "");
    }
  }

  function hostFor(value) {
    try {
      return new URL(value).hostname;
    } catch (_error) {
      return "";
    }
  }

  function faviconURL(value) {
    return `https://www.google.com/s2/favicons?domain_url=${encodeURIComponent(value)}&sz=64`;
  }

  function initialsFor(value) {
    const text = String(value || "").trim();
    if (!text) return "+";
    const first = Array.from(text.replace(/^https?:\/\//i, "").replace(/^www\./i, ""))[0];
    return (first || "+").toUpperCase();
  }

  function extensionFor(wallpaper) {
    const fromURL = String(wallpaper.original_url || wallpaper.preview_url || "").split("?")[0].split(".").pop();
    if (fromURL && fromURL.length <= 5) return fromURL;
    if (String(wallpaper.file_type || "").includes("png")) return "png";
    if (String(wallpaper.file_type || "").includes("webp")) return "webp";
    return "jpg";
  }

  function randomIndex() {
    return Math.floor(Math.random() * state.items.length);
  }

  function setStatus(message) {
    elements.statusLine.textContent = message || "";
  }

  async function apiFetch(path, options = {}) {
    const headers = {
      Accept: "application/json",
      "Accept-Language": currentLocale()
    };
    if (options.body) headers["Content-Type"] = "application/json";
    if (!options.skipAuth && state.settings.token) {
      headers.Authorization = `Bearer ${state.settings.token}`;
    }

    const response = await fetch(`${API_BASE}${path}`, {
      method: options.method || "GET",
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
      credentials: "omit"
    });

    let payload = null;
    try {
      payload = await response.json();
    } catch (_error) {
      payload = null;
    }

    if (!response.ok) {
      throw new Error((payload && payload.message) || `Request failed with ${response.status}`);
    }
    if (payload && typeof payload.code === "number" && payload.code !== 0) {
      throw new Error(payload.message || "Request failed.");
    }
    return payload ? payload.data : null;
  }

  function track(type, props) {
    if (!state.sessionId) return;
    const headers = {
      Accept: "application/json",
      "Content-Type": "application/json",
      "Accept-Language": currentLocale()
    };
    if (state.settings.token) {
      headers.Authorization = `Bearer ${state.settings.token}`;
    }
    fetch(`${API_BASE}/events`, {
      method: "POST",
      headers,
      credentials: "omit",
      body: JSON.stringify({
        session_id: state.sessionId,
        type,
        path: "chrome-extension://newtab",
        referrer: "",
        props: {
          client: "chrome_extension",
          version: extensionVersion,
          source: state.settings.source,
          ...(props || {})
        }
      })
    }).catch(() => {
      // Telemetry must never affect the new tab page.
    });
  }

  async function getSessionID() {
    const now = Date.now();
    const stored = await getStored(SESSION_KEY);
    const stamp = Number(await getStored(SESSION_STAMP_KEY) || 0);
    if (stored && stamp && now - stamp < SESSION_TTL_MS) {
      await setStored(SESSION_STAMP_KEY, now);
      return stored;
    }
    const fresh = newID();
    await setStored(SESSION_KEY, fresh);
    await setStored(SESSION_STAMP_KEY, now);
    return fresh;
  }

  function newID() {
    if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
    return `sid-${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
  }

  async function saveSettings() {
    await setStored(SETTINGS_KEY, state.settings);
  }

  function getStored(key) {
    return new Promise((resolve) => {
      const chromeStorage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
      if (chromeStorage) {
        chromeStorage.get(key, (result) => resolve(result[key] || null));
        return;
      }
      try {
        const value = window.localStorage.getItem(key);
        resolve(value ? JSON.parse(value) : null);
      } catch (_error) {
        resolve(null);
      }
    });
  }

  function setStored(key, value) {
    return new Promise((resolve) => {
      const chromeStorage = globalThis.chrome && globalThis.chrome.storage && globalThis.chrome.storage.local;
      if (chromeStorage) {
        chromeStorage.set({ [key]: value }, resolve);
        return;
      }
      try {
        window.localStorage.setItem(key, JSON.stringify(value));
      } catch (_error) {
        // Ignore storage failures; the tab remains usable for this session.
      }
      resolve();
    });
  }

  function currentLocale() {
    if (state.settings.language === "zh") return "zh-CN";
    if (["zh-CN", "zh-TW", "en", "ja"].includes(state.settings.language)) {
      return state.settings.language;
    }
    const browser = navigator.language || "";
    const lang = browser.toLowerCase();
    if (lang.startsWith("ja")) return "ja";
    if (lang.startsWith("zh")) {
      return lang.includes("tw") || lang.includes("hk") || lang.includes("mo") || lang.includes("hant")
        ? "zh-TW"
        : "zh-CN";
    }
    return "en";
  }

  function t(key) {
    const dict = COPY[currentLocale()] || COPY.en;
    return dict[key] || COPY.en[key] || key;
  }

  function formatTemplate(template, values) {
    return template.replace(/\{(\w+)\}/g, (_match, key) => String(values[key] ?? ""));
  }

  function setDockButton(button, label, icon) {
    button.textContent = icon;
    button.dataset.label = label;
    button.setAttribute("aria-label", label);
    button.title = label;
  }

  function wrap(value, length) {
    return ((value % length) + length) % length;
  }

  function sanitizeColor(value) {
    if (typeof value !== "string") return "";
    return /^#[0-9a-f]{6}$/i.test(value.trim()) ? value.trim() : "";
  }

  function getExtensionVersion() {
    const runtime = globalThis.chrome && globalThis.chrome.runtime;
    if (runtime && typeof runtime.getManifest === "function") {
      return runtime.getManifest().version || "0.1.0";
    }
    return "0.1.0";
  }
})();
