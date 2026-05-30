/* Standalone mockup gallery — three direction proposals for the
   wallpaper-detail page, viewable side-by-side via a simple
   header switcher. No API wiring, no real download — purely a
   visual sandbox so we can pick a direction before rebuilding
   the actual page. Mounted at /dev/wp-detail (see App.tsx). */
import { useState } from 'react';
import {
  AiOutlineHeart, AiFillHeart,
  AiOutlineStar,
  AiOutlineDownload, AiOutlineFullscreen,
  AiOutlineClose, AiOutlineFlag,
} from 'react-icons/ai';
import { MdDesktopMac, MdLaptopMac, MdPhoneIphone, MdTabletMac, MdPlaylistAdd } from 'react-icons/md';

type Variant = 'studio' | 'spotlight' | 'card';

const SAMPLE = {
  id: 42,
  title: 'Misty Pine Forest on Mountain Slopes',
  width: 3840,
  height: 2160,
  fileSize: '2.3 MB',
  fileType: 'PNG',
  category: 'Nature',
  tags: ['nature', 'forest', 'mountain', 'mist', 'serenity'],
  addedDaysAgo: 5,
  dominantColor: 'oklch(45% 0.08 165)',
  palette: [
    'oklch(28% 0.04 165)',
    'oklch(45% 0.08 165)',
    'oklch(62% 0.10 145)',
    'oklch(82% 0.06 105)',
    'oklch(94% 0.03 85)',
  ],
  hero:
    'https://wallpaper.haibing.site/storage/wallpapers/previews/f8f15fe9-986e-4c3a-a99f-a5d787ca313c.webp',
  uploader: {
    username: 'forest_walker',
    nickname: 'Forest Walker',
    bio: 'Nature photographer · Pacific NW',
    avatar: '',
  },
  stats: { downloads: 142, likes: 88, favorites: 24, views: 1240 },
  isDynamic: true,
  isAI: false,
  resLabel: '4K',
  variants: [
    { id: 1, icon: 'desktop' as const, name: 'MacBook Pro 14"', w: 3024, h: 1964, size: '2.0 MB', matched: true },
    { id: 2, icon: 'phone' as const, name: 'iPhone 16 Pro', w: 1290, h: 2796, size: '1.1 MB', matched: false },
    { id: 3, icon: 'tablet' as const, name: 'iPad Pro 13"', w: 2752, h: 2064, size: '1.6 MB', matched: false },
    { id: 4, icon: 'desktop' as const, name: '5K iMac', w: 5120, h: 2880, size: '3.4 MB', matched: false },
  ],
  cost: 1,
  userCoins: 124,
};

function PlatformIcon({ icon, size = 18 }: { icon: 'desktop' | 'laptop' | 'phone' | 'tablet'; size?: number }) {
  const C = icon === 'phone' ? MdPhoneIphone
    : icon === 'tablet' ? MdTabletMac
    : icon === 'laptop' ? MdLaptopMac
    : MdDesktopMac;
  return <C size={size} />;
}

export default function WallpaperDetailPreviewPage() {
  const [variant, setVariant] = useState<Variant>('studio');
  return (
    <div className="bg-paper text-ink min-h-screen">
      <Switcher current={variant} onChange={setVariant} />
      <div className="max-w-[1600px] mx-auto px-6 sm:px-10 py-6">
        {variant === 'studio' && <StudioLayout />}
        {variant === 'spotlight' && <SpotlightLayout />}
        {variant === 'card' && <IndexCardLayout />}
      </div>
    </div>
  );
}

