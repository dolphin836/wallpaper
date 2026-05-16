/* macOS menu-bar app — popover redesign.
   Same editorial vocabulary as the web app (paper + ink + accent for value moments),
   adapted to a frosted-glass menu-bar popover hanging off the menu bar.
   Layout: Header → 2-column (Latest | Downloaded) → Footer. */

const MAC_LATEST = [
  { spec: SPECIMENS[3], pinned: "latest" },       // Bismuth — pinned hover so the action rail is visible in canvas
  { spec: SPECIMENS[1] },
  { spec: SPECIMENS[7], dynamic: true },           // dynamic wallpaper
  { spec: SPECIMENS[12] },
];

const MAC_DOWNLOADED = [
  { spec: SPECIMENS[0], isSet: true },             // currently applied
  { spec: SPECIMENS[15], dynamic: true },
  { spec: SPECIMENS[5], isMissing: true, pinned: "downloaded-missing" }, // file gone, pinned to show Re-download
  { spec: SPECIMENS[13] },
];

// ─── Sub-blocks ────────────────────────────────────────────────────

function MacHeader() {
  return (
    <header style={{
      padding: "14px 18px",
      display: "grid", gridTemplateColumns: "1fr auto auto", gap: 14,
      alignItems: "center",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
        <div style={{
          width: 36, height: 36, borderRadius: "50%",
          background: "var(--paper-2)", border: "1px solid var(--hair)",
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          fontFamily: "var(--display)", fontSize: 18,
        }}>M</div>
        <div style={{ minWidth: 0 }}>
          <div className="display" style={{ fontSize: 17, lineHeight: 1.1 }}>Marin K.</div>
          <div style={{
            fontFamily: "var(--mono)", fontSize: 10,
            letterSpacing: "0.06em", color: "var(--muted)",
          }}>@marin.k</div>
        </div>
      </div>

      <div style={{
        display: "inline-flex", alignItems: "center", gap: 6,
        padding: "5px 11px 5px 5px",
        background: "var(--ink)",
        borderRadius: 999,
      }}>
        <span style={{
          width: 18, height: 18, borderRadius: "50%",
          background: "var(--accent)",
          boxShadow: "inset 0 -2px 0 oklch(48% 0.16 42), inset 0 1px 0 oklch(80% 0.16 60)",
          display: "inline-block", flexShrink: 0,
        }} />
        <span style={{
          fontFamily: "var(--mono)", fontWeight: 600, fontSize: 13,
          color: "var(--paper)", letterSpacing: "0.02em",
        }}>364</span>
      </div>

      <button title="Sign out" style={{
        width: 32, height: 32, borderRadius: 999,
        background: "transparent",
        border: "1px solid var(--hair)",
        color: "var(--ink-2)",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
        cursor: "pointer",
      }}>
        <I.logout size={13} />
      </button>
    </header>
  );
}

function MacTile({ spec, isSet, isMissing, dynamic, pinned, kind }) {
  return (
    <div className={`mac-tile ${pinned ? "is-pinned" : ""}`}>
      <img src={picsum(spec.seed, 800, 500)} alt="" />

      {/* Always-on chips top-left */}
      <div style={{
        position: "absolute", top: 9, left: 9,
        display: "flex", gap: 5,
      }}>
        <span className="mac-tag">{spec.res}</span>
        {(spec.dynamic || dynamic) && (
          <span className="mac-tag">
            <I.apple size={9} /> Mac
          </span>
        )}
      </div>

      {/* Right-side state chips */}
      <div style={{
        position: "absolute", top: 9, right: 9,
        display: "flex", gap: 5,
      }}>
        {isSet && <span className="mac-tag mac-tag--live"><I.check size={9} stroke={2.4} /> Active</span>}
        {isMissing && <span className="mac-tag" style={{ background: "#9a6a18" }}><I.lock size={9} /> Local missing</span>}
      </div>

      {/* Hover dark gradient + action buttons */}
      <div className="mac-grad" />
      <div className="mac-actions">
        {kind === "latest" && (
          <>
            <button className="mac-btn"><I.dl size={11} /> Download</button>
            <button className="mac-btn mac-btn--primary">
              <I.dl size={11} /><I.set size={10} /> Set & download
            </button>
          </>
        )}
        {kind === "downloaded" && (
          <>
            {isMissing && (
              <button className="mac-btn"><I.refresh size={11} /> Re-download</button>
            )}
            <button className="mac-btn mac-btn--primary">
              <I.set size={11} /> Set as wallpaper
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function MacColumn({ title, icon: HeaderIcon, items, kind,
                     dynamicFilter = false, shuffle = false, hasShuffle = false }) {
  return (
    <div style={{
      display: "flex", flexDirection: "column",
      minHeight: 0, minWidth: 0,
      padding: "14px 14px 0",
    }}>
      {/* Column heading */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        marginBottom: 12,
      }}>
        <div style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
          {HeaderIcon && <HeaderIcon size={14} stroke={1.5} />}
          <span className="display" style={{ fontSize: 18, lineHeight: 1 }}>{title}</span>
        </div>
        <div style={{ display: "inline-flex", gap: 6 }}>
          {hasShuffle && (
            <button className={`mac-toggle ${shuffle ? "is-on" : ""}`}
                    title="Auto-shuffle every 4 hours">
              <I.shuffle size={11} />
              {shuffle ? "Shuffle 4h" : "Shuffle"}
            </button>
          )}
          <button className={`mac-toggle ${dynamicFilter ? "is-on" : ""}`}
                  title="Show only macOS dynamic wallpapers">
            <I.apple size={11} />
            Dynamic
          </button>
        </div>
      </div>

      {/* Optional shuffle banner — only on Downloaded when shuffle is on */}
      {shuffle && (
        <div className="mac-banner" style={{ marginBottom: 10 }}>
          <span className="mac-banner-glyph"><I.shuffle size={11} /></span>
          <span>
            <strong>Auto-shuffle is on.</strong> Pulling from your downloads every 4 hours.
          </span>
          <span className="mac-banner-time">NEXT · 2 H 34 M</span>
        </div>
      )}

      {/* Item list — scrolls within the column */}
      <div style={{
        flex: 1, minHeight: 0,
        display: "flex", flexDirection: "column", gap: 10,
        overflowY: "hidden", paddingBottom: 12,
      }}>
        {items.map((it, i) => (
          <MacTile key={i} {...it} kind={kind} />
        ))}
      </div>
    </div>
  );
}

function MacFooter() {
  return (
    <footer style={{
      padding: "11px 18px",
      display: "flex", alignItems: "center", justifyContent: "space-between",
      borderTop: "1px solid var(--hair)",
      background: "rgba(255,255,255,0.45)",
    }}>
      <div style={{ display: "flex", gap: 16 }}>
        <button style={{
          display: "inline-flex", alignItems: "center", gap: 6,
          background: "transparent", border: "none", padding: 0,
          fontFamily: "var(--sans)", fontSize: 12, color: "var(--ink-2)", cursor: "pointer",
        }}>
          <I.power size={13} /> Quit
        </button>
        <button style={{
          display: "inline-flex", alignItems: "center", gap: 6,
          background: "transparent", border: "none", padding: 0,
          fontFamily: "var(--sans)", fontSize: 12, color: "var(--ink-2)", cursor: "pointer",
        }}>
          <I.external size={13} /> Open in browser
        </button>
      </div>
      <span style={{
        fontFamily: "var(--mono)", fontSize: 10,
        letterSpacing: "0.1em", color: "var(--muted)",
      }}>v 2.4.0</span>
    </footer>
  );
}

// ─── The Popover ─────────────────────────────────────────────────

function MacPopover({ dynLatest = false, dynDl = false, shuffle = false }) {
  return (
    <div style={{ position: "relative", width: 720 }}>
      <div className="mac-popover" style={{ width: 720, height: 700 }}>
        <MacHeader />
        <div style={{
          display: "grid", gridTemplateColumns: "1fr 1fr",
          borderTop: "1px solid var(--hair)",
          height: "calc(100% - 64px - 44px)",
          // 64 = header; 44 = footer
        }}>
          {/* Vertical hairline divider between columns */}
          <MacColumn title="Latest" icon={I.bolt} items={MAC_LATEST}
                     kind="latest" dynamicFilter={dynLatest} />
          <div style={{ borderLeft: "1px solid var(--hair)" }}>
            <MacColumn title="Downloaded" icon={I.dl} items={MAC_DOWNLOADED}
                       kind="downloaded" hasShuffle dynamicFilter={dynDl} shuffle={shuffle} />
          </div>
        </div>
        <MacFooter />
      </div>

      {/* The tail/triangle that connects to the menu-bar icon */}
      <span className="mac-tail" />
    </div>
  );
}

// ─── Artboards ─────────────────────────────────────────────────

/* The popover floats in front of a Mac desktop with a fake menu bar at the
   top. This gives users context for what the popover looks like in real use. */

function MacDesktopFrame({ children, wallpaperIdx = 3 }) {
  const wp = SPECIMENS[wallpaperIdx];
  return (
    <div style={{
      width: 1440, height: 1040,
      position: "relative", overflow: "hidden",
      background: "#000",
      fontFamily: "var(--sans)",
    }}>
      {/* Desktop wallpaper */}
      <img src={picsum(wp.seed, 2000, 1400)} alt=""
           style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
      <div style={{
        position: "absolute", inset: 0,
        background: "linear-gradient(180deg, rgba(0,0,0,0.18), rgba(0,0,0,0) 16%)",
      }} />

      {/* Menu bar */}
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 28,
        background: "rgba(0,0,0,0.18)",
        backdropFilter: "blur(20px) saturate(1.4)",
        display: "flex", alignItems: "center", padding: "0 14px", gap: 18,
        color: "#fff", fontSize: 13,
      }}>
        <I.apple size={14} />
        <span style={{ fontWeight: 600 }}>Finder</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span>Go</span>
        <span>Window</span>
        <span>Help</span>

        <span style={{ marginLeft: "auto", display: "inline-flex", gap: 14, alignItems: "center" }}>
          {/* The Wallpaper Exchange menu bar icon — highlighted because the popover is anchored to it */}
          <span style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            width: 24, height: 22, borderRadius: 5,
            background: "rgba(255,255,255,0.2)", color: "#fff",
            fontFamily: "var(--display)", fontSize: 14,
            border: "1px solid rgba(255,255,255,0.3)",
          }}>W</span>
          <I.search size={13} />
          <span style={{
            fontFamily: "var(--mono)", fontSize: 12, letterSpacing: "0.04em",
          }}>Fri 15 May · 14:02</span>
        </span>
      </div>

      {/* Popover anchored below the W icon. The W icon sits ~96px from the
          right edge; the popover is 720px wide centered roughly under it. */}
      <div style={{
        position: "absolute",
        top: 34,
        right: 80,
      }}>
        {children}
      </div>
    </div>
  );
}

function MacPopoverDefault() {
  return <MacDesktopFrame><MacPopover /></MacDesktopFrame>;
}
function MacPopoverFiltered() {
  return <MacDesktopFrame><MacPopover dynLatest dynDl /></MacDesktopFrame>;
}
function MacPopoverShuffle() {
  return <MacDesktopFrame><MacPopover shuffle /></MacDesktopFrame>;
}

Object.assign(window, {
  MacHeader, MacColumn, MacTile, MacFooter, MacPopover, MacDesktopFrame,
  MacPopoverDefault, MacPopoverFiltered, MacPopoverShuffle,
});
