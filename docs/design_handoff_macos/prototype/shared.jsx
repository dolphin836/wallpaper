/* Shared data + components for "The Archive" — V2.
   Edits in this version:
   - Wallpapers have NO title / NO description fields anymore.
   - Sidebar: removed EST/Volume sub-tagline & Catalog nav; added Upload, theme toggle,
     auth slot (login/register OR avatar/logout), and a weak legal footer with copyright.
   - SpecimenTag now leads with specimen number + category, since there's no title.
   - SearchField removed (unsupported in V1).
*/

// 16 specimens — title/description removed; metadata kept.
const SPECIMENS = [
  { id: 1,  seed: "arch-1041",  w: 1600, h: 1066, author: "marin.k",      cat: "Nature",       color: "#c9966a", res: "4K",  coins: 1, likes: 2841,  downloads: 1209, days: 2 },
  { id: 2,  seed: "arch-2089",  w: 1200, h: 1600, author: "k_otsuka",     cat: "City",         color: "#1a2a3d", res: "5K",  coins: 2, likes: 5120,  downloads: 2890, days: 5 },
  { id: 3,  seed: "arch-3120",  w: 1600, h: 900,  author: "fern.atelier", cat: "Minimal",      color: "#e6e1d3", res: "4K",  coins: 1, likes: 932,   downloads: 488,  days: 1 },
  { id: 4,  seed: "arch-4501",  w: 1600, h: 1200, author: "studio.glo",   cat: "Abstract",     color: "#7a3aa8", res: "6K",  coins: 3, likes: 12440, downloads: 8801, days: 12, featured: true },
  { id: 5,  seed: "arch-5072",  w: 1400, h: 1600, author: "ohta",         cat: "Nature",       color: "#23568a", res: "4K",  coins: 1, likes: 1804,  downloads: 902,  days: 3 },
  { id: 6,  seed: "arch-6233",  w: 1600, h: 1066, author: "marin.k",      cat: "Architecture", color: "#9a9a96", res: "4K",  coins: 1, likes: 612,   downloads: 280,  days: 6 },
  { id: 7,  seed: "arch-7088",  w: 1600, h: 900,  author: "wallx",        cat: "Dynamic",      color: "#d97757", res: "5K",  coins: 2, likes: 3201,  downloads: 1980, days: 8, dynamic: true },
  { id: 8,  seed: "arch-8410",  w: 1066, h: 1600, author: "fern.atelier", cat: "Nature",       color: "#5b6b4d", res: "4K",  coins: 1, likes: 740,   downloads: 410,  days: 4 },
  { id: 9,  seed: "arch-9105",  w: 1600, h: 1066, author: "ines.r",       cat: "Street",       color: "#b86a3f", res: "3K",  coins: 1, likes: 1190,  downloads: 530,  days: 9 },
  { id: 10, seed: "arch-1212",  w: 1600, h: 1066, author: "ohta",         cat: "Nature",       color: "#a6b7c8", res: "4K",  coins: 1, likes: 2010,  downloads: 1102, days: 11 },
  { id: 11, seed: "arch-1313",  w: 1600, h: 900,  author: "k_otsuka",     cat: "City",         color: "#3a5a3a", res: "5K",  coins: 2, likes: 880,   downloads: 421,  days: 13 },
  { id: 12, seed: "arch-1414",  w: 1200, h: 1600, author: "fern.atelier", cat: "Minimal",      color: "#efe9dd", res: "4K",  coins: 1, likes: 1502,  downloads: 720,  days: 7 },
  { id: 13, seed: "arch-1515",  w: 1600, h: 1066, author: "studio.glo",   cat: "Abstract",     color: "#2b2b35", res: "6K",  coins: 2, likes: 6210,  downloads: 3340, days: 15 },
  { id: 14, seed: "arch-1616",  w: 1600, h: 1066, author: "marin.k",      cat: "Nature",       color: "#4a7892", res: "4K",  coins: 1, likes: 990,   downloads: 488,  days: 5 },
  { id: 15, seed: "arch-1717",  w: 1066, h: 1600, author: "ines.r",       cat: "Architecture", color: "#7a2222", res: "4K",  coins: 1, likes: 1430, downloads: 612,  days: 10 },
  { id: 16, seed: "arch-1818",  w: 1600, h: 900,  author: "wallx",        cat: "Dynamic",      color: "#1a4a4a", res: "8K",  coins: 3, likes: 8810, downloads: 4920, days: 14, dynamic: true },
];

