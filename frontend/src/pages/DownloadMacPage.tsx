import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  AiOutlineAndroid,
  AiOutlineApple,
  AiOutlineCloudDownload,
  AiOutlineDownload,
  AiOutlineMobile,
  AiOutlineQrcode,
  AiOutlineSafetyCertificate,
  AiOutlineSync,
} from "react-icons/ai";
import { FiChrome } from "react-icons/fi";
import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { getAndroidRelease, getChromeRelease, getMacRelease } from "../api";
import type { AndroidRelease, ChromeRelease, MacRelease, MacReleaseEntry } from "../types";
import PageMeta from "../components/PageMeta";
import { track } from "../lib/track";

const DEFAULT_MACOS_VERSION = "14.0";
const CLIENT_KEYS = ["mac", "android", "chrome", "ios"] as const;

type ClientKey = (typeof CLIENT_KEYS)[number];
type DownloadTarget = "mac" | "android" | "chrome";
type DownloadArtifact = "dmg" | "apk" | "zip";
type DownloadSurface = "client_card" | "release_panel";

interface ClientEntry {
  key: ClientKey;
  icon: ReactNode;
  eyebrow: string;
  title: string;
  text: string;
  version: string;
  requirement: string;
  updated: string;
  href?: string;
  actionLabel: string;
  targetClient?: DownloadTarget;
  artifact?: DownloadArtifact;
  notes: string[];
  footer?: string;
  comingSoon?: boolean;
}

