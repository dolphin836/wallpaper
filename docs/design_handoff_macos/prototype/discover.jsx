/* Discover — Salon Wall layout with all controls + hover/action states. */

function DiscoverControls({ feed = "latest", deviceFilter = false, macFilter = false, sort = "latest",
                            viewMode = "justified", sizeMode = "md", auth = "in" }) {
  const segBtn = (isOn) => ({
    padding: "8px 16px",
    fontSize: 12,
    fontFamily: "var(--sans)",
    fontWeight: 500,
    borderRadius: 999,
    color: isOn ? "var(--ink)" : "var(--muted)",
    background: isOn ? "var(--paper)" : "transparent",
    border: "none",
    boxShadow: isOn ? "0 1px 0 var(--hair), 0 0 0 1px var(--hair)" : "none",
  });

  const filterChip = (active) => ({
    display: "inline-flex", alignItems: "center", gap: 6,
    padding: "8px 14px", fontSize: 12, fontFamily: "var(--sans)", fontWeight: 500,
    borderRadius: 999,
    color: active ? "#fff" : "var(--ink-2)",
    background: active ? "var(--accent)" : "var(--paper)",
    border: `1px solid ${active ? "transparent" : "var(--hair)"}`,
  });

  return (
    <div style={{
      display: "flex", alignItems: "center", justifyContent: "space-between",
      gap: 16, flexWrap: "wrap", padding: "20px 32px 16px",
      borderBottom: "1px solid var(--hair)", background: "var(--paper)",
    }}>
      {/* Left: feed segment + filters */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        {auth === "in" && (
          <div style={{
            display: "flex", alignItems: "center", padding: 3, gap: 2,
            background: "var(--paper-2)", border: "1px solid var(--hair)", borderRadius: 999,
          }}>
            <button style={segBtn(feed === "latest")}>Latest</button>
            <button style={segBtn(feed === "for_you")}>For You</button>
          </div>
        )}

        <button style={filterChip(deviceFilter)}>
          <I.monitor size={13} />
          {deviceFilter ? "5120 × 2880" : "My Device"}
        </button>
        <button style={filterChip(macFilter)}>
          <I.apple size={12} />
          macOS
        </button>
      </div>

      {/* Right: view + size + sort */}
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        {/* View toggle */}
        <div style={{
          display: "flex", alignItems: "center", padding: 3, gap: 2,
          background: "var(--paper-2)", border: "1px solid var(--hair)", borderRadius: 8,
        }}>
          <button style={{
            width: 30, height: 26, borderRadius: 5, border: "none",
            background: viewMode === "justified" ? "var(--ink)" : "transparent",
            color: viewMode === "justified" ? "var(--paper)" : "var(--muted)",
            display: "flex", alignItems: "center", justifyContent: "center",
          }} title="Salon (justified)">
            <I.grid size={13} />
          </button>
          <button style={{
            width: 30, height: 26, borderRadius: 5, border: "none",
            background: viewMode === "grid" ? "var(--ink)" : "transparent",
            color: viewMode === "grid" ? "var(--paper)" : "var(--muted)",
            display: "flex", alignItems: "center", justifyContent: "center",
          }} title="Grid">
            <I.rows size={13} />
          </button>
        </div>

        {/* Size toggle — uses sm/md/lg keys (matches HomePage SIZE_KEYS) */}
        <div style={{
          display: "inline-flex", alignItems: "center",
          background: "var(--paper-2)", border: "1px solid var(--hair)", borderRadius: 8,
          padding: 3, gap: 2,
        }}>
          {[["sm", "S"], ["md", "M"], ["lg", "L"]].map(([key, label]) => {
            const isOn = sizeMode === key;
            return (
              <button key={key} style={{
                minWidth: 30, height: 26, borderRadius: 5, border: "none",
                background: isOn ? "var(--ink)" : "transparent",
                color: isOn ? "var(--paper)" : "var(--muted)",
                fontFamily: "var(--mono)", fontSize: 11,
                fontWeight: isOn ? 600 : 500, letterSpacing: "0.04em",
                padding: "0 9px",
                boxShadow: isOn ? "0 1px 2px rgba(0,0,0,0.18)" : "none",
                transition: "background 140ms ease, color 140ms ease",
              }} title={`Size · ${label}`}>{label}</button>
            );
          })}
        </div>

        {/* Sort */}
        <button style={{
          display: "inline-flex", alignItems: "center", gap: 12, height: 32,
          padding: "0 14px", borderRadius: 8,
          background: "var(--paper-2)", border: "1px solid var(--hair)",
          fontFamily: "var(--sans)", fontSize: 12, color: "var(--ink-2)",
        }}>
          <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)", letterSpacing: "0.1em" }}>SORT</span>
          {sort === "trending" ? "Trending" : "Latest"}
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M5 9l7 7 7-7" strokeLinecap="round" strokeLinejoin="round" /></svg>
        </button>
      </div>
    </div>
  );
}