function picsum(s, w, h) { return `https://picsum.photos/seed/${s}/${w}/${h}`; }

const fmt = (n) => n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);

// ─── Atoms ─────────────────────────────────────────────────────────────

function Kicker({ children, style }) {
  return <span className="kicker" style={{ color: "var(--muted)", ...style }}>{children}</span>;
}

function Coin({ value, size = 12 }) {
  return <span className="coin" style={{ fontSize: size }}>{value}</span>;
}

function Tag({ children, style, tone = "ink" }) {
  const tones = {
    ink:    { bg: "transparent",        bd: "var(--hair)", fg: "var(--ink)" },
    paper:  { bg: "var(--paper-2)",     bd: "var(--hair)", fg: "var(--ink)" },
    accent: { bg: "var(--accent-soft)", bd: "transparent", fg: "var(--accent-ink)" },
    solid:  { bg: "var(--ink)",         bd: "transparent", fg: "var(--paper)" },
  };
  const t = tones[tone];
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      padding: "3px 8px", border: `1px solid ${t.bd}`, background: t.bg, color: t.fg,
      borderRadius: 999, fontFamily: "var(--mono)", fontSize: 10, fontWeight: 500,
      letterSpacing: "0.06em",
      ...style,
    }}>{children}</span>
  );
}

function Btn({ children, tone = "ink", size = "md", style, onClick, active = false }) {
  const sizes = {
    sm: { padding: "6px 12px",  fontSize: 12 },
    md: { padding: "10px 18px", fontSize: 13 },
    lg: { padding: "14px 24px", fontSize: 14 },
  };
  const tones = {
    ink:    { bg: "var(--ink)",         fg: "var(--paper)", bd: "transparent" },
    ghost:  { bg: "transparent",        fg: "var(--ink)",   bd: "var(--hair)" },
    accent: { bg: "var(--accent)",      fg: "#fff",         bd: "transparent" },
    paper:  { bg: "var(--paper)",       fg: "var(--ink)",   bd: "var(--hair)" },
    activeAccent: { bg: "var(--accent)",fg: "#fff",         bd: "transparent" },
  };
  const t = tones[active ? "activeAccent" : tone];
  return (
    <button onClick={onClick} style={{
      ...sizes[size],
      background: t.bg, color: t.fg, border: `1px solid ${t.bd}`,
      fontFamily: "var(--sans)", fontWeight: 500, letterSpacing: "-0.01em",
      borderRadius: 999, display: "inline-flex", alignItems: "center", gap: 8,
      ...style,
    }}>{children}</button>
  );
}

function IconBtn({ children, tone = "paper", style, title, onClick }) {
  const tones = {
    paper: { bg: "var(--paper)",   fg: "var(--ink)",  bd: "var(--hair)" },
    ink:   { bg: "var(--ink)",     fg: "var(--paper)", bd: "transparent" },
    glass: { bg: "rgba(255,255,255,0.14)", fg: "#fff", bd: "rgba(255,255,255,0.22)" },
    accent:{ bg: "var(--accent)",  fg: "#fff",         bd: "transparent" },
  };
  const t = tones[tone];
  return (
    <button onClick={onClick} title={title} style={{
      width: 38, height: 38, borderRadius: 999,
      background: t.bg, color: t.fg, border: `1px solid ${t.bd}`,
      backdropFilter: tone === "glass" ? "blur(12px)" : undefined,
      display: "inline-flex", alignItems: "center", justifyContent: "center",
      ...style,
    }}>{children}</button>
  );
}

function Brackets({ inset = 6, color = "var(--ink)", size = 14, opacity = 1 }) {
  const s = { position: "absolute", width: size, height: size, borderColor: color, opacity };
  return (
    <>
      <span style={{ ...s, top: inset, left: inset,  borderTop: "1px solid", borderLeft: "1px solid" }} />
      <span style={{ ...s, top: inset, right: inset, borderTop: "1px solid", borderRight: "1px solid" }} />
      <span style={{ ...s, bottom: inset, left: inset,  borderBottom: "1px solid", borderLeft: "1px solid" }} />
      <span style={{ ...s, bottom: inset, right: inset, borderBottom: "1px solid", borderRight: "1px solid" }} />
    </>
  );
}