function formatReleaseDate(value: string | undefined, latestLabel: string) {
  if (!value) return latestLabel;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

function localizedMacNotes(entry: MacReleaseEntry | undefined, lang: string): string[] {
  if (!entry) return [];
  return entry.notes_i18n?.[lang] ?? entry.notes ?? [];
}

function latestMacNotes(release: MacRelease | null, lang: string) {
  return localizedMacNotes(release?.releases?.[0], lang).filter(Boolean).slice(0, 4);
}

function localizedAndroidNotes(release: AndroidRelease | null, lang: string): string[] {
  if (!release) return [];
  return (release.notes_i18n?.[lang] ?? release.notes ?? []).filter(Boolean).slice(0, 4);
}

export default function DownloadMacPage() {
  const { t, i18n } = useTranslation("mac");
  const [macRelease, setMacRelease] = useState<MacRelease | null>(null);
  const [androidRelease, setAndroidRelease] = useState<AndroidRelease | null>(null);
  const [chromeRelease, setChromeRelease] = useState<ChromeRelease | null>(null);
  const [selectedClient, setSelectedClient] = useState<ClientKey>("mac");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    Promise.allSettled([getMacRelease(), getAndroidRelease(), getChromeRelease()])
      .then(([macResult, androidResult, chromeResult]) => {
        if (cancelled) return;

        const nextMac =
          macResult.status === "fulfilled" ? macResult.value.data.data : null;
        const nextAndroid =
          androidResult.status === "fulfilled" ? androidResult.value.data.data : null;
        const nextChrome =
          chromeResult.status === "fulfilled" ? chromeResult.value : null;

        setMacRelease(nextMac);
        setAndroidRelease(nextAndroid);
        setChromeRelease(nextChrome);
        setError(nextMac || nextAndroid || nextChrome ? null : t("error.loadFailed"));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [t]);

  const macVersion = macRelease?.current_version ?? "2.0";
  const minimumMacOS = macRelease?.min_macos_version ?? DEFAULT_MACOS_VERSION;
  const currentMacRelease = macRelease?.releases?.[0];
  const macNotes = useMemo(
    () => latestMacNotes(macRelease, i18n.language),
    [macRelease, i18n.language],
  );
  const androidNotes = useMemo(
    () => localizedAndroidNotes(androidRelease, i18n.language),
    [androidRelease, i18n.language],
  );
  const chromeNotes = useMemo(() => [t("release.chromeNote")], [t]);

  const trackClientDownload = (
    targetClient: DownloadTarget,
    artifact: DownloadArtifact,
    version: string | undefined,
    url: string | undefined,
    surface: DownloadSurface,
  ) => {
    track("client_download", {
      target_client: targetClient,
      artifact,
      version: version ?? "",
      url: url ?? "",
      surface,
    });
  };

  const clients = useMemo<ClientEntry[]>(() => [
    {
      key: "mac",
      icon: <AiOutlineApple />,
      eyebrow: t("platforms.mac.eyebrow"),
      title: t("platforms.mac.title"),
      text: t("platforms.mac.text"),
      version: macRelease ? `v${macVersion}` : t("status.unavailable"),
      requirement: `macOS ${minimumMacOS}+`,
      updated: formatReleaseDate(currentMacRelease?.released_at, t("release.latest")),
      href: macRelease?.current_dmg_url,
      actionLabel: t("actions.downloadMac"),
      targetClient: "mac",
      artifact: "dmg",
      notes: macNotes,
    },
    {
      key: "android",
      icon: <AiOutlineAndroid />,
      eyebrow: t("platforms.android.eyebrow"),
      title: t("platforms.android.title"),
      text: t("platforms.android.text"),
      version: androidRelease ? `v${androidRelease.current_version}` : t("status.unavailable"),
      requirement: t("platforms.android.requirement"),
      updated: formatReleaseDate(androidRelease?.released_at, t("release.latest")),
      href: androidRelease?.current_apk_url,
      actionLabel: t("actions.downloadAndroid"),
      targetClient: "android",
      artifact: "apk",
      notes: androidNotes,
      footer: androidRelease?.apk_sha256 ? t("release.apkHash", { hash: androidRelease.apk_sha256.slice(0, 12) }) : undefined,
    },
    {
      key: "chrome",
      icon: <FiChrome />,
      eyebrow: t("platforms.chrome.eyebrow"),
      title: t("platforms.chrome.title"),
      text: t("platforms.chrome.text"),
      version: chromeRelease ? `v${chromeRelease.current_version}` : t("status.unavailable"),
      requirement: t("platforms.chrome.requirement"),
      updated: formatReleaseDate(chromeRelease?.released_at, t("release.latest")),
      href: chromeRelease?.current_zip_url,
      actionLabel: t("actions.downloadChrome"),
      targetClient: "chrome",
      artifact: "zip",
      notes: chromeNotes,
      footer: chromeRelease?.zip_sha256 ? t("release.zipHash", { hash: chromeRelease.zip_sha256.slice(0, 12) }) : undefined,
    },
    {
      key: "ios",
      icon: <AiOutlineMobile />,
      eyebrow: t("platforms.ios.eyebrow"),
      title: t("platforms.ios.title"),
      text: t("platforms.ios.text"),
      version: t("status.comingSoon"),
      requirement: t("status.comingSoon"),
      updated: t("status.comingSoon"),
      actionLabel: t("status.comingSoon"),
      notes: [t("release.iosPending")],
      comingSoon: true,
    },
  ], [
    androidNotes,
    androidRelease,
    chromeNotes,
    chromeRelease,
    currentMacRelease?.released_at,
    macNotes,
    macRelease,
    macVersion,
    minimumMacOS,
    t,
  ]);

  const activeClient = clients.find((client) => client.key === selectedClient) ?? clients[0];

  const handleDownload = (client: ClientEntry, surface: DownloadSurface) => {
    if (!client.targetClient || !client.artifact) return;
    trackClientDownload(client.targetClient, client.artifact, client.version, client.href, surface);
  };

  return (
    <main className="min-h-full bg-paper text-ink">
      <PageMeta title={t("meta.title")} description={t("meta.description")} />

      <section className="relative isolate overflow-hidden border-b border-hair">
        <div
          className="pointer-events-none absolute inset-0 -z-10 opacity-90"
          style={{
            background:
              "radial-gradient(circle at 12% 18%, rgba(238, 122, 74, 0.18), transparent 30%), radial-gradient(circle at 86% 10%, rgba(72, 118, 160, 0.12), transparent 28%), linear-gradient(180deg, var(--color-paper), var(--color-paper-2))",
          }}
        />

        <div className="mx-auto max-w-[1440px] px-6 py-10 sm:px-10 lg:px-14 lg:py-14">
          <div className="grid gap-10 lg:grid-cols-[0.84fr_1.16fr] lg:items-end">
            <div>
              <div className="label-rule max-w-xl">
                <span>{t("hero.label")}</span>
                <span>{t("hero.kicker")}</span>
              </div>

              <div className="mt-10 max-w-[680px]">
                <h1 className="display max-w-3xl text-[3.15rem] leading-[0.98] sm:text-[5.6rem] lg:text-[6.2rem]">
                  {t("hero.title")}
                </h1>
                <p className="mt-6 max-w-xl text-base leading-8 text-muted sm:text-lg">
                  {t("hero.subtitle")}
                </p>
              </div>

              <div className="mt-9 grid max-w-2xl gap-4 sm:grid-cols-3">
                <QuickPoint icon={<AiOutlineCloudDownload />} label={t("quick.directLabel")} text={t("quick.directText")} />
                <QuickPoint icon={<AiOutlineSync />} label={t("quick.updateLabel")} text={t("quick.updateText")} />
                <QuickPoint icon={<AiOutlineSafetyCertificate />} label={t("quick.accountLabel")} text={t("quick.accountText")} />
              </div>
            </div>

            {loading ? (
              <HeroSkeleton />
            ) : error ? (
              <DownloadError message={error} />
            ) : (
              <FeaturedClient
                client={activeClient}
                onDownload={() => handleDownload(activeClient, "client_card")}
              />
            )}
          </div>

          {!loading && !error ? (
            <div className="mt-10">
              <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
                <div>
                  <p className="kicker">{t("selector.kicker")}</p>
                  <h2 className="mt-2 text-2xl font-semibold tracking-normal text-ink">{t("selector.title")}</h2>
                </div>
                <p className="max-w-md text-sm leading-6 text-muted">{t("selector.helper")}</p>
              </div>
              <ClientSwitcher
                clients={clients}
                selected={selectedClient}
                onSelect={setSelectedClient}
              />
            </div>
          ) : null}
        </div>
      </section>

      {!loading && !error ? (
        <>
          <section
            id="release-notes"
            className="mx-auto grid max-w-[1440px] gap-8 px-6 py-12 sm:px-10 lg:grid-cols-[320px_1fr] lg:px-14 lg:py-14"
          >
            <aside className="lg:sticky lg:top-24 lg:self-start">
              <p className="kicker">{t("release.selectedKicker")}</p>
              <h2 className="display mt-3 text-[2.8rem] leading-none sm:text-[3.7rem]">
                {t("release.selectedTitle")}
              </h2>
              <p className="mt-5 text-sm leading-7 text-muted">{t("release.selectedText")}</p>

              <div className="mt-7 grid gap-2">
                {clients.map((client) => (
                  <button
                    key={client.key}
                    type="button"
                    onClick={() => setSelectedClient(client.key)}
                    className={`group flex items-center justify-between gap-4 rounded-[14px] px-4 py-3 text-left transition focus:outline-none focus:ring-2 focus:ring-accent/40 ${
                      selectedClient === client.key
                        ? "bg-ink text-paper shadow-[0_18px_44px_rgba(43,38,34,0.16)]"
                        : "bg-paper-2 text-ink hover:bg-paper hover:shadow-sm"
                    }`}
                  >
                    <span className="flex items-center gap-3">
                      <span className={`grid h-9 w-9 place-items-center rounded-[10px] text-lg ${
                        selectedClient === client.key ? "bg-paper/12 text-accent" : "bg-accent/10 text-accent"
                      }`}>
                        {client.icon}
                      </span>
                      <span>
                        <span className="block text-sm font-semibold">{client.title}</span>
                        <span className={`mt-0.5 block text-xs ${
                          selectedClient === client.key ? "text-paper/58" : "text-muted"
                        }`}>
                          {client.version}
                        </span>
                      </span>
                    </span>
                    {selectedClient === client.key ? (
                      <span className="h-2 w-2 rounded-full bg-accent" />
                    ) : null}
                  </button>
                ))}
              </div>
            </aside>

            <ReleaseWorkspace
              client={activeClient}
              macReleases={macRelease?.releases ?? []}
              onDownload={() => handleDownload(activeClient, "release_panel")}
            />
          </section>

          <section className="mx-auto max-w-[1440px] border-t border-hair px-6 py-10 sm:px-10 lg:px-14">
            <div className="flex flex-col gap-5 rounded-[18px] bg-paper-2 px-6 py-6 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="kicker">{t("install.kicker")}</p>
                <p className="mt-2 text-lg font-semibold text-ink">{t("install.text")}</p>
              </div>
              <Link
                to="/discover"
                className="inline-flex h-11 items-center justify-center rounded-full bg-ink px-5 text-sm font-semibold text-paper transition hover:-translate-y-0.5 hover:bg-accent focus:outline-none focus:ring-2 focus:ring-accent/40"
              >
                {t("install.browse")}
              </Link>
            </div>
          </section>
        </>
      ) : null}
    </main>
  );
}

function QuickPoint({ icon, label, text }: { icon: ReactNode; label: string; text: string }) {
  return (
    <div className="flex gap-3">
      <span className="mt-1 grid h-9 w-9 flex-none place-items-center rounded-[10px] bg-accent/10 text-lg text-accent">
        {icon}
      </span>
      <div>
        <h3 className="text-sm font-semibold text-ink">{label}</h3>
        <p className="mt-1 text-xs leading-6 text-muted">{text}</p>
      </div>
    </div>
  );
}

function FeaturedClient({
  client,
  onDownload,
}: {
  client: ClientEntry;
  onDownload: () => void;
}) {
  const { t } = useTranslation("mac");

  return (
    <article className="relative overflow-hidden rounded-[24px] bg-ink p-6 text-paper shadow-[0_30px_90px_rgba(43,38,34,0.18)]">
      <div
        className="pointer-events-none absolute inset-0 opacity-80"
        style={{
          background:
            "radial-gradient(circle at 12% 0%, rgba(238,122,74,0.42), transparent 28%), radial-gradient(circle at 100% 20%, rgba(255,255,255,0.14), transparent 28%)",
        }}
      />
      <div className="relative">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <span className="grid h-14 w-14 place-items-center rounded-[16px] bg-paper/10 text-3xl text-accent">
              {client.icon}
            </span>
            <div>
              <p className="kicker text-paper/56">{client.eyebrow}</p>
              <h2 className="mt-1 text-3xl font-semibold tracking-normal text-paper">{client.title}</h2>
            </div>
          </div>
          <span className="rounded-full bg-paper/10 px-3 py-1 text-xs font-semibold text-paper/74">
            {client.version}
          </span>
        </div>

        <p className="mt-7 max-w-2xl text-sm leading-7 text-paper/72">{client.text}</p>

        <dl className="mt-8 grid gap-px overflow-hidden rounded-[16px] bg-paper/12 sm:grid-cols-2">
          <SpecItem label={t("card.requirement")} value={client.requirement} />
          <SpecItem label={t("card.updated")} value={client.updated} />
        </dl>

        <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          {client.href ? (
            <a
              href={client.href}
              download
              onClick={onDownload}
              className="inline-flex h-12 items-center justify-center gap-2 rounded-full bg-accent px-6 text-sm font-semibold text-white shadow-[0_18px_48px_rgba(238,122,74,0.28)] transition hover:-translate-y-0.5 hover:bg-accent-strong focus:outline-none focus:ring-2 focus:ring-white/40"
            >
              <AiOutlineDownload className="text-lg" />
              {client.actionLabel}
            </a>
          ) : (
            <button
              type="button"
              disabled
              className="inline-flex h-12 cursor-not-allowed items-center justify-center rounded-full bg-paper/10 px-6 text-sm font-semibold text-paper/52"
            >
              {client.actionLabel}
            </button>
          )}

          {client.comingSoon ? (
            <div className="grid h-20 w-20 place-items-center rounded-[18px] border border-dashed border-paper/20 text-paper/64">
              <AiOutlineQrcode className="text-4xl" />
            </div>
          ) : client.footer ? (
            <p className="font-mono text-xs text-paper/48">{client.footer}</p>
          ) : null}
        </div>
      </div>
    </article>
  );
}

function SpecItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-paper/5 px-4 py-3">
      <dt className="kicker text-[0.62rem] text-paper/45">{label}</dt>
      <dd className="mt-1 text-sm font-semibold text-paper">{value}</dd>
    </div>
  );
}