/* A single tile — always-on top-left badges, hover-revealed bottom-right
   action rail with persisted selected states. `pinned` keeps the rail
   visible in static screenshots so all three selected states are visible. */

function SalonTile({ spec, feat, pinned = false, state = {} }) {
  const { liked = false, favorited = false, downloaded = false } = state;
  return (
    <div className={`tile-cell ${pinned ? "is-pinned" : ""}`} style={{
      position: "relative", overflow: "hidden",
      border: "1px solid var(--hair)",
      background: spec.color,
      width: "100%", height: "100%",
    }}>
      <img
        className="tile-img"
        src={picsum(spec.seed, 1200, 900)}
        style={{
          position: "absolute", inset: 0,
          width: "100%", height: "100%", objectFit: "cover", display: "block",
        }}
        loading="lazy"
      />

      {/* Hover-only darkening — covers the action rail area for icon legibility.
          Sits at opacity 0 and rises to 1 via .tile-cell:hover .tile-gradient. */}
      <div className="tile-gradient" style={{
        position: "absolute", inset: 0, opacity: 0,
        background: "linear-gradient(180deg, rgba(0,0,0,0.18) 0%, rgba(0,0,0,0) 30%, rgba(0,0,0,0) 60%, rgba(0,0,0,0.28) 100%)",
        pointerEvents: "none",
      }} />

      {/* Always-on top-left badges — resolution + macOS only */}
      <div style={{
        position: "absolute", top: 12, left: 12,
        display: "flex", gap: 6, flexWrap: "wrap", maxWidth: "calc(100% - 24px)",
      }}>
        <span style={{
          padding: "3px 8px", background: "rgba(0,0,0,0.55)", color: "#fff",
          borderRadius: 3, fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.06em",
          backdropFilter: "blur(8px)", fontWeight: 500,
        }}>{spec.res}</span>
        {spec.dynamic && (
          <span style={{
            padding: "3px 8px", background: "rgba(0,0,0,0.55)", color: "#fff", borderRadius: 3,
            fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.06em",
            display: "inline-flex", alignItems: "center", gap: 5, backdropFilter: "blur(8px)",
            fontWeight: 500,
          }}>
            <I.apple size={10} /> Mac
          </span>
        )}
      </div>

      {/* Hover-revealed action rail (bottom-right column) */}
      <div className="tile-actions">
        <button className={`t-act ${favorited ? "is-favorited" : ""}`} title={favorited ? "Favorited" : "Favorite"}>
          {favorited ? <I.starFill size={15} /> : <I.star size={15} />}
        </button>
        <button className={`t-act ${liked ? "is-liked" : ""}`} title={liked ? "Liked" : "Like"}>
          {liked ? <I.heartFill size={15} /> : <I.heart size={15} />}
        </button>
        <button className={`t-act ${downloaded ? "is-downloaded" : ""}`} title={downloaded ? "Downloaded" : "Download"}>
          {downloaded ? <I.check size={15} /> : <I.dl size={15} />}
        </button>
      </div>
    </div>
  );
}

/* Salon mosaic — fixed asymmetric layout. `pinnedIds` shows the hover state
   on selected tiles so all interaction states are visible in static screenshots. */

function SalonMosaic({ items, layout, demoStates = {}, pinnedIds = [] }) {
  return (
    <div style={{
      display: "grid", gridTemplateColumns: "repeat(11, 1fr)",
      gridAutoRows: 145, gap: 8, padding: 24,
    }}>
      {layout.map(({ idx, col, row, feat }, i) => {
        const spec = items[idx];
        const id = spec.id;
        return (
          <div key={i} style={{ gridColumn: col, gridRow: row, position: "relative" }}>
            <SalonTile
              spec={spec}
              feat={feat}
              pinned={pinnedIds.includes(id)}
              state={demoStates[id] || {}}
            />
          </div>
        );
      })}
    </div>
  );
}

