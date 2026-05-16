/* macOS app download page + Legal page template (Terms / Privacy / DMCA share
   the same structural template — copy is illustrative). */

function MacDownloadPage() {
  const cover = SPECIMENS[3];
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="macOS App" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in" />

        <main style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
          {/* Hero */}
          <section style={{
            padding: "48px 56px 40px",
            display: "grid", gridTemplateColumns: "1fr 1fr", gap: 56,
            borderBottom: "1px solid var(--hair)",
          }}>
            <div>
              <div className="kicker" style={{ color: "var(--muted)" }}>
                <I.apple size={11} /> &nbsp; FOR MACOS 14+ · UNIVERSAL · v2.4.0
              </div>
              <h1 className="display" style={{
                fontSize: 88, lineHeight: 0.88, margin: "14px 0 0", letterSpacing: "-0.03em",
              }}>
                The archive,<br/><span className="italic-d">in your menu bar.</span>
              </h1>
              <p style={{
                marginTop: 22, fontSize: 15, color: "var(--ink-2)", lineHeight: 1.55, maxWidth: 480,
              }}>
                A small companion app that lives in the macOS menu bar. Browse, preview, and apply
                wallpapers in one click — including <strong style={{ color: "var(--ink)" }}>Apple dynamic</strong>
                {" "}wallpapers that shift with the sun.
              </p>

              <div style={{ marginTop: 28, display: "flex", alignItems: "center", gap: 14, flexWrap: "wrap" }}>
                <button style={{
                  padding: "16px 26px",
                  background: "var(--ink)", color: "var(--paper)", border: "none",
                  fontFamily: "var(--sans)", fontWeight: 600, fontSize: 15,
                  borderRadius: 999, cursor: "pointer",
                  display: "inline-flex", alignItems: "center", gap: 12,
                }}>
                  <I.apple size={16} /> Download for macOS
                  <span style={{
                    paddingLeft: 12, marginLeft: 4, borderLeft: "1px solid rgba(255,255,255,0.2)",
                    fontFamily: "var(--mono)", fontSize: 11, fontWeight: 500,
                    color: "rgba(255,255,255,0.6)", letterSpacing: "0.1em",
                  }}>DMG · 14.2 MB</span>
                </button>
                <div style={{
                  fontFamily: "var(--mono)", fontSize: 11, color: "var(--muted)", letterSpacing: "0.06em",
                }}>
                  Free · auto-updates · signed and notarized
                </div>
              </div>

              {/* System requirements */}
              <div style={{ marginTop: 36, display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 0,
                            border: "1px solid var(--hair)", borderRight: "none" }}>
                {[
                  ["MACOS",      "14 Sonoma or later"],
                  ["ARCHITECTURE","Apple Silicon · Intel"],
                  ["SIGN-IN",     "Same archive account"],
                ].map(([k, v]) => (
                  <div key={k} style={{ padding: "14px 16px", borderRight: "1px solid var(--hair)" }}>
                    <div className="kicker" style={{ color: "var(--muted)" }}>{k}</div>
                    <div style={{ fontSize: 12, color: "var(--ink)", marginTop: 4 }}>{v}</div>
                  </div>
                ))}
              </div>
            </div>

            {/* Mock screenshot of the menu-bar popover */}
            <div style={{ position: "relative" }}>
              <div style={{
                position: "absolute", inset: 0,
                background: `url("${picsum(cover.seed, 1200, 1600)}") center/cover`,
                filter: "blur(0.5px) brightness(0.92)",
              }} />
              <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(0,0,0,0.05), rgba(0,0,0,0.35))" }} />

              {/* Menu-bar popover mock */}
              <div style={{
                position: "absolute", right: 36, top: 36,
                width: 280, background: "rgba(245,243,238,0.94)",
                border: "1px solid rgba(0,0,0,0.08)",
                backdropFilter: "blur(20px) saturate(1.2)",
                boxShadow: "0 20px 60px rgba(0,0,0,0.25)",
                fontFamily: "var(--sans)",
              }}>
                <div style={{
                  padding: "10px 14px", borderBottom: "1px solid rgba(0,0,0,0.06)",
                  display: "flex", justifyContent: "space-between", alignItems: "center",
                  fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em",
                  color: "var(--muted)", textTransform: "uppercase",
                }}>
                  <span>WALLPAPER EXCHANGE</span>
                  <I.apple size={11} />
                </div>
                <div style={{ padding: 10, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6 }}>
                  {[3, 7, 12, 13].map((i) => (
                    <div key={i} style={{
                      aspectRatio: "16/10", borderRadius: 4, overflow: "hidden",
                      border: i === 3 ? "2px solid var(--accent)" : "1px solid rgba(0,0,0,0.06)",
                    }}>
                      <img src={picsum(SPECIMENS[i].seed, 400, 250)}
                           style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                    </div>
                  ))}
                </div>
                <div style={{ padding: "10px 14px", borderTop: "1px solid rgba(0,0,0,0.06)", fontSize: 11 }}>
                  <div style={{ display: "flex", justifyContent: "space-between" }}>
                    <span>Bismuth bloom</span>
                    <span style={{ color: "var(--accent)", fontWeight: 600 }}>Applied</span>
                  </div>
                </div>
                <button style={{
                  width: "100%", padding: "10px", border: "none",
                  background: "var(--ink)", color: "var(--paper)",
                  fontFamily: "var(--sans)", fontSize: 12, cursor: "pointer",
                }}>Open in archive →</button>
              </div>
            </div>
          </section>

          {/* Features */}
          <section style={{ padding: "32px 56px", display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 0,
                            borderTop: "1px solid var(--hair)" }}>
            {[
              ["I.menu",     "One-click apply",     "Right-click any wallpaper in the menu-bar grid to set it as your desktop."],
              ["I.apple",    "Apple Dynamic",        "Full support for solar / 24-hour / appearance-linked wallpapers."],
              ["I.bolt",     "Live sync",            "Your favorites and likes sync with the web archive. No setup required."],
              ["I.layers",   "Collections offline",  "Subscribe a collection — every wallpaper is cached locally."],
            ].map(([_, title, body], i) => (
              <div key={title} style={{
                padding: "0 24px 0 0",
                borderLeft: i === 0 ? "none" : "1px solid var(--hair)",
                paddingLeft: i === 0 ? 0 : 24,
              }}>
                <div className="kicker" style={{ color: "var(--muted)" }}>0{i + 1}</div>
                <div className="display" style={{ fontSize: 22, lineHeight: 1.1, marginTop: 6 }}>
                  {title}
                </div>
                <p style={{ marginTop: 8, fontSize: 13, color: "var(--ink-2)", lineHeight: 1.5 }}>
                  {body}
                </p>
              </div>
            ))}
          </section>

          {/* Changelog stub */}
          <section style={{
            padding: "24px 56px", borderTop: "1px solid var(--hair)",
            background: "var(--paper-2)",
            display: "flex", justifyContent: "space-between", alignItems: "center", gap: 24,
          }}>
            <div>
              <div className="kicker" style={{ color: "var(--muted)" }}>v2.4.0 · May 12, 2026</div>
              <div style={{ marginTop: 4, fontSize: 13, color: "var(--ink-2)" }}>
                Apple dynamic wallpaper support, faster preview generation, fixed a HEIC decoding edge case.
              </div>
            </div>
            <a href="#" style={{
              fontFamily: "var(--mono)", fontSize: 11, letterSpacing: "0.12em",
              color: "var(--ink)", textTransform: "uppercase",
              textDecoration: "underline", textDecorationColor: "var(--hair)", textUnderlineOffset: 4,
            }}>FULL CHANGELOG →</a>
          </section>
        </main>
      </div>
    </div>
  );
}

