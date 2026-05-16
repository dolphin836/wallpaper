/* Wallpaper detail — Editorial Spread.
   V3 changes:
   - Removed the "№001 / in nature" hero lead. Right column now reads as
     a structured spec card; the plate header (left) carries the № reference.
   - Added Palette (5 dominant colors) and Available Devices (per-device fit).
   - Removed Tags, License, and the Follow button.
   - Action buttons: Like, Favorite, Add to Collection (toggleable) +
     Fullscreen Preview, Preview on Device (interactive secondary actions).
   - One extra artboard shows the "Add to Collection" popover open. */

// Hand-tuned palette per specimen (5 swatches, light → dark)
const PALETTES = {
  1:  ["#f2e6d4", "#e3c19e", "#c9966a", "#8b5a35", "#1a0f08"],
  4:  ["#d9c5e6", "#a374cc", "#7a3aa8", "#4a1d6a", "#1a0b2e"],
  // fallback
  __: ["#f0eee6", "#cfcabc", "#928a72", "#56503e", "#1a160e"],
};

function paletteFor(spec) {
  return PALETTES[spec.id] || PALETTES.__;
}

// Map the `res` label to a numeric tier so we can decide device fit.
const RES_TIER = { "1080P": 1, "2K": 2, "3K": 2.5, "4K": 3, "5K": 4, "6K": 5, "8K": 7 };

// Approximate per-device file size at JPEG quality ~85.
// (Real value would come from the server after the per-device variant is generated.)
function estSize(w, h) {
  const mb = (w * h * 0.42) / (1024 * 1024);
  return mb < 1 ? `${(mb * 1024).toFixed(0)} KB` : `${mb.toFixed(1)} MB`;
}

function deviceFits(spec) {
  const isPortrait = spec.h > spec.w;
  const tier = RES_TIER[spec.res] || 3;
  const fit = (need) => tier >= need ? "ok" : "upscale";
  if (isPortrait) {
    return [
      { name: "iPhone 15",           w: 1179, h: 2556, icon: "phone",  fit: fit(2),   size: estSize(1179, 2556) },
      { name: "iPhone 15 Pro Max",   w: 1290, h: 2796, icon: "phone",  fit: fit(2.5), size: estSize(1290, 2796) },
      { name: "iPad Pro 12.9″",      w: 2048, h: 2732, icon: "tablet", fit: fit(3),   size: estSize(2048, 2732) },
      { name: "Apple Watch Ultra",   w: 410,  h: 502,  icon: "phone",  fit: "ok",     size: estSize(410, 502) },
    ];
  }
  return [
    { name: "MacBook Pro 14″",     w: 3024, h: 1964, icon: "laptop",  fit: fit(3), size: estSize(3024, 1964) },
    { name: "MacBook Pro 16″",     w: 3456, h: 2234, icon: "laptop",  fit: fit(3), size: estSize(3456, 2234) },
    { name: "Studio Display 5K",   w: 5120, h: 2880, icon: "desktop", fit: fit(4), size: estSize(5120, 2880) },
    { name: "Pro Display XDR 6K",  w: 6016, h: 3384, icon: "proDisp", fit: fit(5), size: estSize(6016, 3384) },
  ];
}

// ─── Sub-blocks ────────────────────────────────────────────────────────