// Hand-tuned salon-style mosaic
const SALON_LAYOUT = [
  { idx: 0,  col: "1 / 5",  row: "1 / 3" },
  { idx: 1,  col: "5 / 8",  row: "1 / 4" },
  { idx: 3,  col: "8 / 12", row: "1 / 3", feat: true },
  { idx: 2,  col: "1 / 4",  row: "3 / 5" },
  { idx: 5,  col: "4 / 6",  row: "3 / 4" },
  { idx: 6,  col: "6 / 9",  row: "4 / 6" },
  { idx: 8,  col: "9 / 12", row: "3 / 5" },
  { idx: 7,  col: "1 / 3",  row: "5 / 6" },
  { idx: 12, col: "3 / 6",  row: "5 / 6" },
  { idx: 9,  col: "9 / 12", row: "5 / 6" },
];

// Demo: a handful of selected states so user can see filled icons in canvas
const DEMO_STATES = {
  2:  { liked: true },                                    // Tokyo
  4:  { favorited: true, downloaded: true },              // Bismuth (Editor's pick)
  6:  { downloaded: true },                               // Concrete
  9:  { liked: true, favorited: true },                   // Market light
  13: { favorited: true },                                // Tide pool
};
// Pin the featured + one other so action rail is visible without hover
const PINNED_IDS = [4, 6];

/* Feed footer — three states for the bottom of the infinite scroll.
   `state` is one of: "loading" (auto-fetch in progress, normally hidden
   above the fold), "retry" (auto-fetch failed; manual retry CTA),
   "end" (all loaded, friendly sign-off). */

function FeedFooter({ state = "loading", count = 1284 }) {
  if (state === "loading") {
    return (
      <div className="feed-foot">
        <div className="feed-foot__inner">
          <span className="spinner" />
          <span style={{ fontFamily: "var(--mono)", fontSize: 11, letterSpacing: "0.12em", color: "var(--muted)", textTransform: "uppercase" }}>
            Loading more specimens
          </span>
        </div>
      </div>
    );
  }

  if (state === "retry") {
    return (
      <div className="feed-foot">
        <div className="feed-foot__inner" style={{ flexDirection: "column", gap: 12 }}>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
            <span className="btn-load-more__warn" />
            <span style={{ fontFamily: "var(--mono)", fontSize: 11, letterSpacing: "0.12em", color: "var(--muted)", textTransform: "uppercase" }}>
              Couldn't auto-load · network hiccup
            </span>
          </div>
          <button className="btn-load-more">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 12a9 9 0 1 0 3-6.7" />
              <path d="M3 4v5h5" />
            </svg>
            Load more
          </button>
        </div>
      </div>
    );
  }

  // end
  return (
    <div className="feed-foot">
      <div className="feed-foot__rule" />
      <div className="feed-foot__inner">
        <span className="display italic-d" style={{ fontSize: 18, color: "var(--ink-2)" }}>
          end of the archive
        </span>
        <span style={{ fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.14em", color: "var(--muted)", textTransform: "uppercase" }}>
          {count.toLocaleString()} specimens · vol. 14
        </span>
      </div>
      <div className="feed-foot__rule" />
    </div>
  );
}

function DiscoverSalon({ auth = "in", footerState = "loading" }) {
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Discover" auth={auth} />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth={auth} />

        <DiscoverControls auth={auth} />

        <main style={{ overflow: "hidden", background: "var(--paper-2)", flex: 1, display: "flex", flexDirection: "column" }}>
          <SalonMosaic
            items={SPECIMENS}
            layout={SALON_LAYOUT}
            demoStates={DEMO_STATES}
            pinnedIds={PINNED_IDS}
          />
          <FeedFooter state={footerState} />
        </main>
      </div>
    </div>
  );
}

Object.assign(window, {
  DiscoverSalon, DiscoverControls, SalonMosaic, SalonTile,
  SALON_LAYOUT, DEMO_STATES, PINNED_IDS, FeedFooter,
});