// ─── Legal template ─────────────────────────────────────────────────

const LEGAL_DOC = {
  title: "Terms of Service",
  italicTail: "of service",
  updated: "May 12, 2026",
  version: "v3.2",
  toc: [
    "01 · Acceptance",
    "02 · Eligibility",
    "03 · Account & coins",
    "04 · User content",
    "05 · Acceptable use",
    "06 · DMCA takedown",
    "07 · Termination",
    "08 · Disclaimers",
    "09 · Governing law",
    "10 · Contact",
  ],
  body: [
    { h: "Acceptance", id: "01",
      ps: [
        "By creating an account or downloading a wallpaper from Wallpaper Exchange (\"the Archive\"), you agree to these terms.",
        "If you do not agree, do not use the service. We may update these terms; we'll surface a notice in the app when we do.",
      ],
    },
    { h: "Account & coins", id: "03",
      ps: [
        "Coins are an in-product credit, not currency. They cannot be transferred, refunded for cash, or assigned a monetary value.",
        "Coins are earned by uploading wallpapers, daily check-ins, and when others download work you uploaded. Coins are spent at the time of download.",
        "If you delete your account, any unused coin balance is forfeited.",
      ],
    },
    { h: "User content", id: "04",
      ps: [
        "You retain copyright in everything you upload. By uploading, you grant the Archive a non-exclusive license to host, display, resize, watermark, and serve the work to other users for the duration the wallpaper is published.",
        "Don't upload anything you don't have the rights to. We respond to DMCA notices within 48 hours.",
      ],
    },
  ],
};

