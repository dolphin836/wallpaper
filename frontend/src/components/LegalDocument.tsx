import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { AiOutlineArrowRight } from 'react-icons/ai';

export interface LegalSection {
  /** Mono section number, e.g. "01". */
  id: string;
  /** Display heading text (sans 30px). */
  h: string;
  /** Paragraphs. Strings are rendered as <p>; React nodes are passed through. */
  ps: (string | React.ReactNode)[];
}

export interface LegalDoc {
  title: string;        // e.g. "Terms"
  italicTail: string;   // e.g. "of service" — rendered italic after the title
  updated: string;      // e.g. "May 12, 2026"
  version: string;      // e.g. "v3.2"
  /** TOC labels. The first matching prefix (e.g. "01") binds to a section. */
  toc: string[];
  body: LegalSection[];
}

interface Props {
  doc: LegalDoc;
  /** Path of this document — used to mark "CURRENT" in the See-also list. */
  currentPath: '/terms' | '/privacy' | '/legal/dmca';
}

// `nameKey` is an i18n key in the `about` namespace, resolved at render time.
const RELATED: Array<{ nameKey: string; path: '/terms' | '/privacy' | '/legal/dmca' }> = [
  { nameKey: 'legal.termsName',   path: '/terms' },
  { nameKey: 'legal.privacyName', path: '/privacy' },
  { nameKey: 'legal.dmcaName',    path: '/legal/dmca' },
];

/**
 * Shared editorial template for Terms / Privacy / DMCA — TOC sidebar on the
 * left + title spread + mono-numbered, hairline-indented section body on
 * the right. Each page passes its own `LegalDoc` data; nothing here is
 * document-specific.
 */
export default function LegalDocument({ doc, currentPath }: Props) {
  const { t } = useTranslation('about');
  // Map TOC labels to anchor targets by stripping " · …" / lowering. Used
  // when the TOC links jump to the matching <section id=...>.
  const slugFor = (label: string) => label.toLowerCase().replace(/^\d+\s*·\s*/, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

  return (
    <div className="legal-page min-h-full">
      <div className="legal-mesh" aria-hidden />
      <div className="relative z-10 grid grid-cols-1 lg:grid-cols-[240px_1fr] gap-8 lg:gap-14 max-w-[1280px] mx-auto px-6 sm:px-10 lg:px-14 py-12">
        {/* TOC sidebar */}
        <aside className="hidden lg:block">
          <div className="kicker text-muted">{t('legal.articles', { num: doc.toc.length })}</div>
          <ul className="list-none p-0 mt-3 mono text-[11px] tracking-[0.04em] border-t border-hair">
            {doc.toc.map((label, i) => {
              const num = label.match(/^\d+/)?.[0] ?? null;
              const matched = num ? doc.body.find((b) => b.id === num) : null;
              const targetId = matched ? slugFor(matched.h) : null;
              const active = i === 0; // visually mark first article (single-page docs)
              return (
                <li
                  key={label}
                  className="flex justify-between items-baseline py-2.5 border-b border-hair"
                  style={{ color: active ? 'var(--color-ink)' : 'var(--color-ink-2)' }}
                >
                  {targetId ? (
                    <a href={`#${targetId}`} className="no-underline text-inherit hover:text-ink">
                      {label}
                    </a>
                  ) : (
                    <span>{label}</span>
                  )}
                  {active && <span className="text-accent">●</span>}
                </li>
              );
            })}
          </ul>

          <div className="mt-7">
            <div className="kicker text-muted">{t('legal.seeAlso')}</div>
            <ul className="list-none p-0 mt-2.5 text-[13px]">
              {RELATED.map((r) => {
                const isCurrent = r.path === currentPath;
                return (
                  <li
                    key={r.path}
                    className="flex items-center justify-between py-2 border-b border-hair"
                    style={{ color: isCurrent ? 'var(--color-ink)' : 'var(--color-ink-2)' }}
                  >
                    {isCurrent ? (
                      <>
                        <span>{t(r.nameKey)}</span>
                        <span className="mono text-[10px] text-accent tracking-[0.1em]">{t('legal.current')}</span>
                      </>
                    ) : (
                      <Link to={r.path} className="flex w-full items-center justify-between text-inherit no-underline hover:text-ink">
                        <span>{t(r.nameKey)}</span>
                        <AiOutlineArrowRight size={11} />
                      </Link>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>
        </aside>

        {/* Body */}
        <article className="min-w-0">
          <div className="flex justify-between items-baseline border-b border-hair pb-4 gap-4 flex-wrap">
            <div>
              <div className="kicker text-muted">{t('legal.kicker', { version: doc.version })}</div>
              <h1 className="display text-[44px] sm:text-[60px] lg:text-[76px] leading-[0.95] tracking-[-0.015em] mt-2 text-ink">
                {doc.title} <span className="legal-title-tail">{doc.italicTail}.</span>
              </h1>
            </div>
            <div className="text-right mono text-[11px] text-muted tracking-[0.06em]">
              <div>{t('legal.lastUpdated')}</div>
              <div className="text-ink mt-1">{doc.updated.toUpperCase()}</div>
            </div>
          </div>

          <div className="mt-6 max-w-[720px]">
            {doc.body.map((section) => (
              <section
                key={section.id}
                id={slugFor(section.h)}
                className="mb-8 scroll-mt-24"
              >
                <div className="flex items-baseline gap-3">
                  <span className="mono text-[11px] tracking-[0.14em] text-muted pt-1">
                    {section.id}
                  </span>
                  <h2 className="display text-[26px] sm:text-[30px] leading-tight tracking-[-0.01em] m-0">
                    {section.h}
                  </h2>
                </div>
                <div className="mt-2.5 pl-8 border-l border-hair">
                  {section.ps.map((p, j) => (
                    <p
                      key={j}
                      className="text-[14px] leading-[1.6] text-ink-2"
                      style={{ marginTop: j === 0 ? 0 : 12, textWrap: 'pretty' as React.CSSProperties['textWrap'] }}
                    >
                      {p}
                    </p>
                  ))}
                </div>
              </section>
            ))}
          </div>
        </article>
      </div>
    </div>
  );
}