function ClientSwitcher({
  clients,
  selected,
  onSelect,
}: {
  clients: ClientEntry[];
  selected: ClientKey;
  onSelect: (key: ClientKey) => void;
}) {
  const { t } = useTranslation("mac");

  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4" role="list" aria-label={t("selector.title")}>
      {clients.map((client) => {
        const isSelected = client.key === selected;
        return (
          <button
            key={client.key}
            type="button"
            onClick={() => onSelect(client.key)}
            className={`group flex min-h-[154px] flex-col rounded-[18px] p-4 text-left transition focus:outline-none focus:ring-2 focus:ring-accent/40 ${
              isSelected
                ? "bg-paper shadow-[0_18px_60px_rgba(43,38,34,0.12)] ring-1 ring-ink/10"
                : "bg-paper/70 hover:-translate-y-0.5 hover:bg-paper hover:shadow-[0_14px_46px_rgba(43,38,34,0.08)]"
            }`}
          >
            <span className="flex items-start justify-between gap-4">
              <span className="grid h-11 w-11 place-items-center rounded-[13px] bg-accent/10 text-2xl text-accent">
                {client.icon}
              </span>
              <span className={`rounded-full px-3 py-1 text-xs font-semibold ${
                isSelected ? "bg-ink text-paper" : "bg-paper-2 text-muted"
              }`}>
                {client.version}
              </span>
            </span>
            <span className="mt-5 block">
              <span className="kicker">{client.eyebrow}</span>
              <span className="mt-2 block text-xl font-semibold tracking-normal text-ink">{client.title}</span>
            </span>
            <span className="mt-auto pt-4 text-xs font-semibold text-accent">
              {isSelected ? t("selector.selected") : t("selector.choose")}
            </span>
          </button>
        );
      })}
    </div>
  );
}

