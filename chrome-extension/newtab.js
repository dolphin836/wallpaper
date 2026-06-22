(function () {
  const API_BASE = "https://wallpaperexchange.com/api/v1";
  const SITE_BASE = "https://wallpaperexchange.com";
  const SETTINGS_KEY = "wallpaperExchangeNewTabSettings";
  const CACHE_KEY = "wallpaperExchangeNewTabCache";

  const DEFAULT_SETTINGS = {
    source: "weekly",
    collectionId: null,
    collectionTitle: "",
    token: "",
    user: null,
    currentIndex: 0
  };

  const elements = {
    stage: document.getElementById("stage"),
    base: document.getElementById("wallpaperBase"),
    image: document.getElementById("wallpaperImage"),
    clock: document.getElementById("clock"),
    searchForm: document.getElementById("searchForm"),
    searchInput: document.getElementById("searchInput"),
    title: document.getElementById("wallpaperTitle"),
    details: document.getElementById("wallpaperDetails"),
    sourceLabel: document.getElementById("sourceLabel"),
    openLink: document.getElementById("openWallpaperLink"),
    previousButton: document.getElementById("previousButton"),
    nextButton: document.getElementById("nextButton"),
    refreshButton: document.getElementById("refreshButton"),
    settingsButton: document.getElementById("settingsButton"),
    panel: document.getElementById("settingsPanel"),
    closeSettingsButton: document.getElementById("closeSettingsButton"),
    sourceOptions: Array.from(document.querySelectorAll(".source-option")),
    loginForm: document.getElementById("loginForm"),
    loginFields: document.getElementById("loginFields"),
    signedInRow: document.getElementById("signedInRow"),
    signedInName: document.getElementById("signedInName"),
    signOutButton: document.getElementById("signOutButton"),
    collectionBlock: document.getElementById("collectionBlock"),
    collectionsList: document.getElementById("collectionsList"),
    reloadCollectionsButton: document.getElementById("reloadCollectionsButton"),
    thumbStrip: document.getElementById("thumbStrip"),
    statusLine: document.getElementById("statusLine")
  };

  const state = {
    settings: { ...DEFAULT_SETTINGS },
    items: [],
    collections: [],
    current: null,
    loadingToken: 0
  };

  document.addEventListener("DOMContentLoaded", init);

  async function init() {
    state.settings = { ...DEFAULT_SETTINGS, ...(await getStored(SETTINGS_KEY)) };
    renderAuthState();
    renderSourceOptions();
    bindEvents();
    updateClock();
    setInterval(updateClock, 1000 * 30);
    await loadSource({ preferCached: true });
  }

  function bindEvents() {
    elements.searchForm.addEventListener("submit", handleSearch);
    elements.previousButton.addEventListener("click", () => move(-1));
    elements.nextButton.addEventListener("click", () => move(1));
    elements.refreshButton.addEventListener("click", () => shuffleWallpaper());
    elements.settingsButton.addEventListener("click", () => setPanelOpen(!elements.panel.classList.contains("is-open")));
    elements.closeSettingsButton.addEventListener("click", () => setPanelOpen(false));
    elements.loginForm.addEventListener("submit", handleLogin);
    elements.signOutButton.addEventListener("click", handleSignOut);
    elements.reloadCollectionsButton.addEventListener("click", () => loadCollections({ force: true }));

    elements.sourceOptions.forEach((button) => {
      button.addEventListener("click", async () => {
        const source = button.dataset.source;
        if (!source || source === state.settings.source) return;
        state.settings.source = source;
        state.settings.currentIndex = 0;
        await saveSettings();
        renderSourceOptions();
        await loadSource();
      });
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") setPanelOpen(false);
      if (event.key === "ArrowRight" && !isTextFieldFocused()) move(1);
      if (event.key === "ArrowLeft" && !isTextFieldFocused()) move(-1);
    });

    document.addEventListener("pointerdown", (event) => {
      if (!elements.panel.classList.contains("is-open")) return;
      const target = event.target;
      if (elements.panel.contains(target) || elements.settingsButton.contains(target)) return;
      setPanelOpen(false);
    });
  }

  function isTextFieldFocused() {
    const active = document.activeElement;
    return active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement;
  }

  async function loadSource({ preferCached = false } = {}) {
    const token = ++state.loadingToken;
    setStatus("Loading wallpapers...");
    elements.stage.classList.add("is-loading");

    if (preferCached) {
      const cached = await getStored(CACHE_KEY);
      if (cached && cached.source === state.settings.source && Array.isArray(cached.items) && cached.items.length > 0) {
        setItems(cached.items, { fromCache: true });
      }
    }

    try {
      const loaded = await fetchItemsForSource();
      if (token !== state.loadingToken) return;
      if (!loaded.items.length) throw new Error("No wallpapers found for this source.");
      setItems(loaded.items, { label: loaded.label });
      await setStored(CACHE_KEY, {
        source: state.settings.source,
        label: loaded.label,
        items: loaded.items,
        savedAt: Date.now()
      });
      setStatus("");
    } catch (error) {
      if (token !== state.loadingToken) return;
      const cached = await getStored(CACHE_KEY);
      if (cached && Array.isArray(cached.items) && cached.items.length > 0) {
        setItems(cached.items, { label: cached.label || sourceName(), fromCache: true });
        setStatus("Using the last loaded wallpaper set.");
      } else {
        setStatus(error.message || "Unable to load wallpapers.");
        elements.stage.classList.remove("is-loading");
      }
    }
  }

  async function fetchItemsForSource() {
    if (state.settings.source === "favorites") {
      requireSignIn();
      const page = await apiFetch("/users/me/favorites?limit=80");
      return { label: "My Favorites", items: normalizeItems(page) };
    }

    if (state.settings.source === "collection") {
      requireSignIn();
      if (!state.settings.collectionId) {
        await loadCollections();
        throw new Error("Choose a collection first.");
      }
      const page = await apiFetch(`/collections/${state.settings.collectionId}/wallpapers?limit=80`);
      return {
        label: state.settings.collectionTitle || "My Collection",
        items: normalizeItems(page)
      };
    }

    const weekly = await apiFetch("/weekly-picks/current");
    const label = weekly && weekly.week ? `Weekly Picks W${weekly.week}` : "Weekly Picks";
    return { label, items: Array.isArray(weekly && weekly.picks) ? weekly.picks : [] };
  }

  function requireSignIn() {
    if (!state.settings.token) {
      setPanelOpen(true);
      throw new Error("Sign in to use this source.");
    }
  }

  function normalizeItems(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function setItems(items, options = {}) {
    state.items = items.filter((item) => item && item.id && getBestImage(item));
    if (!state.items.length) {
      setStatus("This source has no displayable wallpapers yet.");
      elements.stage.classList.remove("is-loading");
      return;
    }

    const maxIndex = state.items.length - 1;
    state.settings.currentIndex = clamp(Number(state.settings.currentIndex) || 0, 0, maxIndex);
    renderThumbStrip();
    showWallpaperAt(state.settings.currentIndex);
    elements.sourceLabel.textContent = options.label || sourceName();
  }

  function showWallpaperAt(index) {
    if (!state.items.length) return;
    state.settings.currentIndex = wrap(index, state.items.length);
    state.current = state.items[state.settings.currentIndex];
    saveSettings();
    renderThumbStrip();
    paintWallpaper(state.current);
  }

  function move(delta) {
    showWallpaperAt(state.settings.currentIndex + delta);
  }

  function shuffleWallpaper() {
    if (!state.items.length) {
      loadSource();
      return;
    }
    if (state.items.length === 1) {
      showWallpaperAt(0);
      return;
    }
    let next = state.settings.currentIndex;
    while (next === state.settings.currentIndex) {
      next = Math.floor(Math.random() * state.items.length);
    }
    showWallpaperAt(next);
  }

  function paintWallpaper(wallpaper) {
    const title = wallpaper.title || "Untitled wallpaper";
    const detail = formatWallpaperDetails(wallpaper);
    const slug = wallpaper.slug || wallpaper.id;
    const highSrc = getBestImage(wallpaper);
    const softSrc = wallpaper.thumb_url || wallpaper.preview_url || highSrc;
    const color = sanitizeColor(wallpaper.dominant_color) || "#101316";

    elements.base.style.backgroundColor = color;
    elements.title.textContent = title;
    elements.details.textContent = detail;
    elements.openLink.href = `${SITE_BASE}/wallpaper/${slug}`;
    elements.openLink.setAttribute("aria-label", `Open ${title}`);
    elements.stage.classList.add("is-loading");

    if (softSrc && elements.image.src !== softSrc) {
      elements.image.classList.remove("is-ready");
      elements.image.classList.add("is-soft");
      elements.image.src = softSrc;
      requestAnimationFrame(() => elements.image.classList.add("is-ready"));
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
      setStatus("The high quality image did not load. Showing the preview.");
    };
    loader.src = highSrc;
  }

  function getBestImage(wallpaper) {
    return wallpaper.original_url || wallpaper.preview_url || wallpaper.thumb_url || "";
  }

  function formatWallpaperDetails(wallpaper) {
    const parts = [];
    if (wallpaper.width && wallpaper.height) parts.push(`${wallpaper.width} x ${wallpaper.height}`);
    if (wallpaper.file_size) parts.push(formatBytes(wallpaper.file_size));
    if (wallpaper.is_dynamic) {
      const type = wallpaper.dynamic_type ? wallpaper.dynamic_type.toUpperCase() : "DYNAMIC";
      parts.push(type);
    }
    return parts.join("  ");
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

  function renderThumbStrip() {
    const previewItems = state.items.slice(0, 10);
    elements.thumbStrip.replaceChildren();
    previewItems.forEach((item, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `thumb-button${index === state.settings.currentIndex ? " is-active" : ""}`;
      button.setAttribute("aria-label", item.title || `Wallpaper ${index + 1}`);
      const img = document.createElement("img");
      img.loading = "lazy";
      img.decoding = "async";
      img.src = item.thumb_url || item.preview_url || getBestImage(item);
      img.alt = "";
      button.appendChild(img);
      button.addEventListener("click", () => showWallpaperAt(index));
      elements.thumbStrip.appendChild(button);
    });
  }

  async function loadCollections({ force = false } = {}) {
    if (!state.settings.token) {
      elements.collectionBlock.hidden = true;
      return;
    }
    if (!force && state.collections.length) {
      renderCollections();
      return;
    }
    setStatus("Loading collections...");
    try {
      const collections = await apiFetch("/users/me/collections?limit=80");
      state.collections = Array.isArray(collections) ? collections : [];
      renderCollections();
      setStatus("");
    } catch (error) {
      setStatus(error.message || "Unable to load collections.");
    }
  }

  function renderCollections() {
    elements.collectionBlock.hidden = state.settings.source !== "collection" || !state.settings.token;
    elements.collectionsList.replaceChildren();

    state.collections.forEach((collection) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `collection-button${collection.id === state.settings.collectionId ? " is-selected" : ""}`;
      const title = document.createElement("span");
      title.textContent = collection.title || "Untitled collection";
      const count = document.createElement("small");
      count.textContent = `${collection.wallpaper_count || 0} wallpapers`;
      button.append(title, count);
      button.addEventListener("click", async () => {
        state.settings.collectionId = collection.id;
        state.settings.collectionTitle = collection.title || "My Collection";
        state.settings.currentIndex = 0;
        await saveSettings();
        renderCollections();
        await loadSource();
      });
      elements.collectionsList.appendChild(button);
    });
  }

  async function handleLogin(event) {
    event.preventDefault();
    const form = new FormData(elements.loginForm);
    const email = String(form.get("email") || "").trim();
    const password = String(form.get("password") || "");
    if (!email || !password) {
      setStatus("Enter your email and password.");
      return;
    }
    setStatus("Signing in...");
    try {
      const data = await apiFetch("/auth/login", {
        method: "POST",
        body: { email, password },
        skipAuth: true
      });
      state.settings.token = data.token || "";
      state.settings.user = data.user || null;
      await saveSettings();
      elements.loginForm.reset();
      renderAuthState();
      await loadCollections({ force: true });
      await loadSource();
      setStatus("");
    } catch (error) {
      setStatus(error.message || "Sign in failed.");
    }
  }

  async function handleSignOut() {
    state.settings.token = "";
    state.settings.user = null;
    state.settings.collectionId = null;
    state.settings.collectionTitle = "";
    if (state.settings.source !== "weekly") state.settings.source = "weekly";
    await saveSettings();
    renderAuthState();
    renderSourceOptions();
    renderCollections();
    await loadSource();
  }

  function renderAuthState() {
    const user = state.settings.user;
    const signedIn = Boolean(state.settings.token && user);
    elements.signedInRow.hidden = !signedIn;
    elements.loginFields.hidden = signedIn;
    elements.signedInName.textContent = signedIn ? (user.nickname || user.username || "Signed in") : "";
    if (signedIn) loadCollections();
  }

  function renderSourceOptions() {
    elements.sourceOptions.forEach((button) => {
      const active = button.dataset.source === state.settings.source;
      button.setAttribute("aria-checked", active ? "true" : "false");
    });
    elements.collectionBlock.hidden = state.settings.source !== "collection" || !state.settings.token;
    if (state.settings.source === "collection" && state.settings.token) loadCollections();
  }

  function sourceName() {
    if (state.settings.source === "favorites") return "My Favorites";
    if (state.settings.source === "collection") return state.settings.collectionTitle || "My Collection";
    return "Weekly Picks";
  }

  function handleSearch(event) {
    event.preventDefault();
    const query = elements.searchInput.value.trim();
    if (!query) return;

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

  function setStatus(message) {
    elements.statusLine.textContent = message || "";
  }

  function updateClock() {
    const now = new Date();
    const display = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    elements.clock.textContent = display;
    elements.clock.dateTime = now.toISOString();
  }

  async function apiFetch(path, options = {}) {
    const headers = {
      Accept: "application/json"
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

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function wrap(value, length) {
    return ((value % length) + length) % length;
  }

  function sanitizeColor(value) {
    if (typeof value !== "string") return "";
    return /^#[0-9a-f]{6}$/i.test(value.trim()) ? value.trim() : "";
  }
})();