// ─── Icons ─────────────────────────────────────────────────────────────

const SvgI = ({ d, size = 16, stroke = 1.4, fill = "none" }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
    {Array.isArray(d) ? d.map((p, i) => <path key={i} d={p} />) : <path d={d} />}
  </svg>
);
const I = {
  heart:    (p) => <SvgI d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" {...p} />,
  heartFill: (p) => <SvgI d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" fill="currentColor" stroke="none" {...p} />,
  star:     (p) => <SvgI d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" {...p} />,
  starFill: (p) => <SvgI d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" fill="currentColor" stroke="none" {...p} />,
  check:    (p) => <SvgI d="M5 12l5 5L20 7" {...p} />,
  dl:       (p) => <SvgI d={["M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4","M7 10l5 5 5-5","M12 15V3"]} {...p} />,
  arrow:    (p) => <SvgI d={["M5 12h14","M13 6l6 6-6 6"]} {...p} />,
  plus:     (p) => <SvgI d={["M12 5v14","M5 12h14"]} {...p} />,
  grid:     (p) => <SvgI d={["M3 3h7v7H3z","M14 3h7v7h-7z","M3 14h7v7H3z","M14 14h7v7h-7z"]} {...p} />,
  rows:     (p) => <SvgI d={["M3 6h18","M12 12h9","M3 12h6","M3 18h18"]} {...p} />,
  monitor:  (p) => <SvgI d={["M3 4h18v12H3z","M8 20h8","M12 16v4"]} {...p} />,
  globe:    (p) => <SvgI d={["M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z","M2 12h20","M12 2a14 14 0 0 1 0 20","M12 2a14 14 0 0 0 0 20"]} {...p} />,
  more:     (p) => <SvgI d={["M6 12h.01","M12 12h.01","M18 12h.01"]} stroke={3} {...p} />,
  sun:      (p) => <SvgI d={["M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10z","M12 1v3","M12 20v3","M4.2 4.2l2.1 2.1","M17.7 17.7l2.1 2.1","M1 12h3","M20 12h3","M4.2 19.8l2.1-2.1","M17.7 6.3l2.1-2.1"]} {...p} />,
  moon:     (p) => <SvgI d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" {...p} />,
  logout:   (p) => <SvgI d={["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4","M16 17l5-5-5-5","M21 12H9"]} {...p} />,
  upload:   (p) => <SvgI d={["M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4","M17 8l-5-5-5 5","M12 3v12"]} {...p} />,
  x:        (p) => <SvgI d={["M18 6L6 18","M6 6l12 12"]} {...p} />,
  eye:      (p) => <SvgI d={["M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z","M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"]} {...p} />,
  layers:   (p) => <SvgI d={["M12 2l10 6-10 6L2 8l10-6z","M2 16l10 6 10-6","M2 12l10 6 10-6"]} {...p} />,
  phone:    (p) => <SvgI d={["M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z","M11 18h2"]} {...p} />,
  tablet:   (p) => <SvgI d={["M5 2h14a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z","M10 18h4"]} {...p} />,
  laptop:   (p) => <SvgI d={["M4 5h16v11H4z","M2 19h20","M2 19l1-3h18l1 3"]} {...p} />,
  desktop:  (p) => <SvgI d={["M3 4h18v12H3z","M8 20h8","M12 16v4"]} {...p} />,
  proDisp:  (p) => <SvgI d={["M2 4h20v13H2z","M9 21h6","M12 17v4","M6 8h2","M6 11h2"]} {...p} />,
  copy:     (p) => <SvgI d={["M9 4h11a1 1 0 0 1 1 1v11","M4 8h11a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"]} {...p} />,
  check:    (p) => <SvgI d="M5 12l5 5L20 7" {...p} />,
  pen:      (p) => <SvgI d={["M3 21l3-1 12-12-2-2L4 18l-1 3z","M15 5l4 4"]} {...p} />,
  lock:     (p) => <SvgI d={["M5 11h14v10H5z","M8 11V7a4 4 0 0 1 8 0v4"]} {...p} />,
  cal:      (p) => <SvgI d={["M4 5h16v16H4z","M4 9h16","M9 3v4","M15 3v4"]} {...p} />,
  mail:     (p) => <SvgI d={["M3 6h18v12H3z","M3 6l9 7 9-7"]} {...p} />,
  folder:   (p) => <SvgI d={["M3 6h6l2 3h10v10H3z"]} {...p} />,
  bolt:     (p) => <SvgI d={["M13 2L4 14h8l-1 8 9-12h-8l1-8z"]} {...p} />,
  user:     (p) => <SvgI d={["M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z","M4 21a8 8 0 0 1 16 0"]} {...p} />,
  external: (p) => <SvgI d={["M7 17L17 7","M8 7h9v9"]} {...p} />,
  search:   (p) => <SvgI d={["M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z","M21 21l-4.3-4.3"]} {...p} />,
  shuffle:  (p) => <SvgI d={["M16 3h5v5","M4 20L21 3","M21 16v5h-5","M15 15l6 6","M4 4l5 5"]} {...p} />,
  power:    (p) => <SvgI d={["M18.4 6.6a9 9 0 1 1-12.8 0","M12 2v10"]} {...p} />,
  refresh:  (p) => <SvgI d={["M3 12a9 9 0 1 0 3-6.7","M3 4v5h5"]} {...p} />,
  set:      (p) => <SvgI d={["M3 4h18v12H3z","M8 20h8","M12 16v4","M9 8l3 3 3-3","M12 4v7"]} {...p} />,
  filter:   (p) => <SvgI d={["M3 5h18","M6 12h12","M10 19h4"]} {...p} />,
  apple:    ({ size = 14 }) => (
    <svg width={size} height={size} viewBox="0 0 384 512" fill="currentColor">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/>
    </svg>
  ),
};