function PaletteBlock({ spec }) {
  const colors = paletteFor(spec);
  return (
    <section>
      <div className="kicker" style={{ color: "var(--muted)" }}>Palette · 5 colors</div>
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8, marginTop: 10,
      }}>
        {colors.map((c, i) => (
          <div key={c + i}>
            <div className="swatch" style={{ background: c, height: 52, borderRadius: 2 }}
                 title={`${c.toUpperCase()} — click to copy`} />
            <span className="swatch-hex">{c.toUpperCase()}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function DevicesBlock({ spec, currentDevice = 'MacBook Pro 14″' }) {
  const fits = deviceFits(spec);
  return (
    <section>
      <div className="kicker" style={{ color: "var(--muted)" }}>Available devices</div>
      <div style={{ marginTop: 8, paddingTop: 0, borderTop: "1px solid var(--hair)" }}>
        {fits.map((d) => {
          const Icon = I[d.icon];
          const isCurrent = d.name === currentDevice;
          const previewAvailable = d.fit === "ok";
          return (
            <div key={d.name} className={`dev-row ${isCurrent ? "is-current" : ""}`}>
              <span className="dev-icon"><Icon size={18} /></span>
              <div className="dev-meta">
                <div className="dev-name-row">
                  <span className="dev-name">{d.name}</span>
                  {isCurrent && <span className="dev-badge">Your device</span>}
                </div>
                <div className="dev-spec">
                  <span>{d.w.toLocaleString()} × {d.h.toLocaleString()} px</span>
                  <span className="sep">·</span>
                  <span>{d.size}</span>
                  {d.fit === "upscale" && (
                    <>
                      <span className="sep">·</span>
                      <span style={{ color: "#9a6a18" }}>upscaled</span>
                    </>
                  )}
                </div>
              </div>
              <div className="dev-actions">
                <button
                  className={`dev-btn ${previewAvailable ? "" : "is-disabled"}`}
                  disabled={!previewAvailable}
                  title={previewAvailable ? "Preview on this device" : "Source resolution is too low to render a faithful preview"}
                >
                  <I.eye size={11} /> Preview
                </button>
                <button
                  className={`dev-btn ${isCurrent ? "dev-btn--accent" : "dev-btn--primary"}`}
                  title={`Download a ${d.w}×${d.h} variant`}
                >
                  <I.dl size={11} /> Download
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function SpecsBlock({ spec }) {
  return (
    <section>
      <div className="kicker" style={{ color: "var(--muted)" }}>Specifications</div>
      <dl style={{
        margin: "10px 0 0", display: "grid", gridTemplateColumns: "90px 1fr",
        rowGap: 10, fontSize: 13, fontFamily: "var(--mono)",
      }}>
        {[
          ["DIM",      `${spec.w.toLocaleString()} × ${spec.h.toLocaleString()} px`],
          ["RES",      <span>{spec.res}{spec.dynamic && <span style={{ color: "var(--accent)", marginLeft: 8 }}>● Dynamic</span>}</span>],
          ["FILE",     "JPEG · 6.8 MB"],
          ["DOMINANT", (
            <span>
              <span style={{
                display: "inline-block", width: 10, height: 10,
                background: spec.color, marginRight: 6, verticalAlign: "middle",
                border: "1px solid var(--hair)",
              }} />
              {spec.color.toUpperCase()}
            </span>
          )],
        ].map(([k, v]) => (
          <React.Fragment key={k}>
            <dt style={{
              color: "var(--muted)", letterSpacing: "0.12em",
              textTransform: "uppercase", fontSize: 10, paddingTop: 2,
            }}>{k}</dt>
            <dd style={{ margin: 0, color: "var(--ink)" }}>{v}</dd>
          </React.Fragment>
        ))}
      </dl>
    </section>
  );
}

/* Five action buttons.
   Row 1 — 3 toggleable: Like, Favorite, Add to collection.
   Row 2 — 2 action-tone: Fullscreen preview, Preview on device.
   `state` = { liked, favorited, collected, collectedCount, showCollectionsPopover } */

function ActionGrid({ spec, state = {} }) {
  const { liked = false, favorited = false, collected = false, collectedCount = 0,
          showCollectionsPopover = false } = state;
  return (
    <section style={{ position: "relative" }}>
      <div className="kicker" style={{ color: "var(--muted)" }}>Actions</div>

      {/* Toggleable row */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginTop: 10 }}>
        <button className={`btn-pill ${liked ? "is-liked" : ""}`}>
          {liked ? <I.heartFill size={15} /> : <I.heart size={15} />}
          <span className="label">{liked ? "Liked" : "Like"}</span>
          <span className="count">{fmt(spec.likes + (liked ? 1 : 0))}</span>
        </button>
        <button className={`btn-pill ${favorited ? "is-favorited" : ""}`}>
          {favorited ? <I.starFill size={15} /> : <I.star size={15} />}
          <span className="label">{favorited ? "Favorited" : "Favorite"}</span>
        </button>
        <button className={`btn-pill ${collected ? "is-collected" : ""}`}>
          <I.layers size={15} />
          <span className="label">
            {collected ? `In ${collectedCount} list${collectedCount > 1 ? "s" : ""}` : "Add to list"}
          </span>
        </button>
      </div>

      {/* Action-tone row */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 8 }}>
        <button className="btn-pill btn-pill--action">
          <span className="lhs">
            <span className="glyph"><I.eye size={15} /></span>
            <span>
              <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.1 }}>Fullscreen preview</div>
              <div style={{
                fontSize: 10, color: "var(--muted)", fontFamily: "var(--mono)",
                letterSpacing: "0.08em", marginTop: 3, textTransform: "uppercase",
              }}>Watermarked · free</div>
            </span>
          </span>
          <span className="arrow"><I.arrow size={13} /></span>
        </button>
        <button className="btn-pill btn-pill--action">
          <span className="lhs">
            <span className="glyph"><I.desktop size={15} /></span>
            <span>
              <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.1 }}>On device</div>
              <div style={{
                fontSize: 10, color: "var(--muted)", fontFamily: "var(--mono)",
                letterSpacing: "0.08em", marginTop: 3, textTransform: "uppercase",
              }}>Mockup preview</div>
            </span>
          </span>
          <span className="arrow"><I.arrow size={13} /></span>
        </button>
      </div>

      {/* Collections popover — anchored to the 3rd toggleable button */}
      {showCollectionsPopover && <CollectionsPopover />}
    </section>
  );
}

// Anchored popover for the Add-to-collection button.
// Positioned absolute to its parent <section>; the 3rd column ≈ right third.
function CollectionsPopover() {
  const lists = [
    { name: "Cool blues",      count: 24, active: false },
    { name: "Studio.glo set",  count: 8,  active: true  },
    { name: "Living room TV",  count: 12, active: false },
    { name: "Reference board", count: 47, active: false },
  ];
  return (
    <div style={{
      position: "absolute", right: 0, top: "calc(100% + 4px)",
      width: 280, padding: 14,
      background: "var(--paper)", border: "1px solid var(--ink)",
      boxShadow: "0 16px 40px rgba(0,0,0,0.18)",
      zIndex: 10, fontFamily: "var(--sans)",
    }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div className="kicker" style={{ color: "var(--muted)" }}>Add to a list</div>
        <button style={{
          width: 22, height: 22, borderRadius: 999, background: "transparent",
          border: "1px solid var(--hair)", color: "var(--ink-2)",
          display: "inline-flex", alignItems: "center", justifyContent: "center",
        }}><I.x size={11} /></button>
      </div>
      <ul style={{ listStyle: "none", padding: 0, margin: "10px 0 0",
                   borderTop: "1px solid var(--hair)" }}>
        {lists.map((l) => (
          <li key={l.name} style={{
            display: "flex", alignItems: "center", gap: 10,
            padding: "9px 0", borderBottom: "1px solid var(--hair)",
            fontSize: 13, cursor: "pointer",
          }}>
            <span style={{
              width: 14, height: 14, borderRadius: 3,
              border: `1.5px solid ${l.active ? "var(--accent)" : "var(--hair)"}`,
              background: l.active ? "var(--accent)" : "transparent",
              display: "inline-flex", alignItems: "center", justifyContent: "center",
              color: "#fff", flexShrink: 0,
            }}>
              {l.active && <I.check size={9} stroke={3} />}
            </span>
            <span style={{ flex: 1, color: "var(--ink)" }}>{l.name}</span>
            <span style={{
              fontFamily: "var(--mono)", fontSize: 10,
              color: "var(--muted)", letterSpacing: "0.06em",
            }}>{l.count}</span>
          </li>
        ))}
      </ul>
      <button style={{
        marginTop: 10, width: "100%", padding: "9px 12px",
        border: "1px dashed var(--hair)", background: "transparent",
        color: "var(--ink-2)", fontFamily: "var(--sans)", fontSize: 12,
        display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 6,
      }}>
        <I.plus size={13} /> New list
      </button>
    </div>
  );
}

// ─── SpreadBody — shared between modal + full page ─────────────────────

/* Bottom CTA — coin/exchange/download — with mode states:
   "default"      — initial, shows cost + balance + Download
   "confirm"      — confirmation step before the coin is deducted
   "insufficient" — balance < cost
   "success"      — after a successful download */

function CoinCTA({ spec, balance = 12, mode = "default", compact = false }) {
  const pad = compact ? 18 : 22;

  if (mode === "confirm") {
    return (
      <div style={{
        background: "var(--ink)", color: "var(--paper)", padding: pad,
        border: "2px solid var(--accent)",
      }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16 }}>
          <div style={{ minWidth: 0 }}>
            <div className="kicker" style={{ color: "var(--accent)" }}>CONFIRM EXCHANGE</div>
            <div className="display" style={{ fontSize: compact ? 30 : 36, lineHeight: 1, marginTop: 6 }}>
              −{spec.coins} <span style={{ color: "var(--accent)" }}>coin{spec.coins > 1 ? "s" : ""}</span>
            </div>
            <div style={{
              marginTop: 8, fontFamily: "var(--mono)", fontSize: 10,
              color: "rgba(255,255,255,0.55)", letterSpacing: "0.14em",
            }}>
              {balance} <span style={{ color: "var(--accent)" }}>→</span> {balance - spec.coins} COINS REMAINING
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8, flexShrink: 0 }}>
            <button style={{
              padding: compact ? "10px 18px" : "12px 22px",
              background: "var(--accent)", color: "#fff", border: "none",
              fontFamily: "var(--sans)", fontWeight: 600, fontSize: 13, borderRadius: 999,
              display: "inline-flex", alignItems: "center", gap: 10, cursor: "pointer",
            }}>
              <I.check size={14} stroke={2.2} /> Yes, exchange
            </button>
            <button style={{
              padding: compact ? "8px 16px" : "10px 20px",
              background: "transparent", color: "rgba(255,255,255,0.85)",
              border: "1px solid rgba(255,255,255,0.18)",
              fontFamily: "var(--sans)", fontSize: 12, borderRadius: 999, cursor: "pointer",
            }}>
              Cancel
            </button>
          </div>
        </div>
        <hr style={{ border: 0, borderTop: "1px solid rgba(255,255,255,0.12)", margin: "14px 0 10px" }} />
        <label style={{
          display: "inline-flex", alignItems: "center", gap: 8,
          fontFamily: "var(--sans)", fontSize: 11, color: "rgba(255,255,255,0.6)", cursor: "pointer",
        }}>
          <span style={{
            width: 13, height: 13, borderRadius: 3, border: "1px solid rgba(255,255,255,0.4)",
            background: "transparent", display: "inline-flex",
          }} />
          Don't ask again for this session
        </label>
      </div>
    );
  }

  if (mode === "insufficient") {
    const need = spec.coins - balance;
    return (
      <div style={{
        background: "oklch(96% 0.05 70)", color: "var(--ink)", padding: pad,
        border: "1px solid #b07a1a",
      }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16 }}>
          <div style={{ minWidth: 0 }}>
            <div className="kicker" style={{ color: "#9a6a18", letterSpacing: "0.14em" }}>
              INSUFFICIENT COINS
            </div>
            <div className="display" style={{
              fontSize: compact ? 30 : 36, lineHeight: 1, marginTop: 6, color: "#5e3f08",
            }}>
              Need <span style={{ color: "#9a6a18" }}>{need}</span> more
            </div>
            <div style={{
              marginTop: 8, fontFamily: "var(--mono)", fontSize: 10,
              color: "#9a6a18", letterSpacing: "0.14em",
            }}>
              YOUR BALANCE · {balance} COINS  ·  COST · {spec.coins}
            </div>
          </div>
          <a href="#" style={{
            padding: compact ? "12px 18px" : "14px 22px",
            background: "#9a6a18", color: "#fff", border: "none",
            fontFamily: "var(--sans)", fontWeight: 600, fontSize: 13, borderRadius: 999,
            display: "inline-flex", alignItems: "center", gap: 10, cursor: "pointer",
            textDecoration: "none", flexShrink: 0,
          }}>
            <I.upload size={14} /> Upload to earn
          </a>
        </div>
        <hr style={{ border: 0, borderTop: "1px solid rgba(154,106,24,0.28)", margin: "14px 0 10px" }} />
        <div style={{
          display: "flex", gap: 22, fontFamily: "var(--sans)", fontSize: 12, color: "#5e3f08",
          flexWrap: "wrap",
        }}>
          <span><strong style={{ color: "#9a6a18", fontFamily: "var(--mono)", marginRight: 6 }}>+5</strong>each upload</span>
          <span><strong style={{ color: "#9a6a18", fontFamily: "var(--mono)", marginRight: 6 }}>+1</strong>daily check-in</span>
          <span><strong style={{ color: "#9a6a18", fontFamily: "var(--mono)", marginRight: 6 }}>+1</strong>others download yours</span>
        </div>
      </div>
    );
  }

  if (mode === "success") {
    const remaining = balance - spec.coins;
    return (
      <div style={{
        background: "oklch(95% 0.05 150)", color: "var(--ink)", padding: pad,
        border: "1px solid #2f6b3e",
      }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16 }}>
          <div style={{ minWidth: 0 }}>
            <div className="kicker" style={{ color: "#2f6b3e", letterSpacing: "0.14em",
              display: "inline-flex", alignItems: "center", gap: 6 }}>
              <I.check size={11} stroke={2.4} /> DOWNLOADED
            </div>
            <div className="display" style={{
              fontSize: compact ? 28 : 32, lineHeight: 1.05, marginTop: 6, color: "#1f4827",
            }}>
              wallpaper_<span className="mono" style={{ fontSize: compact ? 22 : 26 }}>
                {String(spec.id).padStart(3, "0")}
              </span>.jpg
            </div>
            <div style={{
              marginTop: 8, fontFamily: "var(--mono)", fontSize: 10,
              color: "#2f6b3e", letterSpacing: "0.14em",
            }}>
              6.8 MB  ·  {remaining} COINS REMAINING
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8, flexShrink: 0 }}>
            <button style={{
              padding: compact ? "10px 18px" : "12px 20px",
              background: "var(--ink)", color: "var(--paper)", border: "none",
              fontFamily: "var(--sans)", fontWeight: 500, fontSize: 12, borderRadius: 999,
              display: "inline-flex", alignItems: "center", gap: 8, cursor: "pointer",
            }}>
              Show in Downloads
            </button>
            <button style={{
              padding: compact ? "8px 16px" : "10px 18px",
              background: "transparent", color: "var(--ink)",
              border: "1px solid var(--hair)",
              fontFamily: "var(--sans)", fontSize: 12, borderRadius: 999, cursor: "pointer",
              display: "inline-flex", alignItems: "center", gap: 8, justifyContent: "center",
            }}>
              Browse more →
            </button>
          </div>
        </div>
        <hr style={{ border: 0, borderTop: "1px solid rgba(47,107,62,0.25)", margin: "14px 0 10px" }} />
        <div style={{
          display: "flex", gap: 14, fontFamily: "var(--sans)", fontSize: 12, color: "#1f4827",
          alignItems: "center",
        }}>
          <I.apple size={13} />
          <span>
            On macOS? Use the menu-bar app to set this as your wallpaper in one click.
            <a href="#" style={{ marginLeft: 6, color: "#2f6b3e", textDecoration: "underline" }}>Get it →</a>
          </span>
        </div>
      </div>
    );
  }

  // Default
  return (
    <div style={{
      border: "1px solid var(--ink)", background: "var(--ink)", color: "var(--paper)",
      padding: pad,
      display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16,
    }}>
      <div style={{ minWidth: 0 }}>
        <div style={{
          fontFamily: "var(--mono)", fontSize: 10,
          color: "rgba(255,255,255,0.55)", letterSpacing: "0.14em",
        }}>EXCHANGE FOR</div>
        <div className="display" style={{ fontSize: compact ? 32 : 40, lineHeight: 1, marginTop: 4 }}>
          {spec.coins} <span style={{ color: "var(--accent)" }}>coin{spec.coins > 1 ? "s" : ""}</span>
        </div>
        <div style={{
          marginTop: 6, fontFamily: "var(--mono)", fontSize: 10,
          color: "rgba(255,255,255,0.55)",
        }}>YOUR BALANCE · {balance} COINS</div>
      </div>
      <button style={{
        padding: compact ? "12px 18px" : "14px 22px",
        background: "var(--accent)", color: "#fff", border: "none",
        fontFamily: "var(--sans)", fontWeight: 600, fontSize: 13, borderRadius: 999,
        display: "inline-flex", alignItems: "center", gap: 10, flexShrink: 0,
        cursor: "pointer",
      }}>
        <I.dl size={15} /> Download original
      </button>
    </div>
  );
}