function Switcher({ current, onChange }: { current: Variant; onChange: (v: Variant) => void }) {
  const opts: { key: Variant; label: string; sub: string }[] = [
    { key: 'studio',    label: 'Studio',     sub: '大图左 · 玻璃 inspector 右' },
    { key: 'spotlight', label: 'Spotlight',  sub: '图居中 · 底部 dock' },
    { key: 'card',      label: 'Index Card', sub: '编辑刊 · 三栏' },
  ];
  return (
    <div className="sticky top-0 z-50 border-b border-hair bg-paper/90 backdrop-blur">
      <div className="max-w-[1600px] mx-auto px-6 sm:px-10 py-3 flex items-center gap-6 flex-wrap">
        <div className="kicker text-muted">Mockup · Wallpaper detail · dev preview</div>
        <div className="flex gap-2 items-center ml-auto flex-wrap">
          {opts.map((o) => (
            <button
              key={o.key}
              onClick={() => onChange(o.key)}
              className={`inline-flex flex-col items-start gap-0 px-3.5 py-1.5 rounded-lg text-[12px] font-medium border transition-colors ${
                current === o.key
                  ? 'bg-ink text-paper border-ink'
                  : 'bg-paper text-ink border-hair hover:border-ink-2'
              }`}
            >
              <span className="text-[13px] leading-tight">{o.label}</span>
              <span className={`mono text-[9px] tracking-[0.04em] mt-0.5 ${current === o.key ? 'text-paper/70' : 'text-muted'}`}>{o.sub}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ─── DESIGN 1 — STUDIO ────────────────────────────────────────
   Big hero left (60%), glass inspector right (40%) with all
   metadata + sticky CTA at the bottom. Similar information
   density to the current page but with the Liquid Surface
   chrome (mesh bg, glass cards, integer stats, accent CTA). */
function StudioLayout() {
  return (
    <div className="relative">
      <div className="studio-mesh" aria-hidden style={meshStyle()} />
      <div className="relative z-10 grid grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-8">
        {/* LEFT — hero */}
        <div className="min-w-0">
          <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted flex justify-between mb-3">
            <span>Plate № {String(SAMPLE.id).padStart(3, '0')}</span>
            <span>{SAMPLE.width.toLocaleString()} × {SAMPLE.height.toLocaleString()} · {SAMPLE.resLabel}</span>
          </div>
          <div className="studio-hero" style={{ aspectRatio: '16/9', backgroundColor: SAMPLE.dominantColor }}>
            <img src={SAMPLE.hero} alt={SAMPLE.title} draggable={false} />
            <button className="studio-hero-fs"><AiOutlineFullscreen size={14} /> Fullscreen</button>
            {SAMPLE.isDynamic && <span className="studio-hero-pill">● Dynamic · PLAY 1/4</span>}
          </div>
          <div className="studio-stats">
            {[['Downloads', SAMPLE.stats.downloads], ['Likes', SAMPLE.stats.likes], ['Favorited', SAMPLE.stats.favorites], ['Views', SAMPLE.stats.views]].map(([k, v]) => (
              <div key={k as string} className="studio-stat">
                <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted">{k}</div>
                <div className="display text-[22px] leading-none mt-1">{fmtN(v as number)}</div>
                <div className="flex mt-2 -space-x-1.5">
                  {[0, 1, 2].map((j) => <span key={j} className="w-[18px] h-[18px] rounded-full border border-paper bg-paper-2" />)}
                </div>
              </div>
            ))}
          </div>

          <div className="label-rule mt-7 mb-3">More like this · 8</div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="dev-spec-card" style={{ aspectRatio: '3/2' }}>
                <div className="dev-spec-card-screen" style={{ aspectRatio: '3/2', background: 'var(--color-paper-2)' }} />
              </div>
            ))}
          </div>
        </div>

        {/* RIGHT — inspector */}
        <aside className="min-w-0">
          <div className="studio-inspector">
            <div className="kicker text-muted">{SAMPLE.category} · Added {SAMPLE.addedDaysAgo}d ago {SAMPLE.isDynamic && '· DYNAMIC'}</div>
            <h1 className="display text-[clamp(26px,2.6vw,32px)] leading-[1.05] mt-1 tracking-[-0.012em]">
              {SAMPLE.title}
            </h1>

            {/* Uploader card */}
            <a className="studio-uploader mt-4">
              <div className="studio-uploader-avatar">{SAMPLE.uploader.nickname[0]}</div>
              <div className="min-w-0 flex-1">
                <div className="text-[14px] font-medium leading-tight">@{SAMPLE.uploader.username}</div>
                <div className="mono text-[10px] tracking-[0.05em] text-muted truncate mt-0.5">{SAMPLE.uploader.bio}</div>
              </div>
              <span className="mono text-[10px] tracking-[0.14em] text-muted whitespace-nowrap">VIEW →</span>
            </a>

            {/* Palette */}
            <div className="mt-5">
              <div className="kicker text-muted">Palette · click to copy</div>
              <div className="grid mt-2 gap-1.5" style={{ gridTemplateColumns: `repeat(${SAMPLE.palette.length}, 1fr)` }}>
                {SAMPLE.palette.map((c, i) => (
                  <div key={i} className="rounded-md h-9" style={{ background: c, boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.3)' }} />
                ))}
              </div>
            </div>

            {/* Specs grid */}
            <div className="studio-specs mt-5">
              <div><span className="kicker text-muted">Dim</span><div className="mt-1 text-[13px] mono">{SAMPLE.width}×{SAMPLE.height}px</div></div>
              <div><span className="kicker text-muted">Res</span><div className="mt-1 text-[13px] mono">{SAMPLE.resLabel}</div></div>
              <div><span className="kicker text-muted">File</span><div className="mt-1 text-[13px] mono">{SAMPLE.fileType} · {SAMPLE.fileSize}</div></div>
              <div><span className="kicker text-muted">Category</span><div className="mt-1 text-[13px]">{SAMPLE.category}</div></div>
            </div>

            {/* Secondary actions */}
            <div className="grid grid-cols-3 gap-2 mt-5">
              <button className="btn-pill is-liked"><AiFillHeart size={15} /><span className="label">Liked</span></button>
              <button className="btn-pill"><AiOutlineStar size={15} /><span className="label">Favorite</span></button>
              <button className="btn-pill"><MdPlaylistAdd size={17} /><span className="label">Add to list</span></button>
            </div>

            {/* Variants drawer */}
            <div className="mt-5">
              <div className="kicker text-muted flex items-center justify-between">
                <span>Available devices · 12</span>
                <span className="mono text-[10px] text-muted normal-case">collapse ▾</span>
              </div>
              <div className="studio-variants mt-2">
                {SAMPLE.variants.slice(0, 3).map((v) => (
                  <div key={v.id} className={`studio-variant-row ${v.matched ? 'is-matched' : ''}`}>
                    <PlatformIcon icon={v.icon} />
                    <div className="min-w-0">
                      <div className="text-[13px] truncate">{v.name} {v.matched && <span className="ml-1.5 mono text-[9px] tracking-[0.12em] px-1.5 py-[1px] bg-ink text-paper rounded">YOUR DEVICE</span>}</div>
                      <div className="mono text-[10px] text-muted mt-0.5">{v.w}×{v.h} · {v.size}</div>
                    </div>
                    <button className={`mono text-[10px] tracking-[0.1em] px-2.5 py-1 rounded-full text-paper ${v.matched ? 'bg-accent' : 'bg-ink'}`}>↓</button>
                  </div>
                ))}
              </div>
            </div>

            {/* Sticky CTA */}
            <div className="studio-cta-wrap mt-5">
              <div className="flex-1 min-w-0">
                <div className="kicker text-paper/55">Exchange for</div>
                <div className="display text-[30px] leading-none mt-1">
                  {SAMPLE.cost} <span className="text-accent">coin</span>
                </div>
                <div className="mono text-[10px] tracking-[0.14em] text-paper/55 mt-1.5">YOUR BALANCE · {SAMPLE.userCoins} COINS</div>
              </div>
              <button className="studio-cta-btn">
                <span className="balance-pill__coin" aria-hidden />
                Trade for {SAMPLE.cost}
              </button>
            </div>

            <div className="flex justify-between items-center mt-4 text-[11px] text-muted">
              <button className="inline-flex items-center gap-1.5 hover:text-ink"><AiOutlineFlag size={13} /> Report</button>
              <span className="mono text-[10px] tracking-[0.14em]">№ {String(SAMPLE.id).padStart(3, '0')}</span>
            </div>
          </div>
        </aside>
      </div>
      <StudioCSS />
    </div>
  );
}

/* ─── DESIGN 2 — SPOTLIGHT ─────────────────────────────────────
   Image centred on dominant-color mesh. All controls in a
   floating glass dock at the bottom: download CTA + like + fav +
   palette swatches + variants horizontal carousel. Specs in a
   small floating tag at the top-right. */
function SpotlightLayout() {
  return (
    <div className="relative spotlight-stage" style={{ background: `linear-gradient(135deg, ${SAMPLE.dominantColor}, var(--color-paper))` }}>
      {/* Top corners */}
      <div className="spotlight-corners">
        <div className="kicker text-paper/80">{SAMPLE.category} · added {SAMPLE.addedDaysAgo}d ago</div>
        <div className="spotlight-specs">
          <div>
            <div className="display text-[22px] leading-none">{SAMPLE.width}<span className="text-paper/55"> × </span>{SAMPLE.height}</div>
            <div className="mono text-[10px] tracking-[0.14em] text-paper/70 mt-1">{SAMPLE.resLabel} · {SAMPLE.fileType} · {SAMPLE.fileSize}{SAMPLE.isDynamic && ' · DYNAMIC'}</div>
          </div>
          <button className="text-paper/80 hover:text-paper p-2"><AiOutlineClose size={18} /></button>
        </div>
      </div>

      {/* Hero */}
      <div className="spotlight-hero" style={{ aspectRatio: '16/9' }}>
        <img src={SAMPLE.hero} alt={SAMPLE.title} draggable={false} />
        <h1 className="spotlight-title">{SAMPLE.title}</h1>
        <button className="spotlight-fs"><AiOutlineFullscreen size={14} /> Fullscreen</button>
      </div>

      {/* Floating dock */}
      <div className="spotlight-dock">
        <div className="spotlight-dock-uploader">
          <div className="w-9 h-9 rounded-full bg-paper-2 border border-hair flex items-center justify-center text-[14px] font-medium">{SAMPLE.uploader.nickname[0]}</div>
          <div className="min-w-0">
            <div className="text-[13px] font-medium leading-tight truncate">@{SAMPLE.uploader.username}</div>
            <div className="mono text-[10px] text-muted">{SAMPLE.uploader.bio}</div>
          </div>
        </div>

        <div className="spotlight-dock-divider" />

        <div className="spotlight-dock-palette" title="click any swatch to copy hex">
          {SAMPLE.palette.map((c, i) => <span key={i} className="block w-5 h-5 rounded-md" style={{ background: c }} />)}
        </div>

        <div className="spotlight-dock-divider" />

        <button className="spotlight-dock-icon" title="Like 88"><AiOutlineHeart size={18} /></button>
        <button className="spotlight-dock-icon" title="Favorite"><AiOutlineStar size={18} /></button>
        <button className="spotlight-dock-icon" title="Add to collection"><MdPlaylistAdd size={20} /></button>

        <div className="spotlight-dock-divider" />

        <button className="spotlight-dock-cta">
          <span className="balance-pill__coin" aria-hidden />
          Trade for {SAMPLE.cost} <span className="text-paper/55 ml-1">· {SAMPLE.userCoins}⊙</span>
        </button>
      </div>

      {/* Variants strip */}
      <div className="spotlight-variants">
        <div className="kicker text-paper/70 mb-2">Available devices · 12 · horizontal scroll →</div>
        <div className="flex gap-2 overflow-x-auto pb-2">
          {SAMPLE.variants.map((v) => (
            <div key={v.id} className={`spotlight-variant ${v.matched ? 'is-matched' : ''}`}>
              <PlatformIcon icon={v.icon} size={20} />
              <div className="min-w-0">
                <div className="text-[12px] font-medium truncate">{v.name}</div>
                <div className="mono text-[10px] text-paper/65 mt-0.5">{v.w}×{v.h}</div>
              </div>
              <button className="spotlight-variant-dl"><AiOutlineDownload size={14} /></button>
              {v.matched && <span className="spotlight-variant-tag">YOUR DEVICE</span>}
            </div>
          ))}
        </div>
      </div>

      <SpotlightCSS />
    </div>
  );
}

/* ─── DESIGN 3 — INDEX CARD ────────────────────────────────────
   Editorial / magazine spread. Big serif headline at the top
   (kicker + title + byline + meta). Full-bleed image below.
   Three-column metadata strip (Specs · Palette · Actions).
   Variants and More-like-this in their own clearly-titled
   sections below. The most "reading" layout. */
function IndexCardLayout() {
  return (
    <div className="card-page">
      <header className="card-head">
        <div className="kicker text-muted">{SAMPLE.category.toUpperCase()} · ISSUE №{String(SAMPLE.id).padStart(3, '0')} · {SAMPLE.addedDaysAgo} DAYS AGO</div>
        <h1 className="display text-[clamp(40px,5.2vw,68px)] leading-[1.0] tracking-[-0.015em] mt-3">{SAMPLE.title.split(' ').slice(0, 3).join(' ')}<br /><span className="text-accent">{SAMPLE.title.split(' ').slice(3).join(' ')}.</span></h1>
        <div className="card-byline">
          <div className="card-byline-rule" />
          <div>
            <div className="text-[14px]">Photo by <span className="font-medium">@{SAMPLE.uploader.username}</span></div>
            <div className="mono text-[10px] tracking-[0.14em] text-muted mt-1">{SAMPLE.width.toLocaleString()} × {SAMPLE.height.toLocaleString()} · {SAMPLE.resLabel} · {SAMPLE.fileType} · {SAMPLE.fileSize}</div>
          </div>
          <button className="card-close ml-auto"><AiOutlineClose size={16} /></button>
        </div>
      </header>

      <div className="card-hero" style={{ aspectRatio: '16/9' }}>
        <img src={SAMPLE.hero} alt={SAMPLE.title} draggable={false} />
        <span className="card-hero-brackets">
          <span className="br-tl" /><span className="br-tr" /><span className="br-bl" /><span className="br-br" />
        </span>
      </div>

      <div className="card-stats">
        {[['↓ DOWNLOADS', SAMPLE.stats.downloads], ['♥ LIKES', SAMPLE.stats.likes], ['☆ FAVORITED', SAMPLE.stats.favorites], ['◯ VIEWS', SAMPLE.stats.views]].map(([k, v]) => (
          <div key={k as string}>
            <div className="mono text-[9px] tracking-[0.18em] uppercase text-muted">{k}</div>
            <div className="display text-[28px] leading-none mt-1.5">{fmtN(v as number)}</div>
          </div>
        ))}
      </div>

      <div className="card-cols">
        <section>
          <div className="kicker text-muted">Specifications</div>
          <dl className="card-spec-dl mt-3">
            <dt>Resolution</dt><dd>{SAMPLE.width.toLocaleString()} × {SAMPLE.height.toLocaleString()} px</dd>
            <dt>Display class</dt><dd>{SAMPLE.resLabel}{SAMPLE.isDynamic && ' · Dynamic'}{SAMPLE.isAI && ' · AI'}</dd>
            <dt>File</dt><dd>{SAMPLE.fileType} · {SAMPLE.fileSize}</dd>
            <dt>Dominant</dt><dd className="inline-flex items-center gap-2"><span className="inline-block w-3 h-3 border border-hair" style={{ background: SAMPLE.dominantColor }} /> {SAMPLE.category} green</dd>
            <dt>Category</dt><dd className="underline">{SAMPLE.category}</dd>
            <dt>Tags</dt>
            <dd>
              <div className="flex flex-wrap gap-1.5">{SAMPLE.tags.map((t) => <span key={t} className="tile-chip">{t}</span>)}</div>
            </dd>
          </dl>
        </section>

        <section>
          <div className="kicker text-muted">Palette · 5 colors</div>
          <div className="card-palette mt-3">
            {SAMPLE.palette.map((c, i) => (
              <div key={i} className="card-swatch">
                <span className="card-swatch-chip" style={{ background: c }} />
                <span className="mono text-[10px] tracking-[0.08em] text-muted">#2A4B3C</span>
              </div>
            ))}
          </div>
          <div className="card-uploader mt-7">
            <div className="card-uploader-avatar">{SAMPLE.uploader.nickname[0]}</div>
            <div className="min-w-0">
              <div className="text-[14px] font-medium">@{SAMPLE.uploader.username}</div>
              <div className="mono text-[10px] tracking-[0.05em] text-muted mt-0.5">{SAMPLE.uploader.bio}</div>
            </div>
            <a className="mono text-[10px] tracking-[0.18em] text-muted whitespace-nowrap">VIEW →</a>
          </div>
        </section>

        <section>
          <div className="kicker text-muted">Actions</div>
          <div className="card-cta mt-3">
            <div className="kicker text-paper/55">Exchange for</div>
            <div className="display text-[42px] leading-none mt-1">{SAMPLE.cost} <span className="text-accent">coin</span></div>
            <div className="mono text-[10px] tracking-[0.14em] text-paper/55 mt-1.5">YOUR BALANCE · {SAMPLE.userCoins} COINS</div>
            <button className="card-cta-btn mt-3.5">
              <span className="balance-pill__coin" aria-hidden /> Trade for {SAMPLE.cost}
            </button>
          </div>
          <div className="grid grid-cols-2 gap-2 mt-3">
            <button className="btn-pill"><AiOutlineHeart size={15} /><span className="label">Like 88</span></button>
            <button className="btn-pill"><AiOutlineStar size={15} /><span className="label">Favorite</span></button>
            <button className="btn-pill"><MdPlaylistAdd size={17} /><span className="label">Add to list</span></button>
            <button className="btn-pill"><AiOutlineFullscreen size={15} /><span className="label">Fullscreen</span></button>
          </div>
        </section>
      </div>

      <section className="mt-10">
        <div className="label-rule mb-3">Available devices · 12</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
          {SAMPLE.variants.map((v) => (
            <div key={v.id} className={`card-variant ${v.matched ? 'is-matched' : ''}`}>
              <PlatformIcon icon={v.icon} size={22} />
              <div className="min-w-0">
                <div className="text-[14px] font-medium truncate">{v.name} {v.matched && <span className="ml-2 mono text-[9px] tracking-[0.16em] px-2 py-[2px] bg-ink text-paper rounded">YOUR DEVICE</span>}</div>
                <div className="mono text-[10px] text-muted mt-0.5">{v.w}×{v.h} · {v.size}</div>
              </div>
              <button className="card-variant-preview">Preview</button>
              <button className={`card-variant-dl ${v.matched ? 'is-matched' : ''}`}><AiOutlineDownload size={14} /> Download</button>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-12">
        <div className="label-rule mb-3">More like this · 8</div>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="dev-spec-card" style={{ aspectRatio: '3/2' }}>
              <div className="dev-spec-card-screen" style={{ aspectRatio: '3/2', background: 'var(--color-paper-2)' }} />
            </div>
          ))}
        </div>
      </section>

      <CardCSS />
    </div>
  );
}

function fmtN(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(n >= 10_000 ? 0 : 1) + 'K';
  return String(n);
}
function meshStyle(): React.CSSProperties {
  return {
    position: 'absolute', inset: 0, zIndex: 0, pointerEvents: 'none',
    background:
      'radial-gradient(40% 40% at 22% 26%, oklch(92% 0.04 165 / 0.42) 0%, transparent 60%),' +
      'radial-gradient(45% 45% at 78% 80%, oklch(94% 0.03 140 / 0.36) 0%, transparent 55%)',
    filter: 'blur(80px) saturate(1.15)',
  };
}

/* — Studio styles — */
function StudioCSS() {
  return (<style>{`
.studio-hero { position: relative; width: 100%; overflow: hidden; border-radius: 14px; border: 1px solid var(--color-hair); box-shadow: inset 0 1px 0 rgba(255,255,255,0.5), 0 14px 36px -16px rgba(0,0,0,0.25); }
.studio-hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
.studio-hero-fs { position: absolute; top: 14px; right: 14px; display: inline-flex; gap: 6px; align-items: center; padding: 6px 12px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(8px); color: white; font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.06em; border: 1px solid rgba(255,255,255,0.15); }
.studio-hero-pill { position: absolute; bottom: 14px; left: 14px; padding: 6px 12px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(8px); color: var(--color-accent); font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.1em; }
.studio-stats { display: grid; grid-template-columns: repeat(4, 1fr); margin-top: 14px; border: 1px solid var(--color-hair); border-radius: 10px; overflow: hidden; background: var(--color-paper); }
.studio-stat { padding: 14px; border-right: 1px solid var(--color-hair); }
.studio-stat:last-child { border-right: none; }
.studio-inspector { position: sticky; top: 80px; background: var(--color-paper); border: 1px solid var(--color-hair); border-radius: 18px; padding: 22px; box-shadow: inset 0 1px 0 rgba(255,255,255,0.5), 0 14px 36px -16px rgba(0,0,0,0.18); }
.studio-uploader { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border: 1px solid var(--color-hair); border-radius: 12px; background: var(--color-paper-2); cursor: pointer; text-decoration: none; color: inherit; }
.studio-uploader-avatar { width: 38px; height: 38px; border-radius: 50%; background: var(--color-paper); border: 1px solid var(--color-hair); display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-size: 16px; flex-shrink: 0; }
.studio-specs { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px 18px; }
.studio-variants { display: flex; flex-direction: column; gap: 6px; }
.studio-variant-row { display: grid; grid-template-columns: 24px 1fr auto; gap: 12px; align-items: center; padding: 8px 12px; border-radius: 10px; background: var(--color-paper-2); border: 1px solid var(--color-hair); }
.studio-variant-row.is-matched { border-color: var(--color-accent); background: color-mix(in oklch, var(--color-accent) 6%, var(--color-paper-2)); }
.studio-cta-wrap { display: flex; align-items: center; gap: 16px; padding: 18px 20px; border-radius: 14px; background: var(--color-ink); color: var(--color-paper); border: 2px solid var(--color-accent); }
.studio-cta-btn { display: inline-flex; align-items: center; gap: 8px; padding: 12px 22px; border-radius: 999px; background: var(--color-accent); color: white; font-weight: 600; font-size: 13px; box-shadow: 0 8px 22px -8px oklch(72% 0.18 55 / 0.6); }
`}</style>);
}

/* — Spotlight styles — */
function SpotlightCSS() {
  return (<style>{`
.spotlight-stage { position: relative; border-radius: 22px; overflow: hidden; padding: 60px 40px 220px; min-height: 80vh; }
.spotlight-corners { position: absolute; top: 22px; left: 32px; right: 32px; display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; z-index: 3; }
.spotlight-corners .kicker { color: rgba(255,255,255,0.85) !important; }
.spotlight-specs { display: flex; align-items: flex-start; gap: 12px; background: rgba(20,18,15,0.45); backdrop-filter: blur(14px); border: 1px solid rgba(255,255,255,0.14); border-radius: 14px; padding: 14px 16px; color: white; }
.spotlight-hero { max-width: 1080px; margin: 0 auto; position: relative; border-radius: 16px; overflow: hidden; box-shadow: 0 30px 80px -20px rgba(0,0,0,0.45); border: 1px solid rgba(255,255,255,0.18); }
.spotlight-hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
.spotlight-title { position: absolute; left: 28px; bottom: 28px; color: white; font-family: var(--font-display); font-size: clamp(24px, 2.6vw, 36px); line-height: 1.05; max-width: 65%; text-shadow: 0 2px 12px rgba(0,0,0,0.3); }
.spotlight-fs { position: absolute; top: 14px; right: 14px; display: inline-flex; gap: 6px; align-items: center; padding: 6px 12px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(8px); color: white; font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.06em; border: 1px solid rgba(255,255,255,0.15); }
.spotlight-dock { position: absolute; bottom: 110px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 14px; padding: 12px 18px; background: rgba(250,247,240,0.78); backdrop-filter: blur(18px) saturate(1.2); border: 1px solid rgba(0,0,0,0.06); border-radius: 999px; box-shadow: 0 24px 56px -18px rgba(0,0,0,0.35); max-width: calc(100% - 60px); }
.dark .spotlight-dock { background: rgba(20,18,15,0.65); border-color: rgba(255,255,255,0.08); color: var(--color-paper); }
.spotlight-dock-uploader { display: flex; align-items: center; gap: 10px; min-width: 0; }
.spotlight-dock-divider { width: 1px; height: 28px; background: var(--color-hair); }
.spotlight-dock-palette { display: flex; gap: 4px; }
.spotlight-dock-icon { padding: 8px; border-radius: 999px; color: var(--color-ink-2); }
.spotlight-dock-icon:hover { background: var(--color-paper-2); color: var(--color-accent); }
.spotlight-dock-cta { display: inline-flex; align-items: center; gap: 8px; padding: 10px 20px; border-radius: 999px; background: var(--color-ink); color: var(--color-paper); font-size: 13px; font-weight: 600; }
.spotlight-variants { position: absolute; bottom: 22px; left: 32px; right: 32px; }
.spotlight-variants .kicker { color: rgba(255,255,255,0.7) !important; }
.spotlight-variant { position: relative; display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-radius: 12px; background: rgba(20,18,15,0.45); backdrop-filter: blur(14px); border: 1px solid rgba(255,255,255,0.12); color: white; min-width: 220px; }
.spotlight-variant.is-matched { border-color: var(--color-accent); }
.spotlight-variant-dl { padding: 6px; border-radius: 50%; background: rgba(255,255,255,0.15); color: white; }
.spotlight-variant-tag { position: absolute; top: -8px; right: 8px; padding: 2px 8px; border-radius: 999px; background: var(--color-accent); color: white; font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.12em; }
`}</style>);
}

/* — Index Card styles — */
function CardCSS() {
  return (<style>{`
.card-page { max-width: 1100px; margin: 0 auto; }
.card-head { padding: 28px 0 24px; border-bottom: 1px solid var(--color-hair); }
.card-byline { display: flex; align-items: center; gap: 16px; margin-top: 22px; }
.card-byline-rule { width: 56px; height: 1px; background: var(--color-ink); }
.card-close { width: 32px; height: 32px; border-radius: 50%; border: 1px solid var(--color-hair); display: inline-flex; align-items: center; justify-content: center; background: var(--color-paper); }
.card-hero { position: relative; margin: 30px 0; border-radius: 4px; overflow: hidden; background: var(--color-paper-3); }
.card-hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
.card-hero-brackets { position: absolute; inset: 0; pointer-events: none; }
.card-hero-brackets > span { position: absolute; width: 18px; height: 18px; border: 1.5px solid var(--color-ink); }
.card-hero-brackets .br-tl { top: 10px; left: 10px; border-right: none; border-bottom: none; }
.card-hero-brackets .br-tr { top: 10px; right: 10px; border-left: none; border-bottom: none; }
.card-hero-brackets .br-bl { bottom: 10px; left: 10px; border-right: none; border-top: none; }
.card-hero-brackets .br-br { bottom: 10px; right: 10px; border-left: none; border-top: none; }
.card-stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 24px; padding: 18px 0; border-top: 1px solid var(--color-hair); border-bottom: 1px solid var(--color-hair); }
.card-cols { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 36px; margin-top: 28px; }
@media (max-width: 880px) { .card-cols { grid-template-columns: 1fr; } }
.card-spec-dl { display: grid; grid-template-columns: 100px 1fr; gap: 10px 16px; }
.card-spec-dl dt { font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--color-muted); padding-top: 3px; }
.card-spec-dl dd { margin: 0; font-size: 13px; }
.card-palette { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; }
.card-swatch { display: flex; flex-direction: column; gap: 6px; }
.card-swatch-chip { height: 56px; border-radius: 4px; border: 1px solid var(--color-hair); }
.card-uploader { display: flex; align-items: center; gap: 12px; padding: 14px 0; border-top: 1px solid var(--color-hair); border-bottom: 1px solid var(--color-hair); }
.card-uploader-avatar { width: 40px; height: 40px; border-radius: 50%; background: var(--color-paper-2); border: 1px solid var(--color-hair); display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-size: 17px; }
.card-cta { padding: 20px 22px; background: var(--color-ink); color: var(--color-paper); border-radius: 14px; }
.card-cta-btn { display: inline-flex; align-items: center; gap: 8px; padding: 12px 22px; border-radius: 999px; background: var(--color-accent); color: white; font-weight: 600; font-size: 13px; }
.card-variant { display: grid; grid-template-columns: 32px 1fr auto auto; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 12px; background: var(--color-paper); border: 1px solid var(--color-hair); }
.card-variant.is-matched { border-color: var(--color-accent); background: color-mix(in oklch, var(--color-accent) 5%, var(--color-paper)); }
.card-variant-preview { padding: 6px 12px; border-radius: 999px; border: 1px solid var(--color-hair); font-size: 12px; }
.card-variant-dl { display: inline-flex; align-items: center; gap: 6px; padding: 6px 14px; border-radius: 999px; background: var(--color-ink); color: var(--color-paper); font-size: 12px; font-weight: 500; }
.card-variant-dl.is-matched { background: var(--color-accent); }
`}</style>);
}
