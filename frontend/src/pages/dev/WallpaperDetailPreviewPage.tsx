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
  AiOutlineEye,
} from 'react-icons/ai';
import { MdDesktopMac, MdLaptopMac, MdPhoneIphone, MdTabletMac, MdPlaylistAdd, MdDevices } from 'react-icons/md';

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
    { id: 1,  group: 'Mac',         icon: 'laptop'  as const, name: 'MacBook Pro 14"',  w: 3024, h: 1964, size: '2.0 MB', matched: true  },
    { id: 2,  group: 'Mac',         icon: 'laptop'  as const, name: 'MacBook Pro 16"',  w: 3456, h: 2234, size: '2.5 MB', matched: false },
    { id: 3,  group: 'Mac',         icon: 'laptop'  as const, name: 'MacBook Air 13"',  w: 2560, h: 1664, size: '1.7 MB', matched: false },
    { id: 4,  group: 'Mac',         icon: 'desktop' as const, name: '5K iMac · Studio', w: 5120, h: 2880, size: '3.4 MB', matched: false },
    { id: 5,  group: 'iPhone',      icon: 'phone'   as const, name: 'iPhone 16 Pro Max', w: 1320, h: 2868, size: '1.2 MB', matched: false },
    { id: 6,  group: 'iPhone',      icon: 'phone'   as const, name: 'iPhone 16 Pro',     w: 1290, h: 2796, size: '1.1 MB', matched: false },
    { id: 7,  group: 'iPhone',      icon: 'phone'   as const, name: 'iPhone 16',         w: 1170, h: 2532, size: '0.9 MB', matched: false },
    { id: 8,  group: 'iPhone',      icon: 'phone'   as const, name: 'iPhone SE',         w: 750,  h: 1334, size: '0.4 MB', matched: false },
    { id: 9,  group: 'iPad',        icon: 'tablet'  as const, name: 'iPad Pro 13"',      w: 2752, h: 2064, size: '1.6 MB', matched: false },
    { id: 10, group: 'iPad',        icon: 'tablet'  as const, name: 'iPad Air 11"',      w: 1640, h: 2360, size: '1.3 MB', matched: false },
    { id: 11, group: 'Watch / TV',  icon: 'desktop' as const, name: 'Apple TV 4K',       w: 3840, h: 2160, size: '2.3 MB', matched: false },
    { id: 12, group: 'Watch / TV',  icon: 'phone'   as const, name: 'Apple Watch Ultra', w: 410,  h: 502,  size: '0.2 MB', matched: false },
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
  const [variant, setVariant] = useState<Variant>('spotlight');
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
  // Three independent overlays + a small preview popover. Only one
  // overlay shows at a time but they're modeled separately because
  // they're conceptually different (drawer = list, fullscreen = pure
  // image, mockup = chrome). Click outside / ESC closes each.
  const [drawerOpen, setDrawerOpen]   = useState(false);
  const [fsOpen, setFsOpen]           = useState(false);
  const [mockupOpen, setMockupOpen]   = useState(false);
  const [previewMenu, setPreviewMenu] = useState(false);

  const groups = ['Mac', 'iPhone', 'iPad', 'Watch / TV'] as const;

  return (
    <div className="relative">
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

        {/* Hero — click anywhere on the image to enter fullscreen */}
        <div className="spotlight-hero" style={{ aspectRatio: '16/9' }} onClick={() => setFsOpen(true)}>
          <img src={SAMPLE.hero} alt={SAMPLE.title} draggable={false} />
          <h1 className="spotlight-title">{SAMPLE.title}</h1>
          <div className="spotlight-hint"><AiOutlineFullscreen size={12} /> Click to fullscreen</div>
        </div>

        {/* Floating dock — primary surface, always visible while stage in view */}
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

          {/* Preview split — fullscreen vs in-device chrome */}
          <div className="spotlight-dock-pop">
            <button className="spotlight-dock-pill" onClick={() => setPreviewMenu((v) => !v)}>
              <AiOutlineEye size={15} /> Preview <span className="opacity-50 text-[10px]">▾</span>
            </button>
            {previewMenu && (
              <div className="spotlight-popover">
                <button onClick={() => { setPreviewMenu(false); setFsOpen(true); }}>
                  <AiOutlineFullscreen size={14} />
                  <span><strong>Fullscreen</strong><span>Just the image · ESC to close</span></span>
                </button>
                <button onClick={() => { setPreviewMenu(false); setMockupOpen(true); }}>
                  <MdDesktopMac size={16} />
                  <span><strong>In device</strong><span>See it on a Mac / iPhone / iPad</span></span>
                </button>
              </div>
            )}
          </div>

          {/* Devices opens the side drawer with the full grouped list */}
          <button className="spotlight-dock-pill" onClick={() => setDrawerOpen(true)}>
            <MdDevices size={16} /> Devices · 12 <span className="opacity-50 text-[10px]">▾</span>
          </button>

          <div className="spotlight-dock-divider" />

          <button className="spotlight-dock-cta">
            <span className="balance-pill__coin" aria-hidden />
            Trade for {SAMPLE.cost} <span className="text-paper/55 ml-1">· {SAMPLE.userCoins}⊙</span>
          </button>
        </div>

        {/* Tiny matched-device hint under the dock — gives one-tap
            download for the user's own device without opening the drawer */}
        <div className="spotlight-quickmatch">
          <span className="kicker text-paper/65">YOUR DEVICE</span>
          {SAMPLE.variants.filter((v) => v.matched).map((v) => (
            <div key={v.id} className="spotlight-quickmatch-card">
              <PlatformIcon icon={v.icon} size={18} />
              <div>
                <div className="text-[12px] font-medium leading-tight">{v.name}</div>
                <div className="mono text-[10px] text-paper/60">{v.w}×{v.h} · {v.size}</div>
              </div>
              <button className="spotlight-quickmatch-dl"><AiOutlineDownload size={14} /> Get</button>
            </div>
          ))}
        </div>
      </div>

      {/* ─── More like this — below the spotlight stage ─────────────
          Scrolls naturally after the focus moment. 8 cards in a 4-col
          grid; clicking would in the real page swap the hero in-place
          rather than route-jump (parameterless transition). */}
      <section className="mt-12">
        <div className="flex items-end justify-between mb-4">
          <h2 className="display text-[clamp(22px,2.2vw,28px)] leading-none">More like this</h2>
          <a className="mono text-[11px] tracking-[0.14em] text-muted">VIEW ALL → · 8 from <span className="text-ink">@{SAMPLE.uploader.username}</span></a>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="spotlight-rec">
              <div className="spotlight-rec-img" style={{ aspectRatio: '3/2', background: `linear-gradient(${(i * 47) % 360}deg, ${SAMPLE.palette[i % SAMPLE.palette.length]}, ${SAMPLE.palette[(i + 2) % SAMPLE.palette.length]})` }} />
              <div className="spotlight-rec-meta">
                <div className="text-[12px] font-medium truncate">Misty pine №{i + 1}</div>
                <div className="mono text-[10px] text-muted">3840×2160 · 4K</div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* ─── Right-side drawer with grouped device list ───────────── */}
      {drawerOpen && (
        <div className="spotlight-drawer-scrim" onClick={() => setDrawerOpen(false)}>
          <div className="spotlight-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="spotlight-drawer-head">
              <div>
                <div className="kicker text-muted">All devices · 12</div>
                <h3 className="display text-[20px] leading-tight mt-1">Pick the right size</h3>
              </div>
              <button onClick={() => setDrawerOpen(false)} className="p-1.5 rounded-full hover:bg-paper-2"><AiOutlineClose size={18} /></button>
            </div>
            <div className="spotlight-drawer-body">
              {groups.map((g) => {
                const items = SAMPLE.variants.filter((v) => v.group === g);
                if (!items.length) return null;
                return (
                  <div key={g} className="spotlight-drawer-group">
                    <div className="spotlight-drawer-grouphead">
                      <span>{g}</span>
                      <span className="mono text-[10px] tracking-[0.14em] text-muted normal-case">{items.length}</span>
                    </div>
                    {items.map((v) => (
                      <div key={v.id} className={`spotlight-drawer-row ${v.matched ? 'is-matched' : ''}`}>
                        <PlatformIcon icon={v.icon} size={18} />
                        <div className="min-w-0">
                          <div className="text-[13px] truncate">{v.name} {v.matched && <span className="ml-1.5 mono text-[9px] tracking-[0.12em] px-1.5 py-[1px] bg-ink text-paper rounded">YOUR DEVICE</span>}</div>
                          <div className="mono text-[10px] text-muted mt-0.5">{v.w}×{v.h} · {v.size}</div>
                        </div>
                        <button className={`spotlight-drawer-dl ${v.matched ? 'is-matched' : ''}`}>
                          <AiOutlineDownload size={13} /> Get
                        </button>
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
            <div className="spotlight-drawer-foot mono text-[10px] tracking-[0.12em] text-muted">
              ESC OR CLICK OUTSIDE TO CLOSE · ALL DOWNLOADS COST 1 COIN
            </div>
          </div>
        </div>
      )}

      {/* ─── Fullscreen overlay — image-only, dark backdrop ──────── */}
      {fsOpen && (
        <div className="fs-overlay" onClick={() => setFsOpen(false)}>
          <img src={SAMPLE.hero} alt={SAMPLE.title} onClick={(e) => e.stopPropagation()} />
          <div className="fs-controls" onClick={(e) => e.stopPropagation()}>
            <button>Fit</button>
            <span className="fs-divider" />
            <button>Fill</button>
            <span className="fs-divider" />
            <button>↺</button>
            <span className="mono text-[10px] tracking-[0.14em] px-2 opacity-70">100%</span>
            <span className="fs-divider" />
            <button onClick={() => setFsOpen(false)}><AiOutlineClose size={13} /></button>
          </div>
          <button className="fs-close" onClick={() => setFsOpen(false)} title="ESC"><AiOutlineClose size={20} /></button>
        </div>
      )}

      {/* ─── Device mockup modal — wallpaper inside a frame ──────── */}
      {mockupOpen && <DeviceMockupModal onClose={() => setMockupOpen(false)} />}

      <SpotlightCSS />
    </div>
  );
}

/* In-device preview — pick a chassis and render the hero behind it.
   Three SVG frames keeps the demo dependency-free; production would
   probably use real device-frame images sourced from Apple's UI kits. */
function DeviceMockupModal({ onClose }: { onClose: () => void }) {
  const [device, setDevice] = useState<'macbook' | 'iphone' | 'ipad'>('macbook');
  return (
    <div className="mockup-overlay" onClick={onClose}>
      <div className="mockup-shell" onClick={(e) => e.stopPropagation()}>
        <div className="mockup-head">
          <div>
            <div className="kicker text-muted">Preview · how it looks on</div>
            <h3 className="display text-[20px] leading-none mt-1.5">In device</h3>
          </div>
          <div className="mockup-tabs">
            {(['macbook', 'iphone', 'ipad'] as const).map((d) => (
              <button key={d} onClick={() => setDevice(d)} className={device === d ? 'is-on' : ''}>
                {d === 'macbook' ? <MdLaptopMac size={16} /> : d === 'iphone' ? <MdPhoneIphone size={16} /> : <MdTabletMac size={16} />}
                <span className="capitalize">{d}</span>
              </button>
            ))}
          </div>
          <button onClick={onClose} className="p-1.5 rounded-full hover:bg-paper-2 ml-auto"><AiOutlineClose size={18} /></button>
        </div>
        <div className="mockup-stage" style={{ background: `radial-gradient(80% 60% at 50% 35%, ${SAMPLE.palette[1]}, ${SAMPLE.palette[0]})` }}>
          {device === 'macbook' && <MacBookFrame src={SAMPLE.hero} />}
          {device === 'iphone'  && <IPhoneFrame  src={SAMPLE.hero} />}
          {device === 'ipad'    && <IPadFrame    src={SAMPLE.hero} />}
        </div>
        <div className="mockup-foot">
          <div className="mono text-[11px] tracking-[0.08em] text-muted">{deviceLabel(device)}</div>
          <button className="spotlight-dock-cta">
            <AiOutlineDownload size={14} /> Get for this device
          </button>
        </div>
      </div>
    </div>
  );
}
function deviceLabel(d: 'macbook' | 'iphone' | 'ipad'): string {
  if (d === 'macbook') return 'MacBook Pro 14" · 3024×1964 · matched';
  if (d === 'iphone')  return 'iPhone 16 Pro · 1290×2796';
  return 'iPad Pro 13" · 2752×2064';
}
function MacBookFrame({ src }: { src: string }) {
  return (
    <svg viewBox="0 0 800 520" className="mockup-svg" preserveAspectRatio="xMidYMid meet">
      <defs><clipPath id="mbScreen"><rect x="70" y="40" width="660" height="412" rx="14" /></clipPath></defs>
      {/* Body */}
      <rect x="50" y="20" width="700" height="450" rx="20" fill="#1a1815" />
      <rect x="60" y="30" width="680" height="430" rx="16" fill="#2a2724" />
      <circle cx="400" cy="48" r="3" fill="#0a0908" />
      {/* Screen + wallpaper clipped inside */}
      <image href={src} x="70" y="40" width="660" height="412" preserveAspectRatio="xMidYMid slice" clipPath="url(#mbScreen)" />
      {/* Keyboard tray */}
      <rect x="20" y="470" width="760" height="20" rx="6" fill="#3a3633" />
      <rect x="340" y="478" width="120" height="6" rx="2" fill="#1f1d1a" />
    </svg>
  );
}
function IPhoneFrame({ src }: { src: string }) {
  return (
    <svg viewBox="0 0 320 640" className="mockup-svg" preserveAspectRatio="xMidYMid meet">
      <defs><clipPath id="ipScreen"><rect x="22" y="22" width="276" height="596" rx="38" /></clipPath></defs>
      <rect x="10" y="10" width="300" height="620" rx="48" fill="#1a1815" />
      <rect x="22" y="22" width="276" height="596" rx="38" fill="#000" />
      <image href={src} x="22" y="22" width="276" height="596" preserveAspectRatio="xMidYMid slice" clipPath="url(#ipScreen)" />
      {/* Dynamic island */}
      <rect x="125" y="36" width="70" height="22" rx="11" fill="#000" />
    </svg>
  );
}
function IPadFrame({ src }: { src: string }) {
  return (
    <svg viewBox="0 0 560 720" className="mockup-svg" preserveAspectRatio="xMidYMid meet">
      <defs><clipPath id="ipdScreen"><rect x="34" y="34" width="492" height="652" rx="16" /></clipPath></defs>
      <rect x="14" y="14" width="532" height="692" rx="28" fill="#1a1815" />
      <rect x="34" y="34" width="492" height="652" rx="16" fill="#000" />
      <image href={src} x="34" y="34" width="492" height="652" preserveAspectRatio="xMidYMid slice" clipPath="url(#ipdScreen)" />
    </svg>
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
/* ── Stage & hero ── */
.spotlight-stage { position: relative; border-radius: 22px; overflow: hidden; padding: 60px 40px 180px; min-height: 78vh; }
.spotlight-corners { position: absolute; top: 22px; left: 32px; right: 32px; display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; z-index: 3; }
.spotlight-corners .kicker { color: rgba(255,255,255,0.85) !important; }
.spotlight-specs { display: flex; align-items: flex-start; gap: 12px; background: rgba(20,18,15,0.45); backdrop-filter: blur(14px); border: 1px solid rgba(255,255,255,0.14); border-radius: 14px; padding: 14px 16px; color: white; }
.spotlight-hero { max-width: 1080px; margin: 0 auto; position: relative; border-radius: 16px; overflow: hidden; box-shadow: 0 30px 80px -20px rgba(0,0,0,0.45); border: 1px solid rgba(255,255,255,0.18); cursor: zoom-in; }
.spotlight-hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
.spotlight-title { position: absolute; left: 28px; bottom: 28px; color: white; font-family: var(--font-display); font-size: clamp(24px, 2.6vw, 36px); line-height: 1.05; max-width: 65%; text-shadow: 0 2px 12px rgba(0,0,0,0.3); pointer-events: none; }
.spotlight-hint { position: absolute; top: 14px; right: 14px; display: inline-flex; gap: 5px; align-items: center; padding: 5px 10px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(8px); color: white; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.08em; border: 1px solid rgba(255,255,255,0.15); opacity: 0; transition: opacity .25s ease; pointer-events: none; }
.spotlight-hero:hover .spotlight-hint { opacity: 1; }

/* ── Floating dock ── */
.spotlight-dock { position: absolute; bottom: 96px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 12px; padding: 10px 16px; background: rgba(250,247,240,0.82); backdrop-filter: blur(18px) saturate(1.2); border: 1px solid rgba(0,0,0,0.06); border-radius: 999px; box-shadow: 0 24px 56px -18px rgba(0,0,0,0.4); max-width: calc(100% - 60px); flex-wrap: nowrap; }
.dark .spotlight-dock { background: rgba(20,18,15,0.65); border-color: rgba(255,255,255,0.08); color: var(--color-paper); }
.spotlight-dock-uploader { display: flex; align-items: center; gap: 10px; min-width: 0; }
.spotlight-dock-divider { width: 1px; height: 26px; background: var(--color-hair); flex-shrink: 0; }
.spotlight-dock-palette { display: flex; gap: 4px; }
.spotlight-dock-icon { padding: 7px; border-radius: 999px; color: var(--color-ink-2); }
.spotlight-dock-icon:hover { background: var(--color-paper-2); color: var(--color-accent); }
.spotlight-dock-pill { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 999px; border: 1px solid var(--color-hair); background: var(--color-paper); font-size: 12px; font-weight: 500; }
.spotlight-dock-pill:hover { background: var(--color-paper-2); }
.spotlight-dock-cta { display: inline-flex; align-items: center; gap: 8px; padding: 10px 18px; border-radius: 999px; background: var(--color-ink); color: var(--color-paper); font-size: 13px; font-weight: 600; }
.spotlight-dock-pop { position: relative; }
.spotlight-popover { position: absolute; bottom: calc(100% + 10px); left: 50%; transform: translateX(-50%); width: 240px; background: var(--color-paper); border: 1px solid var(--color-hair); border-radius: 14px; box-shadow: 0 20px 50px -16px rgba(0,0,0,0.28); padding: 6px; z-index: 30; }
.spotlight-popover button { width: 100%; display: flex; align-items: flex-start; gap: 10px; padding: 10px 12px; border-radius: 10px; text-align: left; }
.spotlight-popover button:hover { background: var(--color-paper-2); }
.spotlight-popover button strong { display: block; font-size: 13px; font-weight: 600; margin-bottom: 2px; }
.spotlight-popover button span span { display: block; font-family: var(--font-mono); font-size: 10px; color: var(--color-muted); letter-spacing: 0.04em; }

/* Quick-match card under the dock — fast path for matched device */
.spotlight-quickmatch { position: absolute; bottom: 24px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 12px; color: white; }
.spotlight-quickmatch .kicker { color: rgba(255,255,255,0.7) !important; }
.spotlight-quickmatch-card { display: inline-flex; align-items: center; gap: 10px; padding: 8px 14px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(12px); border: 1px solid var(--color-accent); color: white; }
.spotlight-quickmatch-dl { display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 999px; background: var(--color-accent); color: white; font-size: 11px; font-weight: 600; }

/* ── More-like-this grid ── */
.spotlight-rec { border: 1px solid var(--color-hair); border-radius: 12px; overflow: hidden; background: var(--color-paper); cursor: pointer; transition: transform .25s ease, box-shadow .25s ease; }
.spotlight-rec:hover { transform: translateY(-2px); box-shadow: 0 12px 24px -16px rgba(0,0,0,0.18); }
.spotlight-rec-img { width: 100%; }
.spotlight-rec-meta { padding: 8px 12px 10px; }

/* ── Drawer (right slide-in, grouped device list) ── */
.spotlight-drawer-scrim { position: fixed; inset: 0; background: rgba(20,18,15,0.42); backdrop-filter: blur(2px); z-index: 60; display: flex; justify-content: flex-end; }
.spotlight-drawer { width: 420px; max-width: 92vw; height: 100vh; background: var(--color-paper); display: flex; flex-direction: column; box-shadow: -20px 0 60px -20px rgba(0,0,0,0.25); border-left: 1px solid var(--color-hair); animation: slideInRight .28s cubic-bezier(0.2,0.8,0.2,1); }
@keyframes slideInRight { from { transform: translateX(20px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
.spotlight-drawer-head { padding: 22px 22px 16px; border-bottom: 1px solid var(--color-hair); display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.spotlight-drawer-body { flex: 1; overflow-y: auto; padding: 6px 18px 18px; }
.spotlight-drawer-foot { padding: 12px 22px; border-top: 1px solid var(--color-hair); background: var(--color-paper-2); }
.spotlight-drawer-group { margin-top: 14px; }
.spotlight-drawer-grouphead { display: flex; justify-content: space-between; align-items: baseline; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--color-muted); padding: 0 6px 6px; border-bottom: 1px solid var(--color-hair); margin-bottom: 6px; }
.spotlight-drawer-row { display: grid; grid-template-columns: 24px 1fr auto; gap: 12px; align-items: center; padding: 10px 6px; border-radius: 8px; }
.spotlight-drawer-row:hover { background: var(--color-paper-2); }
.spotlight-drawer-row.is-matched { background: color-mix(in oklch, var(--color-accent) 5%, var(--color-paper)); }
.spotlight-drawer-dl { display: inline-flex; align-items: center; gap: 4px; padding: 5px 11px; border-radius: 999px; background: var(--color-ink); color: var(--color-paper); font-size: 11px; font-weight: 500; }
.spotlight-drawer-dl.is-matched { background: var(--color-accent); }

/* ── Fullscreen overlay ── */
.fs-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.94); z-index: 70; display: flex; align-items: center; justify-content: center; cursor: zoom-out; animation: fadeIn .2s ease; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
.fs-overlay > img { max-width: 96vw; max-height: 92vh; object-fit: contain; box-shadow: 0 30px 80px -20px rgba(0,0,0,0.6); cursor: default; }
.fs-close { position: absolute; top: 22px; right: 22px; width: 40px; height: 40px; border-radius: 50%; background: rgba(255,255,255,0.1); color: white; display: inline-flex; align-items: center; justify-content: center; }
.fs-close:hover { background: rgba(255,255,255,0.2); }
.fs-controls { position: absolute; bottom: 28px; left: 50%; transform: translateX(-50%); display: inline-flex; align-items: center; gap: 4px; padding: 8px 12px; border-radius: 999px; background: rgba(255,255,255,0.08); backdrop-filter: blur(14px); border: 1px solid rgba(255,255,255,0.12); color: white; font-size: 12px; }
.fs-controls button { padding: 4px 10px; border-radius: 999px; }
.fs-controls button:hover { background: rgba(255,255,255,0.1); }
.fs-divider { width: 1px; height: 16px; background: rgba(255,255,255,0.2); }

/* ── Device mockup modal ── */
.mockup-overlay { position: fixed; inset: 0; background: rgba(20,18,15,0.5); backdrop-filter: blur(6px); z-index: 70; display: flex; align-items: center; justify-content: center; padding: 24px; animation: fadeIn .2s ease; }
.mockup-shell { width: 100%; max-width: 920px; max-height: 92vh; background: var(--color-paper); border-radius: 18px; border: 1px solid var(--color-hair); display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 40px 100px -30px rgba(0,0,0,0.4); }
.mockup-head { display: flex; align-items: center; gap: 18px; padding: 16px 22px; border-bottom: 1px solid var(--color-hair); }
.mockup-tabs { display: inline-flex; gap: 2px; padding: 3px; background: var(--color-paper-2); border-radius: 999px; }
.mockup-tabs button { display: inline-flex; align-items: center; gap: 6px; padding: 6px 12px; border-radius: 999px; font-size: 12px; font-weight: 500; color: var(--color-muted); }
.mockup-tabs button.is-on { background: var(--color-paper); color: var(--color-ink); box-shadow: 0 2px 4px -1px rgba(0,0,0,0.08); }
.mockup-stage { flex: 1; min-height: 480px; display: flex; align-items: center; justify-content: center; padding: 30px; }
.mockup-svg { width: 100%; height: 100%; max-height: 480px; }
.mockup-foot { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 14px 22px; border-top: 1px solid var(--color-hair); background: var(--color-paper); }
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