function ReleaseWorkspace({
  client,
  macReleases,
  onDownload,
}: {
  client: ClientEntry;
  macReleases: MacReleaseEntry[];
  onDownload: () => void;
}) {
  const { t, i18n } = useTranslation("mac");
  const showMacHistory = client.key === "mac" && macReleases.length > 0;

  return (
    <div className="grid gap-4">
      <article className="rounded-[22px] bg-paper p-6 shadow-[0_18px_70px_rgba(43,38,34,0.08)]">
        <div className="flex flex-col gap-5 border-b border-hair pb-5 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex gap-4">
            <span className="grid h-12 w-12 flex-none place-items-center rounded-[14px] bg-accent/10 text-2xl text-accent">
              {client.icon}
            </span>
            <div>
              <p className="kicker">{client.eyebrow}</p>
              <h3 className="mt-1 text-2xl font-semibold tracking-normal text-ink">{client.title}</h3>
              <p className="mt-2 text-sm leading-6 text-muted">{client.updated}</p>
            </div>
          </div>
          <span className="w-fit rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold text-accent">
            {client.version}
          </span>
        </div>

        <div className="mt-6 grid gap-8 lg:grid-cols-[1fr_260px]">
          <div>
            <p className="kicker">{t("release.latestChanges")}</p>
            {client.notes.length ? (
              <ul className="mt-4 grid gap-3">
                {client.notes.map((note, index) => (
                  <li key={`${client.key}-${index}`} className="flex gap-3 text-sm leading-7 text-ink">
                    <span className="mt-2 h-1.5 w-1.5 flex-none rounded-full bg-accent" />
                    <span>{note}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="mt-4 text-sm leading-7 text-muted">{t("release.noNotes")}</p>
            )}
          </div>

          <div className="grid content-start gap-3 rounded-[16px] bg-paper-2 p-4">
            <div>
              <p className="kicker text-[0.62rem]">{t("card.requirement")}</p>
              <p className="mt-1 text-sm font-semibold text-ink">{client.requirement}</p>
            </div>
            {client.footer ? <p className="font-mono text-xs leading-5 text-muted">{client.footer}</p> : null}
            {client.href ? (
              <a
                href={client.href}
                download
                onClick={onDownload}
                className="mt-2 inline-flex h-10 items-center justify-center gap-2 rounded-full bg-ink px-4 text-sm font-semibold text-paper transition hover:-translate-y-0.5 hover:bg-accent focus:outline-none focus:ring-2 focus:ring-accent/40"
              >
                <AiOutlineDownload className="text-lg" />
                {client.actionLabel}
              </a>
            ) : (
              <div className="mt-2 grid h-28 place-items-center rounded-[14px] border border-dashed border-hair bg-paper text-muted">
                <AiOutlineQrcode className="text-5xl" />
              </div>
            )}
          </div>
        </div>
      </article>

      {showMacHistory ? (
        <article className="rounded-[22px] bg-paper p-6 shadow-[0_18px_70px_rgba(43,38,34,0.06)]">
          <div className="label-rule">
            <span>{t("release.changelog")}</span>
            <span>{t("release.buildCount", { num: macReleases.length })}</span>
          </div>
          <ol className="mt-5 divide-y divide-hair">
            {macReleases.slice(0, 5).map((entry) => (
              <li key={entry.version} className="grid gap-3 py-4 sm:grid-cols-[140px_1fr]">
                <div>
                  <p className="text-sm font-semibold text-ink">v{entry.version}</p>
                  <p className="mt-1 text-xs text-muted">{formatReleaseDate(entry.released_at, t("release.latest"))}</p>
                </div>
                <ul className="grid gap-2">
                  {localizedMacNotes(entry, i18n.language).slice(0, 3).map((note, index) => (
                    <li key={`${entry.version}-${index}`} className="text-sm leading-6 text-muted">
                      {note}
                    </li>
                  ))}
                </ul>
              </li>
            ))}
          </ol>
        </article>
      ) : (
        <article className="rounded-[18px] bg-paper-2 px-5 py-4 text-sm leading-6 text-muted">
          {t("release.historyUnavailable")}
        </article>
      )}
    </div>
  );
}

function HeroSkeleton() {
  return (
    <div className="min-h-[360px] animate-pulse rounded-[24px] bg-paper p-6 shadow-[0_20px_70px_rgba(43,38,34,0.08)]">
      <div className="flex justify-between">
        <div className="h-14 w-14 rounded-[16px] bg-hair/70" />
        <div className="h-7 w-24 rounded-full bg-hair/60" />
      </div>
      <div className="mt-10 h-3 w-24 rounded-full bg-hair/70" />
      <div className="mt-5 h-10 w-52 rounded-full bg-hair/70" />
      <div className="mt-6 h-20 rounded-[16px] bg-hair/50" />
      <div className="mt-8 grid gap-px overflow-hidden rounded-[16px] bg-hair sm:grid-cols-2">
        <div className="h-20 bg-hair/60" />
        <div className="h-20 bg-hair/50" />
      </div>
      <div className="mt-8 h-12 w-44 rounded-full bg-hair/70" />
    </div>
  );
}

function DownloadError({ message }: { message: string }) {
  const { t } = useTranslation("mac");
  return (
    <div className="rounded-[20px] border border-hair bg-paper px-6 py-10 text-center shadow-sm">
      <p className="kicker">{t("error.kicker")}</p>
      <h1 className="display mt-3 text-[3rem] leading-none sm:text-[4.5rem]">{t("error.title")}</h1>
      <p className="mt-5 text-sm leading-7 text-muted">{message}</p>
      <Link
        to="/"
        className="mt-7 inline-flex h-11 items-center justify-center rounded-full bg-ink px-5 text-sm font-semibold text-paper transition hover:bg-accent"
      >
        {t("error.backHome")}
      </Link>
    </div>
  );
}