function SpreadBody({ spec, related = [], compact = false, actionState = {}, downloadMode = "default", balance = 12 }) {
  return (
    <div style={{
      display: "grid", gridTemplateColumns: compact ? "1.3fr 1fr" : "1.4fr 1fr",
      gap: compact ? 28 : 36,
      padding: compact ? "26px 32px" : "32px 40px",
      overflow: "hidden", minHeight: 0, flex: 1,
    }}>
      {/* LEFT — plate + stats + (full-page only) related */}
      <div style={{ minWidth: 0, display: "flex", flexDirection: "column" }}>
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          marginBottom: 12, fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.18em",
          color: "var(--muted)", textTransform: "uppercase",
        }}>
          <span>Plate №{String(spec.id).padStart(3, "0")}</span>
          <span>{spec.w}×{spec.h} · {spec.res} · dominant {spec.color.toUpperCase()}</span>
        </div>

        <div style={{ position: "relative" }}>
          <Tile spec={spec} />
          <Brackets color="var(--ink)" inset={-1} size={18} />
        </div>

        {/* Stats strip */}
        <div style={{
          marginTop: 14, display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr",
          border: "1px solid var(--hair)", borderRight: "none",
        }}>
          {[
            ["DOWNLOADS", fmt(spec.downloads)],
            ["LIKES",     fmt(spec.likes)],
            ["FAVORITED", fmt(Math.round(spec.likes * 0.18))],
            ["VIEWS",     fmt(spec.likes * 4)],
          ].map(([k, v]) => (
            <div key={k} style={{ padding: "12px 14px", borderRight: "1px solid var(--hair)" }}>
              <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--muted)" }}>{k}</div>
              <div className="display" style={{ fontSize: 24, lineHeight: 1, marginTop: 4 }}>{v}</div>
            </div>
          ))}
        </div>

        {!compact && related.length > 0 && (
          <>
            <div className="label-rule" style={{ margin: "28px 0 14px" }}>
              MORE FROM @{spec.author.toUpperCase()} · {related.length}
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12 }}>
              {related.map(r => (
                <div key={r.id}>
                  <Tile spec={r} w={3} h={2} />
                  <div style={{
                    marginTop: 6, display: "flex", justifyContent: "space-between", alignItems: "baseline",
                    fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)", letterSpacing: "0.08em",
                  }}>
                    <span>№{String(r.id).padStart(3, "0")} · {r.cat}</span>
                    <Coin value={r.coins} size={10} />
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>

      {/* RIGHT — metadata + actions */}
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0, gap: compact ? 18 : 22 }}>
        {/* Eyebrow */}
        <div className="kicker" style={{ color: "var(--muted)" }}>
          {spec.cat.toUpperCase()} · ADDED {spec.days}D AGO {spec.dynamic && "· DYNAMIC"}
        </div>

        {/* Uploader — no follow button */}
        <div style={{
          marginTop: -8,
          display: "flex", alignItems: "center", gap: 12,
          padding: "12px 0", borderTop: "1px solid var(--hair)", borderBottom: "1px solid var(--hair)",
        }}>
          <div style={{
            width: 40, height: 40, borderRadius: "50%", background: "var(--paper-2)",
            border: "1px solid var(--hair)", display: "flex", alignItems: "center", justifyContent: "center",
            fontFamily: "var(--display)", fontSize: 18,
          }}>
            {spec.author[0].toUpperCase()}
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <a href="#" style={{ textDecoration: "none", color: "var(--ink)" }}>
              <div className="display" style={{ fontSize: 19, lineHeight: 1.1 }}>@{spec.author}</div>
              <div style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)", letterSpacing: "0.08em" }}>
                CONTRIBUTOR · 142 SPECIMENS
              </div>
            </a>
          </div>
          {/* Quiet "View profile →" affordance instead of a follow button */}
          <span style={{
            fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.1em",
            color: "var(--muted)", textTransform: "uppercase",
          }}>VIEW →</span>
        </div>

        <PaletteBlock spec={spec} />
        <DevicesBlock spec={spec} />
        <SpecsBlock spec={spec} />
        <ActionGrid spec={spec} state={actionState} />

        {/* Coin CTA — multi-state */}
        <div style={{ marginTop: "auto", paddingTop: 4 }}>
          <CoinCTA spec={spec} balance={balance} mode={downloadMode} compact={compact} />
        </div>
      </div>
    </div>
  );
}