// ─── Tile + Specimen (without titles) ──────────────────────────────────

function Tile({ spec, w, h, style }) {
  const ratio = spec.w / spec.h;
  const aspect = w && h ? `${w} / ${h}` : `${spec.w} / ${spec.h}`;
  return (
    <figure style={{
      margin: 0, position: "relative", overflow: "hidden",
      aspectRatio: aspect, background: spec.color, ...style,
    }}>
      <img
        src={picsum(spec.seed, Math.min(1200, Math.round((h ?? 800) * (ratio))), h ?? 800)}
        alt=""
        loading="lazy"
        style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", display: "block" }}
      />
      {spec.dynamic && (
        <span style={{
          position: "absolute", top: 10, left: 10, padding: "3px 8px",
          background: "rgba(0,0,0,0.6)", color: "#fff", borderRadius: 999,
          fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.06em",
          display: "inline-flex", alignItems: "center", gap: 5,
        }}>
          <I.apple size={9} /> DYNAMIC
        </span>
      )}
      <span style={{
        position: "absolute", top: 10, right: 10,
        padding: "3px 8px", background: "rgba(0,0,0,0.55)", color: "#fff",
        borderRadius: 3, fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.06em",
      }}>{spec.res}</span>
    </figure>
  );
}

// Title-free specimen tag — leads with №ID + category instead.
function SpecimenTag({ spec, dense = false, showCoin = true }) {
  return (
    <div style={{
      paddingTop: dense ? 8 : 12,
      display: "grid",
      gridTemplateColumns: "1fr auto",
      alignItems: "center",
      gap: 12,
      fontFamily: "var(--sans)",
    }}>
      <div style={{ minWidth: 0 }}>
        <div style={{
          fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)",
          letterSpacing: "0.12em", textTransform: "uppercase",
          display: "flex", gap: 8, alignItems: "center",
        }}>
          <span>№{String(spec.id).padStart(3, "0")}</span>
          <span style={{ width: 3, height: 3, borderRadius: 999, background: "var(--muted)" }} />
          <span>{spec.cat}</span>
        </div>
        <div className="display" style={{
          fontSize: dense ? 18 : 22, lineHeight: 1.05, color: "var(--ink)", marginTop: 4,
        }}>
          @{spec.author}
        </div>
      </div>
      {showCoin && <Coin value={spec.coins} size={dense ? 11 : 13} />}
    </div>
  );
}

// ─── Brand mark ────────────────────────────────────────────────────────

