import { useEffect, useMemo, useState, type ReactNode } from "react";
import {
  AiOutlineApple,
  AiOutlineDownload,
  AiOutlineMenu,
  AiOutlineSync,
  AiOutlineThunderbolt,
} from "react-icons/ai";
import { BiCollection } from "react-icons/bi";
import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { getMacRelease } from "../api";
import type { MacRelease, MacReleaseEntry } from "../types";
import PageMeta from "../components/PageMeta";

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

function latestNotes(release: MacRelease) {
  return release.releases?.[0]?.notes?.filter(Boolean).slice(0, 4) ?? [];
}

export default function DownloadMacPage() {
  const { t } = useTranslation("mac");
  const [release, setRelease] = useState<MacRelease | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getMacRelease()
      .then((res) => {
        if (!cancelled) {
          setRelease(res.data.data);
          setError(null);
        }
      })
      .catch((err) => {
        // Empty string = generic failure; the render path falls back to the
        // localized error.loadFailed copy.
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "");
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const currentVersion = release?.current_version ?? "2.0";
  const minimumMacOS = release?.min_macos_version ?? DEFAULT_MACOS_VERSION;
  const currentRelease = release?.releases?.[0];
  const notes = useMemo(() => (release ? latestNotes(release) : []), [release]);

  return (
    <main className="min-h-full bg-paper text-ink">
      <PageMeta
        title={t("meta.title")}
        description={t("meta.description")}
      />

      <section className="relative isolate overflow-hidden border-b border-hair">
        <div
          className="pointer-events-none absolute inset-0 -z-10 opacity-80"
          style={{
            background:
              "radial-gradient(circle at 18% 14%, rgba(238, 122, 74, 0.2), transparent 34%), radial-gradient(circle at 82% 10%, rgba(79, 129, 190, 0.14), transparent 28%), linear-gradient(180deg, var(--color-paper), var(--color-paper-2))",
          }}
        />

        <div className="mx-auto grid max-w-[1600px] gap-10 px-6 py-8 sm:px-10 lg:grid-cols-[minmax(340px,0.78fr)_minmax(560px,1.22fr)] lg:px-14 lg:py-12">
          {loading ? (
            <DownloadMacSkeleton />
          ) : error || !release ? (
            <DownloadMacError message={error || t("error.loadFailed")} />
          ) : (
            <>
              <div className="flex min-h-[620px] flex-col justify-between">
                <div>
                  <div className="label-rule">
                    <span>{t("hero.label")}</span>
                    <span>v{currentVersion}</span>
                  </div>

                  <div className="mt-10 max-w-[640px]">
                    <p className="kicker">{t("hero.kicker")}</p>
                    <h1 className="display mt-4 text-[3.4rem] leading-[0.96] sm:text-[5.6rem] lg:text-[6.6rem]">
                      {t("hero.title")}
                    </h1>
                    <p className="mt-6 max-w-xl text-base leading-8 text-muted sm:text-lg">
                      {t("hero.subtitle")}
                    </p>
                  </div>

                  <div className="mt-8 flex flex-wrap items-center gap-3">
                    <a
                      href={release.current_dmg_url}
                      download
                      className="inline-flex h-12 items-center gap-3 rounded-full bg-accent px-6 text-sm font-semibold text-white shadow-[0_16px_38px_rgba(238,122,74,0.26)] transition hover:-translate-y-0.5 hover:bg-accent-strong focus:outline-none focus:ring-2 focus:ring-accent/45"
                    >
                      <AiOutlineApple className="text-xl" />
                      {t("hero.downloadDmg")}
                    </a>
                    <a
                      href="#release-notes"
                      className="inline-flex h-12 items-center gap-2 rounded-full border border-hair bg-paper/75 px-5 text-sm font-semibold text-ink transition hover:border-accent/45 hover:text-accent"
                    >
                      <AiOutlineMenu className="text-lg" />
                      {t("hero.releaseNotes")}
                    </a>
                  </div>

                  <dl className="mt-8 grid max-w-2xl grid-cols-1 gap-px overflow-hidden rounded-[14px] border border-hair bg-hair sm:grid-cols-3">
                    <DownloadStat label={t("hero.statVersion")} value={`v${currentVersion}`} />
                    <DownloadStat label={t("hero.statRequires")} value={`macOS ${minimumMacOS}+`} />
                    <DownloadStat label={t("hero.statUpdated")} value={formatReleaseDate(currentRelease?.released_at, t("release.latest"))} />
                  </dl>
                </div>

                <div className="mt-10 grid gap-4 border-t border-hair pt-6 sm:grid-cols-3">
                  <QuickPoint icon={<AiOutlineDownload />} label={t("quick.originalsLabel")} text={t("quick.originalsText")} />
                  <QuickPoint icon={<AiOutlineSync />} label={t("quick.rotationLabel")} text={t("quick.rotationText")} />
                  <QuickPoint icon={<BiCollection />} label={t("quick.libraryLabel")} text={t("quick.libraryText")} />
                </div>
              </div>

              <div className="relative flex min-h-[620px] items-center">
                <MacAppPreview version={currentVersion} />
              </div>
            </>
          )}
        </div>
      </section>

      {release ? (
        <>
          <section className="mx-auto grid max-w-[1600px] gap-8 px-6 py-12 sm:px-10 lg:grid-cols-[0.95fr_1.05fr] lg:px-14">
            <div className="border-t border-hair pt-6">
              <p className="kicker">{t("why.kicker")}</p>
              <h2 className="display mt-4 max-w-2xl text-[2.7rem] leading-none sm:text-[4.5rem]">
                {t("why.title")}
              </h2>
            </div>

            <div className="grid gap-px overflow-hidden rounded-[18px] border border-hair bg-hair sm:grid-cols-2">
              <FeatureTile
                icon={<AiOutlineApple />}
                title={t("why.macosTitle")}
                text={t("why.macosText")}
              />
              <FeatureTile
                icon={<AiOutlineThunderbolt />}
                title={t("why.browsingTitle")}
                text={t("why.browsingText")}
              />
              <FeatureTile
                icon={<AiOutlineSync />}
                title={t("why.displaysTitle")}
                text={t("why.displaysText")}
              />
              <FeatureTile
                icon={<BiCollection />}
                title={t("why.libraryTitle")}
                text={t("why.libraryText")}
              />
            </div>
          </section>

          <section
            id="release-notes"
            className="mx-auto grid max-w-[1600px] gap-8 border-t border-hair px-6 py-12 sm:px-10 lg:grid-cols-[0.76fr_1.24fr] lg:px-14"
          >
            <div>
              <p className="kicker">{t("release.currentBuild")}</p>
              <h2 className="display mt-4 text-[2.7rem] leading-none sm:text-[4.1rem]">v{currentVersion}</h2>
              <p className="mt-5 max-w-md text-sm leading-7 text-muted">
                {t("release.pointsToLatest")}
              </p>
              <a
                href={release.current_dmg_url}
                download
                className="mt-7 inline-flex h-11 items-center gap-2 rounded-full bg-ink px-5 text-sm font-semibold text-paper transition hover:bg-accent"
              >
                <AiOutlineDownload className="text-lg" />
                {t("release.downloadLatest")}
              </a>
            </div>

            <div className="grid gap-6">
              <div className="rounded-[18px] border border-hair bg-paper-2/80 p-6">
                <div className="flex flex-wrap items-center justify-between gap-3 border-b border-hair pb-4">
                  <div>
                    <p className="kicker">{t("release.latestNotes")}</p>
                    <p className="mt-2 text-sm text-muted">{formatReleaseDate(currentRelease?.released_at, t("release.latest"))}</p>
                  </div>
                  <span className="rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold text-accent">
                    v{currentVersion}
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
                  <p className="mt-5 text-sm leading-7 text-muted">{t("release.noNotes")}</p>
                )}
              </div>

              <ReleaseHistory releases={release.releases ?? []} />
            </div>
          </section>

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

function FeatureTile({ icon, title, text }: { icon: ReactNode; title: string; text: string }) {
  return (
    <article className="min-h-[210px] bg-paper px-6 py-6">
      <div className="flex h-11 w-11 items-center justify-center rounded-full bg-accent/10 text-xl text-accent">
        {icon}
      </div>
      <h3 className="mt-8 text-lg font-semibold text-ink">{title}</h3>
      <p className="mt-3 text-sm leading-7 text-muted">{text}</p>
    </article>
  );
}

function ReleaseHistory({ releases }: { releases: MacReleaseEntry[] }) {
  const { t } = useTranslation("mac");
  if (!releases.length) {
    return null;
  }

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
              {(entry.notes ?? []).slice(0, 3).map((note, index) => (
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

function MacAppPreview({ version }: { version: string }) {
  const swatches = ["#ee7a4a", "#202020", "#5374a3", "#e9b15d", "#8b2740"];

  return (
    <div className="w-full">
      <div className="relative overflow-hidden rounded-[24px] border border-hair bg-paper shadow-[0_28px_90px_rgba(32,32,32,0.16)]">
        <div className="flex h-12 items-center justify-between border-b border-hair bg-paper-2 px-5">
          <div className="flex items-center gap-2">
            <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
            <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
            <span className="h-3 w-3 rounded-full bg-[#28c840]" />
          </div>
          <span className="rounded-full border border-hair bg-paper px-3 py-1 text-xs font-semibold text-muted">
            v{version}
          </span>
        </div>

        <div className="grid min-h-[560px] grid-cols-[180px_1fr] bg-paper">
          <aside className="border-r border-hair bg-paper-2/72 p-5">
            <div className="flex items-center gap-3">
              <div className="grid h-9 w-9 place-items-center rounded-[10px] bg-accent/14 text-accent">
                <AiOutlineApple />
              </div>
              <div>
                <p className="font-serif text-lg font-semibold leading-none">Wallpaper</p>
                <p className="mt-1 text-[0.62rem] font-bold uppercase text-muted">Exchange</p>
              </div>
            </div>

            <nav className="mt-9 grid gap-2 text-sm">
              {["Home", "Discover", "Weekly", "Collections"].map((item, index) => (
                <span
                  key={item}
                  className={[
                    "rounded-[8px] px-3 py-2 font-semibold",
                    index === 1 ? "bg-accent/12 text-accent" : "text-muted",
                  ].join(" ")}
                >
                  {item}
                </span>
              ))}
            </nav>

            <div className="absolute bottom-5 left-5 right-[calc(100%-180px+20px)] rounded-full border border-hair bg-paper px-4 py-3 text-center text-xs font-bold text-ink shadow-sm">
              740 coins
            </div>
          </aside>

          <div className="relative overflow-hidden p-6">
            <div
              className="absolute inset-0 opacity-90"
              style={{
                background:
                  "radial-gradient(circle at 30% 20%, rgba(238,122,74,0.28), transparent 36%), radial-gradient(circle at 78% 72%, rgba(80,115,160,0.24), transparent 32%), linear-gradient(135deg, rgba(250,244,235,0.95), rgba(230,236,238,0.95))",
              }}
            />
            <div className="relative flex items-center justify-between gap-4">
              <div className="flex gap-2">
                {["All", "Nature", "City", "Space"].map((item, index) => (
                  <span
                    key={item}
                    className={[
                      "rounded-full px-4 py-2 text-xs font-semibold",
                      index === 0 ? "bg-ink text-paper" : "bg-paper/88 text-ink",
                    ].join(" ")}
                  >
                    {item}
                  </span>
                ))}
              </div>
              <span className="rounded-full bg-paper/88 px-4 py-2 text-xs font-semibold text-muted">Latest</span>
            </div>

            <div className="relative mx-auto mt-8 max-w-[650px] rounded-[28px] border border-white/35 bg-paper/30 px-10 py-9 shadow-[inset_0_1px_0_rgba(255,255,255,0.5)]">
              <div className="mx-auto aspect-[16/9] max-w-[500px] overflow-hidden rounded-[18px] border-[8px] border-ink bg-ink shadow-[0_26px_60px_rgba(32,32,32,0.22)]">
                <div
                  className="h-full w-full"
                  style={{
                    background:
                      "radial-gradient(circle at 74% 24%, rgba(255,220,132,0.92), transparent 18%), linear-gradient(140deg, #090909 0%, #182f48 42%, #f47a29 43%, #f7c477 62%, #16110d 100%)",
                  }}
                />
              </div>
              <div className="mx-auto h-12 w-28 bg-gradient-to-b from-ink/55 to-ink/35" />
              <div className="mx-auto h-2 w-56 rounded-full bg-ink/42" />
              <div className="mx-auto mt-6 grid w-[280px] grid-cols-3 rounded-full border border-white/60 bg-paper/70 p-1 text-center text-xs font-bold uppercase text-muted">
                <span className="rounded-full bg-ink px-3 py-2 text-paper">Plain</span>
                <span className="px-3 py-2">Home</span>
                <span className="px-3 py-2">Lock</span>
              </div>
            </div>

            <div className="relative mt-6 grid grid-cols-3 gap-4">
              {swatches.map((color, index) => (
                <div
                  key={color}
                  className="aspect-[16/10] overflow-hidden rounded-[10px] border border-white/55 bg-ink shadow-sm"
                  style={{
                    background:
                      index % 2 === 0
                        ? `linear-gradient(135deg, ${color}, #101010 72%)`
                        : `radial-gradient(circle at 70% 30%, ${color}, #101010 65%)`,
                  }}
                >
                  <span className="m-2 inline-flex rounded-full bg-paper/78 px-2 py-0.5 text-[0.65rem] font-bold text-ink">
                    {index === 2 ? "8K" : "4K"}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function DownloadMacSkeleton() {
  return (
    <>
      <div className="min-h-[620px] animate-pulse">
        <div className="h-4 w-full rounded-full bg-hair/70" />
        <div className="mt-12 h-3 w-44 rounded-full bg-hair/70" />
        <div className="mt-5 h-20 w-11/12 rounded-[18px] bg-hair/70" />
        <div className="mt-3 h-20 w-3/4 rounded-[18px] bg-hair/60" />
        <div className="mt-7 h-5 w-3/4 rounded-full bg-hair/60" />
        <div className="mt-10 flex gap-3">
          <div className="h-12 w-40 rounded-full bg-hair/70" />
          <div className="h-12 w-36 rounded-full bg-hair/60" />
        </div>
        <div className="mt-9 grid grid-cols-3 gap-px overflow-hidden rounded-[14px] border border-hair bg-hair">
          <div className="h-24 bg-paper-2" />
          <div className="h-24 bg-paper-2" />
          <div className="h-24 bg-paper-2" />
        </div>
      </div>
      <div className="min-h-[620px] animate-pulse rounded-[24px] border border-hair bg-paper-2" />
    </>
  );
}

function DownloadMacError({ message }: { message: string }) {
  const { t } = useTranslation("mac");
  return (
    <div className="lg:col-span-2">
      <div className="mx-auto max-w-2xl rounded-[20px] border border-hair bg-paper px-6 py-10 text-center shadow-sm">
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
    </div>
  );
}