// ─── Full-page Detail ──────────────────────────────────────────────────

function DetailSpread({ auth = "in", actionState, downloadMode = "default", balance = 12 }) {
  const spec = SPECIMENS[0];
  const related = [SPECIMENS[5], SPECIMENS[13], SPECIMENS[9], SPECIMENS[7]];

  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Discover" auth={auth} balance={balance} />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth={auth}>
          <button style={{
            display: "inline-flex", alignItems: "center", gap: 8,
            background: "transparent", border: "1px solid var(--hair)", padding: "8px 14px",
            fontFamily: "var(--sans)", fontSize: 13, borderRadius: 999, color: "var(--ink)",
            cursor: "pointer",
          }}>
            <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}><I.arrow size={13} /></span>
            Back to wall
          </button>
          <span style={{
            fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.18em",
            color: "var(--muted)", textTransform: "uppercase",
          }}>
            Specimen №{String(spec.id).padStart(3, "0")}
          </span>
        </ArchiveTopbar>
        <SpreadBody spec={spec} related={related} compact={false}
                    actionState={actionState} downloadMode={downloadMode} balance={balance} />
      </div>
    </div>
  );
}

// ─── Modal version ─────────────────────────────────────────────────────

function DetailModal({ auth = "in", actionState }) {
  const spec = SPECIMENS[3];

  return (
    <div style={{
      width: 1440, height: 1040,
      position: "relative", overflow: "hidden", fontFamily: "var(--sans)",
      background: "var(--paper)",
    }}>
      {/* Salon underneath, dimmed */}
      <div style={{ position: "absolute", inset: 0, transform: "scale(1.02)", filter: "blur(1px)" }}>
        <div className="grain" style={{
          width: "100%", height: "100%", background: "var(--paper)", color: "var(--ink)",
          display: "grid", gridTemplateColumns: "232px 1fr",
        }}>
          <ArchiveSidebar active="Discover" auth={auth} />
          <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
            <ArchiveTopbar auth={auth} />
            <DiscoverControls auth={auth} />
            <main style={{ overflow: "hidden", background: "var(--paper-2)" }}>
              <SalonMosaic items={SPECIMENS} layout={SALON_LAYOUT} pinnedIds={[]} />
            </main>
          </div>
        </div>
      </div>

      <div style={{ position: "absolute", inset: 0, background: "rgba(15,12,8,0.55)" }} />

      {/* Modal panel */}
      <div style={{
        position: "absolute", left: 60, right: 60, top: 40, bottom: 40,
        background: "var(--paper)", border: "1px solid var(--ink)",
        boxShadow: "0 24px 80px rgba(0,0,0,0.25), 0 0 0 1px rgba(0,0,0,0.04)",
        display: "flex", flexDirection: "column", minHeight: 0,
      }}>
        <div style={{
          padding: "12px 24px", display: "flex", justifyContent: "space-between", alignItems: "center",
          borderBottom: "1px solid var(--hair)",
          fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.18em",
          color: "var(--muted)", textTransform: "uppercase",
        }}>
          <span>
            SPECIMEN №{String(spec.id).padStart(3, "0")} ·
            <span style={{ marginLeft: 8, color: "var(--ink-2)" }}>OVERLAY VIEW</span>
          </span>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <span>
              <span style={{ border: "1px solid var(--hair)", padding: "2px 6px", marginRight: 6, background: "var(--paper-2)" }}>←</span>
              <span style={{ border: "1px solid var(--hair)", padding: "2px 6px", marginRight: 6, background: "var(--paper-2)" }}>→</span>
              NEIGHBOURING
            </span>
            <span>
              <span style={{ border: "1px solid var(--hair)", padding: "2px 6px", marginRight: 6, background: "var(--paper-2)" }}>ESC</span>
              CLOSE
            </span>
            <IconBtn tone="paper" title="Close" style={{ width: 32, height: 32 }}>
              <I.x size={14} />
            </IconBtn>
          </div>
        </div>

        <div style={{ flex: 1, minHeight: 0, overflow: "hidden", display: "flex" }}>
          <SpreadBody spec={spec} related={[]} compact={true} actionState={actionState} />
        </div>
      </div>

      {/* Prev / next on backdrop */}
      <button style={{
        position: "absolute", left: 16, top: "50%", transform: "translateY(-50%)",
        width: 38, height: 60, background: "rgba(255,255,255,0.92)",
        border: "1px solid var(--hair)", color: "var(--ink)",
        display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
      }}>
        <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}><I.arrow size={14} /></span>
      </button>
      <button style={{
        position: "absolute", right: 16, top: "50%", transform: "translateY(-50%)",
        width: 38, height: 60, background: "rgba(255,255,255,0.92)",
        border: "1px solid var(--hair)", color: "var(--ink)",
        display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
      }}>
        <I.arrow size={14} />
      </button>
    </div>
  );
}

Object.assign(window, { DetailSpread, DetailModal, SpreadBody, CoinCTA, PaletteBlock, DevicesBlock, ActionGrid, paletteFor, deviceFits });