function Logomark({ size = 36, color = "currentColor" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none" stroke={color} strokeWidth="2">
      <rect x="2" y="2" width="60" height="60" />
      <text x="32" y="44" textAnchor="middle" fontFamily="Instrument Serif, serif" fontSize="36" fill={color} stroke="none">W</text>
      <rect x="8" y="8" width="6" height="6" fill={color} stroke="none" />
    </svg>
  );
}

// ─── Sidebar ──────────────────────────────────────────────────────────
// auth: "in" | "out"  — shows the upload nav row only when signed in.

function ArchiveSidebar({ active = "Discover", auth = "in", balance = 12 }) {
  const items = [
    ["Discover",   "Recent specimens"],
    ["Collections","Curated & user lists"],
    ["Uploaders",  "Contributing artists"],
    ["macOS App",  "Menu-bar companion"],
  ];
  if (auth === "in") items.splice(1, 0, ["Upload", "Earn +5 coins"]);

  return (
    <aside style={{
      width: 232, padding: "32px 22px", background: "var(--paper)",
      borderRight: "1px solid var(--hair)", display: "flex", flexDirection: "column",
      fontFamily: "var(--sans)", height: "100%",
    }}>
      {/* Brand */}
      <a href="#" style={{ display: "flex", alignItems: "center", gap: 12, color: "inherit", textDecoration: "none" }}>
        <Logomark size={36} color="var(--ink)" />
        <div>
          <div className="display" style={{ fontSize: 18, lineHeight: 1 }}>Wallpaper</div>
          <div className="display italic-d" style={{ fontSize: 18, lineHeight: 1, marginTop: 2 }}>Exchange</div>
        </div>
      </a>

      <hr className="spec-rule" style={{ margin: "24px 0 14px" }} />

      <div className="kicker" style={{ color: "var(--muted)", marginBottom: 12 }}>Sections</div>

      <nav style={{ display: "flex", flexDirection: "column" }}>
        {items.map(([n, sub], i) => {
          const isActive = n === active;
          const isUpload = n === "Upload";
          return (
            <div key={n} style={{
              padding: "13px 0",
              borderTop: i === 0 ? "1px solid var(--hair)" : "none",
              borderBottom: "1px solid var(--hair)",
              display: "grid", gridTemplateColumns: "20px 1fr auto", alignItems: "baseline",
              cursor: "pointer", color: isActive ? "var(--ink)" : "var(--ink-2)",
            }}>
              <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)" }}>
                {String(i + 1).padStart(2, "0")}
              </span>
              <div>
                <div className="display" style={{ fontSize: 18, lineHeight: 1.1, color: isUpload ? "var(--accent)" : (isActive ? "var(--ink)" : "var(--ink-2)") }}>
                  {n}
                </div>
                <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 2 }}>{sub}</div>
              </div>
              {isActive && <span style={{ width: 6, height: 6, background: "var(--accent)", borderRadius: 999 }} />}
              {isUpload && !isActive && <I.plus size={14} stroke={1.6} />}
            </div>
          );
        })}
      </nav>

      {/* Balance — only when signed in */}
      {auth === "in" && (
        <div style={{
          marginTop: 20, padding: 14, border: "1px solid var(--hair)", background: "var(--paper-2)",
        }}>
          <div className="kicker" style={{ color: "var(--muted)" }}>Your balance</div>
          <div style={{ marginTop: 6, display: "flex", alignItems: "baseline", gap: 6 }}>
            <Coin value={balance} size={22} />
            <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)" }}>/ COINS</span>
          </div>
          <div style={{ marginTop: 8, fontSize: 11, color: "var(--ink-2)", lineHeight: 1.4 }}>
            Upload to earn <span style={{ color: "var(--accent)" }}>+5</span>.
          </div>
        </div>
      )}

      {/* Legal footer — quiet utility nav, clearly fenced off from the copyright line */}
      <div style={{ marginTop: "auto", paddingTop: 24 }}>
        <hr className="spec-rule" style={{ borderTopStyle: "dashed", borderTopColor: "var(--hair)" }} />
        <ul style={{
          listStyle: "none", padding: "12px 0", margin: 0,
          display: "flex", flexWrap: "wrap", gap: "6px 12px",
          fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.12em",
          textTransform: "uppercase", color: "var(--muted)",
        }}>
          <li>
            <a href="#" style={{ color: "inherit", textDecoration: "none" }}>Terms</a>
          </li>
          <li style={{ color: "var(--hair)" }} aria-hidden>·</li>
          <li>
            <a href="#" style={{ color: "inherit", textDecoration: "none" }}>Privacy</a>
          </li>
          <li style={{ color: "var(--hair)" }} aria-hidden>·</li>
          <li>
            <a href="#" style={{ color: "inherit", textDecoration: "none" }}>DMCA</a>
          </li>
        </ul>
        <hr className="spec-rule" />
        <div style={{
          marginTop: 10, fontFamily: "var(--sans)", fontStyle: "normal",
          fontSize: 11, color: "var(--ink-2)", letterSpacing: "-0.005em",
        }}>
          © 2026 <span className="display italic-d" style={{ fontSize: 13 }}>Wallpaper Exchange</span>
        </div>
      </div>
    </aside>
  );
}

