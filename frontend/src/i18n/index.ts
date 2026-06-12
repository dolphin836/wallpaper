import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import common from './locales/common';
import auth from './locales/auth';
import profile from './locales/profile';
import detail from './locales/detail';
import browse from './locales/browse';
import collections from './locales/collections';
import upload from './locales/upload';
import devices from './locales/devices';
import mac from './locales/mac';
import about from './locales/about';

export const SUPPORTED_LANGS = ['en', 'zh-CN', 'zh-TW', 'ja'] as const;
export type Lang = (typeof SUPPORTED_LANGS)[number];

/** Native-script names for the switcher — these never get translated. */
export const LANG_NAMES: Record<Lang, string> = {
  en: 'English',
  'zh-CN': '简体中文',
  'zh-TW': '繁體中文',
  ja: '日本語',
};

const STORAGE_KEY = 'wpe_lang';

/** Saved choice wins; otherwise map the browser locale onto the four
 *  supported UI languages (zh-TW/HK/MO/Hant → Traditional, any other
 *  zh → Simplified) and fall back to English. */
function detectLang(): Lang {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && (SUPPORTED_LANGS as readonly string[]).includes(saved)) return saved as Lang;
  } catch { /* storage unavailable */ }
  const nav = navigator.languages?.[0] ?? navigator.language ?? 'en';
  if (/^zh/i.test(nav)) return /TW|HK|MO|Hant/i.test(nav) ? 'zh-TW' : 'zh-CN';
  if (/^ja/i.test(nav)) return 'ja';
  return 'en';
}

// Each locale module exports { en, 'zh-CN', 'zh-TW', ja }; pivot that into
// i18next's resources[lng][ns] shape.
const modules = { common, auth, profile, detail, browse, collections, upload, devices, mac, about };

const resources = Object.fromEntries(
  SUPPORTED_LANGS.map((lng) => [
    lng,
    Object.fromEntries(Object.entries(modules).map(([ns, mod]) => [ns, mod[lng]])),
  ]),
);

i18n.use(initReactI18next).init({
  resources,
  lng: detectLang(),
  fallbackLng: 'en',
  ns: Object.keys(modules),
  defaultNS: 'common',
  interpolation: { escapeValue: false }, // React already escapes
});

i18n.on('languageChanged', (lng) => { document.documentElement.lang = lng; });
document.documentElement.lang = i18n.language;

export function setLanguage(lng: Lang) {
  try { localStorage.setItem(STORAGE_KEY, lng); } catch { /* storage unavailable */ }
  void i18n.changeLanguage(lng);
}

export default i18n;
