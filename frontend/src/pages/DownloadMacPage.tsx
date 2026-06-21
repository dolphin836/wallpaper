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
import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { getAndroidRelease, getMacRelease } from "../api";
import type { AndroidRelease, MacRelease, MacReleaseEntry } from "../types";
import PageMeta from "../components/PageMeta";
import { track } from "../lib/track";

const DEFAULT_MACOS_VERSION = "14.0";

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
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    Promise.allSettled([getMacRelease(), getAndroidRelease()])
      .then(([macResult, androidResult]) => {
        if (cancelled) return;

        const nextMac =
          macResult.status === "fulfilled" ? macResult.value.data.data : null;
        const nextAndroid =
          androidResult.status === "fulfilled" ? androidResult.value.data.data : null;

        setMacRelease(nextMac);
        setAndroidRelease(nextAndroid);
        setError(nextMac || nextAndroid ? null : t("error.loadFailed"));
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
  const trackClientDownload = (
    targetClient: "mac" | "android",
    artifact: "dmg" | "apk",
    version: string | undefined,
    url: string | undefined,
    surface: "client_card" | "release_panel",
  ) => {
    track("client_download", {
      target_client: targetClient,
      artifact,
      version: version ?? "",
      url: url ?? "",
      surface,
    });
  };

  return (
    <main className="min-h-full bg-paper text-ink">
      <PageMeta title={t("meta.title")} description={t("meta.description")} />

      <section className="relative isolate overflow-hidden border-b border-hair">
        <div
          className="pointer-events-none absolute inset-0 -z-10 opacity-80"
          style={{
            background:
              "radial-gradient(circle at 16% 10%, rgba(238, 122, 74, 0.2), transparent 32%), radial-gradient(circle at 84% 14%, rgba(79, 129, 190, 0.14), transparent 28%), linear-gradient(180deg, var(--color-paper), var(--color-paper-2))",
          }}
        />

        <div className="mx-auto grid max-w-[1600px] gap-8 px-6 py-8 sm:px-10 lg:grid-cols-[0.72fr_1.28fr] lg:px-14 lg:py-12">
          <div className="flex min-h-[520px] flex-col justify-between">
            <div>
              <div className="label-rule">
                <span>{t("hero.label")}</span>
                <span>{t("hero.kicker")}</span>
              </div>

              <div className="mt-10 max-w-[640px]">
                <h1 className="display text-[3.25rem] leading-[0.96] sm:text-[5.4rem] lg:text-[6.4rem]">
                  {t("hero.title")}
                </h1>
                <p className="mt-6 max-w-xl text-base leading-8 text-muted sm:text-lg">
                  {t("hero.subtitle")}
                </p>
              </div>

              <div className="mt-8 grid max-w-2xl gap-px overflow-hidden rounded-[14px] border border-hair bg-hair sm:grid-cols-3">
                <DownloadStat label={t("hero.statMac")} value={macRelease ? `v${macVersion}` : t("status.unavailable")} />
                <DownloadStat label={t("hero.statAndroid")} value={androidRelease ? `v${androidRelease.current_version}` : t("status.unavailable")} />
                <DownloadStat label={t("hero.statIos")} value={t("status.comingSoon")} />
              </div>
            </div>

            <div className="mt-10 grid gap-4 border-t border-hair pt-6 sm:grid-cols-3">
              <QuickPoint icon={<AiOutlineCloudDownload />} label={t("quick.directLabel")} text={t("quick.directText")} />
              <QuickPoint icon={<AiOutlineSync />} label={t("quick.updateLabel")} text={t("quick.updateText")} />
              <QuickPoint icon={<AiOutlineSafetyCertificate />} label={t("quick.accountLabel")} text={t("quick.accountText")} />
            </div>
          </div>

          <div className="grid content-center gap-4 lg:min-h-[520px]">
            {loading ? (
              <DownloadSkeleton />
            ) : error ? (
              <DownloadError message={error} />
            ) : (
              <div className="grid gap-4 xl:grid-cols-3">
                <ClientCard
                  icon={<AiOutlineApple />}
                  eyebrow={t("platforms.mac.eyebrow")}
                  title={t("platforms.mac.title")}
                  text={t("platforms.mac.text")}
                  version={macRelease ? `v${macVersion}` : t("status.unavailable")}
                  requirement={`macOS ${minimumMacOS}+`}
                  updated={formatReleaseDate(currentMacRelease?.released_at, t("release.latest"))}
                  href={macRelease?.current_dmg_url}
                  actionLabel={t("actions.downloadMac")}
                  onDownload={() => trackClientDownload("mac", "dmg", macVersion, macRelease?.current_dmg_url, "client_card")}
                  tone="accent"
                />

                <ClientCard
                  icon={<AiOutlineAndroid />}
                  eyebrow={t("platforms.android.eyebrow")}
                  title={t("platforms.android.title")}
                  text={t("platforms.android.text")}
                  version={androidRelease ? `v${androidRelease.current_version}` : t("status.unavailable")}
                  requirement={t("platforms.android.requirement")}
                  updated={formatReleaseDate(androidRelease?.released_at, t("release.latest"))}
                  href={androidRelease?.current_apk_url}
                  actionLabel={t("actions.downloadAndroid")}
                  onDownload={() => trackClientDownload("android", "apk", androidRelease?.current_version, androidRelease?.current_apk_url, "client_card")}
                  tone="ink"
                />

                <IOSCard />
              </div>
            )}
          </div>
        </div>
      </section>

      {!loading && !error ? (
        <>
          <section className="mx-auto grid max-w-[1600px] gap-8 px-6 py-12 sm:px-10 lg:grid-cols-[0.76fr_1.24fr] lg:px-14">
            <div className="border-t border-hair pt-6">
              <p className="kicker">{t("overview.kicker")}</p>
              <h2 className="display mt-4 max-w-2xl text-[2.7rem] leading-none sm:text-[4.2rem]">
                {t("overview.title")}
              </h2>
              <p className="mt-5 max-w-xl text-sm leading-7 text-muted">
                {t("overview.text")}
              </p>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <ReleasePanel
                icon={<AiOutlineApple />}
                title={t("release.macTitle")}
                version={macRelease ? `v${macVersion}` : t("status.unavailable")}
                date={formatReleaseDate(currentMacRelease?.released_at, t("release.latest"))}
                notes={macNotes}
                emptyText={t("release.noNotes")}
                href={macRelease?.current_dmg_url}
                actionLabel={t("actions.downloadMac")}
                onDownload={() => trackClientDownload("mac", "dmg", macVersion, macRelease?.current_dmg_url, "release_panel")}
              />

              <ReleasePanel
                icon={<AiOutlineAndroid />}
                title={t("release.androidTitle")}
                version={androidRelease ? `v${androidRelease.current_version}` : t("status.unavailable")}
                date={formatReleaseDate(androidRelease?.released_at, t("release.latest"))}
                notes={androidNotes}
                emptyText={t("release.noNotes")}
                href={androidRelease?.current_apk_url}
                actionLabel={t("actions.downloadAndroid")}
                onDownload={() => trackClientDownload("android", "apk", androidRelease?.current_version, androidRelease?.current_apk_url, "release_panel")}
                footer={androidRelease?.apk_sha256 ? t("release.apkHash", { hash: androidRelease.apk_sha256.slice(0, 12) }) : undefined}
              />
            </div>
          </section>

          {macRelease?.releases?.length ? (
            <section
              id="release-notes"
              className="mx-auto max-w-[1600px] border-t border-hair px-6 py-12 sm:px-10 lg:px-14"
            >
              <ReleaseHistory releases={macRelease.releases} />
            </section>
          ) : null}

          <section className="mx-auto max-w-[1600px] border-t border-hair px-6 py-10 sm:px-10 lg:px-14">
            <div className="flex flex-col gap-5 rounded-[18px] bg-ink px-6 py-6 text-paper sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="kicker text-paper/55">{t("install.kicker")}</p>
                <p className="mt-2 text-lg font-semibold">{t("install.text")}</p>
              </div>
              <Link
                to="/discover"
                className="inline-flex h-11 items-center justify-center rounded-full bg-paper px-5 text-sm font-semibold text-ink transition hover:bg-accent hover:text-white"
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

function DownloadStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-paper-2 px-5 py-4">
      <dt className="kicker text-[0.65rem]">{label}</dt>
      <dd className="mt-2 text-sm font-semibold text-ink">{value}</dd>
    </div>
  );
}

function QuickPoint({ icon, label, text }: { icon: ReactNode; label: string; text: string }) {
  return (
    <div className="flex gap-3">
      <span className="mt-1 flex h-9 w-9 flex-none items-center justify-center rounded-full border border-hair bg-paper-2 text-lg text-accent">
        {icon}
      </span>
      <div>
        <h3 className="text-sm font-semibold text-ink">{label}</h3>
        <p className="mt-1 text-xs leading-6 text-muted">{text}</p>
      </div>
    </div>
  );
}

function ClientCard({
  icon,
  eyebrow,
  title,
  text,
  version,
  requirement,
  updated,
  href,
  actionLabel,
  onDownload,
  tone,
}: {
  icon: ReactNode;
  eyebrow: string;
  title: string;
  text: string;
  version: string;
  requirement: string;
  updated: string;
  href?: string;
  actionLabel: string;
  onDownload?: () => void;
  tone: "accent" | "ink";
}) {
  const { t } = useTranslation("mac");
  const actionClass =
    tone === "accent"
      ? "bg-accent text-white shadow-[0_16px_38px_rgba(238,122,74,0.24)] hover:bg-accent-strong"
      : "bg-ink text-paper hover:bg-accent";

  return (
    <article className="flex min-h-[410px] flex-col rounded-[18px] border border-hair bg-paper p-5 shadow-[0_20px_70px_rgba(32,32,32,0.08)]">
      <div className="flex items-center justify-between gap-4">
        <div className="grid h-12 w-12 place-items-center rounded-[14px] bg-accent/10 text-2xl text-accent">
          {icon}
        </div>
        <span className="rounded-full border border-hair bg-paper-2 px-3 py-1 text-xs font-semibold text-muted">
          {version}
        </span>
      </div>

      <div className="mt-8">
        <p className="kicker">{eyebrow}</p>
        <h2 className="mt-3 text-2xl font-semibold tracking-normal text-ink">{title}</h2>
        <p className="mt-4 text-sm leading-7 text-muted">{text}</p>
      </div>

      <dl className="mt-7 grid gap-px overflow-hidden rounded-[12px] border border-hair bg-hair">
        <div className="bg-paper-2 px-4 py-3">
          <dt className="kicker text-[0.62rem]">{t("card.requirement")}</dt>
          <dd className="mt-1 text-sm font-semibold text-ink">{requirement}</dd>
        </div>
        <div className="bg-paper-2 px-4 py-3">
          <dt className="kicker text-[0.62rem]">{t("card.updated")}</dt>
          <dd className="mt-1 text-sm font-semibold text-ink">{updated}</dd>
        </div>
      </dl>

      <div className="mt-auto pt-7">
        {href ? (
          <a
            href={href}
            download
            onClick={onDownload}
            className={`inline-flex h-11 w-full items-center justify-center gap-2 rounded-full px-5 text-sm font-semibold transition hover:-translate-y-0.5 focus:outline-none focus:ring-2 focus:ring-accent/45 ${actionClass}`}
          >
            <AiOutlineDownload className="text-lg" />
            {actionLabel}
          </a>
        ) : (
          <button
            type="button"
            disabled
            className="inline-flex h-11 w-full cursor-not-allowed items-center justify-center rounded-full border border-hair bg-paper-2 px-5 text-sm font-semibold text-muted"
          >
            {actionLabel}
          </button>
        )}
      </div>
    </article>
  );
}

function IOSCard() {
  const { t } = useTranslation("mac");

  return (
    <article className="flex min-h-[410px] flex-col rounded-[18px] border border-hair bg-paper p-5 shadow-[0_20px_70px_rgba(32,32,32,0.08)]">
      <div className="flex items-center justify-between gap-4">
        <div className="grid h-12 w-12 place-items-center rounded-[14px] bg-accent/10 text-2xl text-accent">
          <AiOutlineMobile />
        </div>
        <span className="rounded-full border border-hair bg-paper-2 px-3 py-1 text-xs font-semibold text-muted">
          {t("status.comingSoon")}
        </span>
      </div>

      <div className="mt-8">
        <p className="kicker">{t("platforms.ios.eyebrow")}</p>
        <h2 className="mt-3 text-2xl font-semibold tracking-normal text-ink">{t("platforms.ios.title")}</h2>
        <p className="mt-4 text-sm leading-7 text-muted">{t("platforms.ios.text")}</p>
      </div>

      <div className="mt-7 grid flex-1 place-items-center rounded-[16px] border border-dashed border-hair bg-paper-2 px-5 py-7">
        <div className="grid h-32 w-32 place-items-center rounded-[18px] border border-hair bg-paper text-accent">
          <AiOutlineQrcode className="text-5xl" />
        </div>
        <p className="mt-4 text-center text-xs font-semibold uppercase tracking-[0.14em] text-muted">
          {t("platforms.ios.qrPlaceholder")}
        </p>
      </div>
    </article>
  );
}

function ReleasePanel({
  icon,
  title,
  version,
  date,
  notes,
  emptyText,
  href,
  actionLabel,
  onDownload,
  footer,
}: {
  icon: ReactNode;
  title: string;
  version: string;
  date: string;
  notes: string[];
  emptyText: string;
  href?: string;
  actionLabel: string;
  onDownload?: () => void;
  footer?: string;
}) {
  return (
    <article className="rounded-[18px] border border-hair bg-paper p-6">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-hair pb-4">
        <div className="flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-[12px] bg-accent/10 text-xl text-accent">
            {icon}
          </span>
          <div>
            <h3 className="text-lg font-semibold text-ink">{title}</h3>
            <p className="mt-1 text-sm text-muted">{date}</p>
          </div>
        </div>
        <span className="rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold text-accent">
          {version}
        </span>
      </div>

      {notes.length ? (
        <ul className="mt-5 grid gap-3">
          {notes.map((note, index) => (
            <li key={`${note}-${index}`} className="flex gap-3 text-sm leading-7 text-ink">
              <span className="mt-2 h-1.5 w-1.5 flex-none rounded-full bg-accent" />
              <span>{note}</span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-5 text-sm leading-7 text-muted">{emptyText}</p>
      )}

      <div className="mt-6 flex flex-col gap-3 border-t border-hair pt-5 sm:flex-row sm:items-center sm:justify-between">
        {footer ? <p className="font-mono text-xs text-muted">{footer}</p> : <span />}
        {href ? (
          <a
            href={href}
            download
            onClick={onDownload}
            className="inline-flex h-10 items-center justify-center gap-2 rounded-full bg-ink px-4 text-sm font-semibold text-paper transition hover:bg-accent"
          >
            <AiOutlineDownload className="text-lg" />
            {actionLabel}
          </a>
        ) : null}
      </div>
    </article>
  );
}

function ReleaseHistory({ releases }: { releases: MacReleaseEntry[] }) {
  const { t, i18n } = useTranslation("mac");

  return (
    <div className="rounded-[18px] border border-hair bg-paper p-6">
      <div className="label-rule">
        <span>{t("release.changelog")}</span>
        <span>{t("release.buildCount", { num: releases.length })}</span>
      </div>
      <ol className="mt-5 divide-y divide-hair">
        {releases.slice(0, 5).map((entry) => (
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
    </div>
  );
}

function DownloadSkeleton() {
  return (
    <div className="grid gap-4 xl:grid-cols-3">
      {[0, 1, 2].map((item) => (
        <div key={item} className="min-h-[410px] animate-pulse rounded-[18px] border border-hair bg-paper p-5">
          <div className="flex justify-between">
            <div className="h-12 w-12 rounded-[14px] bg-hair/70" />
            <div className="h-7 w-20 rounded-full bg-hair/60" />
          </div>
          <div className="mt-10 h-3 w-24 rounded-full bg-hair/70" />
          <div className="mt-5 h-8 w-36 rounded-full bg-hair/70" />
          <div className="mt-5 h-20 rounded-[12px] bg-hair/50" />
          <div className="mt-8 h-24 rounded-[12px] bg-hair/50" />
          <div className="mt-8 h-11 rounded-full bg-hair/70" />
        </div>
      ))}
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