function LegalPage() {
  const d = LEGAL_DOC;
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in" />

        <main style={{ flex: 1, overflow: "hidden", padding: "32px 56px",
                       display: "grid", gridTemplateColumns: "240px 1fr", gap: 56 }}>

          {/* TOC */}
          <aside>
            <div className="kicker" style={{ color: "var(--muted)" }}>Articles · {d.toc.length}</div>
            <ul style={{
              listStyle: "none", padding: 0, margin: "12px 0 0",
              fontFamily: "var(--mono)", fontSize: 11, letterSpacing: "0.04em",
              borderTop: "1px solid var(--hair)",
            }}>
              {d.toc.map((label, i) => (
                <li key={label} style={{
                  padding: "10px 0", borderBottom: "1px solid var(--hair)",
                  color: i === 0 ? "var(--ink)" : "var(--ink-2)",
                  display: "flex", justifyContent: "space-between",
                }}>
                  <span>{label}</span>
                  {i === 0 && <span style={{ color: "var(--accent)" }}>●</span>}
                </li>
              ))}
            </ul>

            {/* "See also" — Terms / Privacy / DMCA cross-links share the template */}
            <div style={{ marginTop: 28 }}>
              <div className="kicker" style={{ color: "var(--muted)" }}>See also</div>
              <ul style={{
                listStyle: "none", padding: 0, margin: "10px 0 0",
                fontFamily: "var(--sans)", fontSize: 13,
              }}>
                {["Terms of Service", "Privacy Policy", "Copyright / DMCA"].map((n, i) => (
                  <li key={n} style={{
                    padding: "8px 0", borderBottom: "1px solid var(--hair)",
                    color: i === 0 ? "var(--ink)" : "var(--ink-2)",
                    display: "flex", alignItems: "center", justifyContent: "space-between",
                  }}>
                    <span>{n}</span>
                    {i === 0 ? (
                      <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--accent)", letterSpacing: "0.1em" }}>CURRENT</span>
                    ) : (
                      <I.arrow size={11} />
                    )}
                  </li>
                ))}
              </ul>
            </div>
          </aside>

          {/* Body */}
          <article style={{ minWidth: 0, overflow: "hidden" }}>
            <div style={{
              display: "flex", justifyContent: "space-between", alignItems: "baseline",
              borderBottom: "1px solid var(--hair)", paddingBottom: 18,
            }}>
              <div>
                <div className="kicker" style={{ color: "var(--muted)" }}>Legal · {d.version}</div>
                <h1 className="display" style={{
                  fontSize: 76, lineHeight: 0.92, margin: "8px 0 0", letterSpacing: "-0.02em",
                }}>
                  Terms <span className="italic-d">{d.italicTail}.</span>
                </h1>
              </div>
              <div style={{ textAlign: "right", fontFamily: "var(--mono)", fontSize: 11, color: "var(--muted)", letterSpacing: "0.06em" }}>
                <div>LAST UPDATED</div>
                <div style={{ color: "var(--ink)", marginTop: 4 }}>{d.updated.toUpperCase()}</div>
              </div>
            </div>

            <div style={{ marginTop: 24, maxWidth: 680 }}>
              {d.body.map((section, i) => (
                <section key={section.h} style={{ marginBottom: 32 }}>
                  <div style={{
                    display: "flex", alignItems: "baseline", gap: 12,
                  }}>
                    <span style={{
                      fontFamily: "var(--mono)", fontSize: 11,
                      color: "var(--muted)", letterSpacing: "0.14em", paddingTop: 4,
                    }}>{section.id}</span>
                    <h2 className="display" style={{
                      fontSize: 30, lineHeight: 1.1, margin: 0, letterSpacing: "-0.01em",
                    }}>{section.h}</h2>
                  </div>
                  <div style={{
                    marginTop: 10, paddingLeft: 32, borderLeft: "1px solid var(--hair)",
                  }}>
                    {section.ps.map((p, j) => (
                      <p key={j} style={{
                        margin: j === 0 ? "0" : "12px 0 0",
                        fontSize: 14, lineHeight: 1.6, color: "var(--ink-2)",
                        textWrap: "pretty",
                      }}>{p}</p>
                    ))}
                  </div>
                </section>
              ))}

              <p style={{
                marginTop: 36, padding: 16, background: "var(--paper-2)",
                border: "1px solid var(--hair)", fontSize: 12, color: "var(--muted)",
                fontFamily: "var(--sans)", lineHeight: 1.5,
              }}>
                <strong style={{ color: "var(--ink-2)" }}>Note.</strong> This is the template
                shared by Terms · Privacy · DMCA. Each document uses the same TOC sidebar,
                title spread, mono-numbered sections, and hairline-bordered body — only the copy changes.
              </p>
            </div>
          </article>
        </main>
      </div>
    </div>
  );
}

Object.assign(window, { MacDownloadPage, LegalPage });