// ─── Topbar (no search; auth + theme) ──────────────────────────────────
// `children` slot sits between masthead/back and right-side utilities.

function ArchiveTopbar({ children, auth = "in", dark = false, stats = { wallpapers: 1284, collections: 168 }, date = "MAY 15, 2026" }) {
  return (
    <div style={{ borderBottom: "1px solid var(--hair)", background: "var(--paper)" }}>
      {/* Masthead — project stats left, date right */}
      <div style={{
        padding: "10px 32px", display: "flex", justifyContent: "space-between", alignItems: "center",
        borderBottom: "1px solid var(--hair)",
        fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.18em",
        color: "var(--muted)", textTransform: "uppercase",
      }}>
        <span style={{ display: "inline-flex", alignItems: "center", gap: 14 }}>
          <span><strong style={{ color: "var(--ink-2)", fontWeight: 600 }}>{stats.wallpapers.toLocaleString()}</strong> Specimens</span>
          <span style={{ opacity: 0.4 }}>·</span>
          <span><strong style={{ color: "var(--ink-2)", fontWeight: 600 }}>{stats.collections.toLocaleString()}</strong> Collections</span>
        </span>
        <span>{date}</span>
      </div>
      {/* Row */}
      <div style={{ padding: "16px 32px", display: "flex", alignItems: "center", gap: 12, minHeight: 64 }}>
        <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
          {children}
        </div>

        {/* Right side: theme + auth */}
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {/* Theme toggle — 2-state segmented control */}
          <div style={{
            display: "inline-flex", alignItems: "center", padding: 3, gap: 2,
            background: "var(--paper-2)", border: "1px solid var(--hair)", borderRadius: 999,
          }}>
            <button title="Light mode" style={{
              width: 30, height: 30, borderRadius: 999, border: "none",
              background: !dark ? "var(--paper)" : "transparent",
              color: !dark ? "var(--ink)" : "var(--muted)",
              boxShadow: !dark ? "0 1px 0 var(--hair), 0 0 0 1px var(--hair)" : "none",
              display: "inline-flex", alignItems: "center", justifyContent: "center",
              cursor: "pointer", transition: "background 140ms ease, color 140ms ease",
            }}>
              <I.sun size={14} />
            </button>
            <button title="Dark mode" style={{
              width: 30, height: 30, borderRadius: 999, border: "none",
              background: dark ? "var(--ink)" : "transparent",
              color: dark ? "var(--paper)" : "var(--muted)",
              boxShadow: dark ? "0 1px 0 var(--hair), 0 0 0 1px var(--ink-2)" : "none",
              display: "inline-flex", alignItems: "center", justifyContent: "center",
              cursor: "pointer", transition: "background 140ms ease, color 140ms ease",
            }}>
              <I.moon size={14} />
            </button>
          </div>

          {auth === "in" ? (
            <>
              <IconBtn tone="paper" title="Log out"><I.logout size={15} /></IconBtn>
              <a href="#" title="@marin.k" style={{ display: "inline-flex", textDecoration: "none" }}>
                <div style={{
                  width: 38, height: 38, borderRadius: "50%",
                  background: "var(--paper-2)", border: "1px solid var(--hair)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontFamily: "var(--display)", fontSize: 18, color: "var(--ink)",
                  marginLeft: 4,
                }}>M</div>
              </a>
            </>
          ) : (
            <>
              <Btn tone="ghost" size="sm" style={{ borderRadius: 999 }}>Log in</Btn>
              <Btn tone="ink" size="sm" style={{ borderRadius: 999 }}>Register</Btn>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  SPECIMENS, picsum, fmt, Kicker, Coin, Tag, Btn, IconBtn, Brackets, I, Tile, SpecimenTag, Logomark,
  ArchiveSidebar, ArchiveTopbar,
  Pagination, ProfileTabs, PrivacyNotice, ProcessingOverlay,
});

// ─── Pagination ───────────────────────────────────────────────────────

function Pagination({ current = 1, total = 12 }) {
  // Compact pager: 1 · 2 · 3 ... N-1 · N with current centered.
  const pages = [];
  const push = (v) => pages.push(v);
  if (total <= 7) {
    for (let i = 1; i <= total; i++) push(i);
  } else {
    push(1);
    if (current > 3) push("…");
    const start = Math.max(2, current - 1);
    const end   = Math.min(total - 1, current + 1);
    for (let i = start; i <= end; i++) push(i);
    if (current < total - 2) push("…");
    push(total);
  }
  return (
    <>
      <div className="pager">
        <button className="pager-nav" disabled={current === 1}>
          ← Prev
        </button>
        <div className="pager-pages">
          {pages.map((p, i) =>
            p === "…"
              ? <span key={`e${i}`} className="pager-ellipsis">…</span>
              : <button key={p} className={p === current ? "is-current" : ""}>{p}</button>
          )}
        </div>
        <button className="pager-nav" disabled={current === total}>
          Next →
        </button>
      </div>
      <div className="pager-status">PAGE {current} OF {total}</div>
    </>
  );
}

// ─── Profile tabs ─────────────────────────────────────────────────────

function ProfileTabs({ active = "uploads", isOwner = true, counts = {} }) {
  const allTabs = [
    { id: "uploads",     label: "Uploads",     icon: "upload" },
    { id: "collections", label: "Collections", icon: "folder" },
    { id: "favorites",   label: "Favorites",   icon: "star", ownerOnly: false },
    { id: "likes",       label: "Likes",       icon: "heart", ownerOnly: false },
    { id: "downloads",   label: "Downloads",   icon: "dl", ownerOnly: true },
    { id: "ledger",      label: "Coin ledger", icon: "bolt", ownerOnly: true },
  ];
  const tabs = isOwner ? allTabs : allTabs.filter((t) => !t.ownerOnly);
  return (
    <div className="ptabs">
      {tabs.map((t) => {
        const Icon = I[t.icon];
        const c = counts[t.id];
        return (
          <button key={t.id} className={t.id === active ? "is-active" : ""}>
            <Icon size={13} />
            <span>{t.label}</span>
            {c !== undefined && <span className="ptab-count">{c}</span>}
          </button>
        );
      })}
    </div>
  );
}

// ─── Privacy notice ──────────────────────────────────────────────────

function PrivacyNotice({ listName = "list", isOwner = true, isPublic = false }) {
  if (!isOwner) {
    // Viewing someone else's hidden list
    return (
      <div className="priv-notice">
        <div className="priv-icon"><I.lock size={16} /></div>
        <div>
          <div className="priv-title">This {listName} is private</div>
          <div className="priv-sub">The owner has chosen not to share it.</div>
        </div>
        <span />
      </div>
    );
  }
  // Owner — show toggle
  return (
    <div className="priv-notice">
      <div className="priv-icon"><I.lock size={16} /></div>
      <div>
        <div className="priv-title">Your {listName} is {isPublic ? "public" : "private"}</div>
        <div className="priv-sub">
          {isPublic
            ? "Anyone visiting your profile can see this list."
            : "Only you can see this list. Make it public to share what you collect."}
        </div>
      </div>
      <button style={{
        padding: "8px 14px", background: "var(--paper)",
        border: "1px solid var(--ink)", color: "var(--ink)",
        fontFamily: "var(--sans)", fontSize: 12, fontWeight: 500,
        borderRadius: 999, cursor: "pointer",
      }}>{isPublic ? "Make private" : "Make public"}</button>
    </div>
  );
}

// ─── Processing overlay ─────────────────────────────────────────────

function ProcessingOverlay({ progress = 32, sub = "Generating device variants" }) {
  return (
    <div className="proc-overlay">
      <span className="spinner" />
      <div className="proc-label">Processing · {progress}%</div>
      <div className="proc-sub">{sub}</div>
    </div>
  );
}
