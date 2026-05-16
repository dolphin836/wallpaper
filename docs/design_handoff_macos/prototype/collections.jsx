/* Collections browse + Collection detail pages. */

const COLLECTIONS = [
  { id: 1, name: "Slow morning light",       curator: "marin.k",      count: 12, layers: [0, 9, 4]  },
  { id: 2, name: "Cold cities at dusk",      curator: "k_otsuka",     count: 8,  layers: [1, 10, 12] },
  { id: 3, name: "Bismuth and other glows",  curator: "studio.glo",   count: 16, layers: [3, 13, 7]  },
  { id: 4, name: "Field notes · Minimal",    curator: "fern.atelier", count: 22, layers: [2, 11, 7]  },
  { id: 5, name: "Saturday street",          curator: "ines.r",       count: 9,  layers: [8, 14, 0]  },
  { id: 6, name: "Mac dynamic only",         curator: "wallx",        count: 6,  layers: [6, 15, 12] },
  { id: 7, name: "Reference · Aerial",       curator: "ohta",         count: 18, layers: [9, 5, 13]  },
  { id: 8, name: "Concrete and softness",    curator: "marin.k",      count: 10, layers: [5, 11, 2]  },
];

function CollectionsBrowse() {
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Collections" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in" />

        <main style={{ padding: "28px 40px", overflow: "hidden", flex: 1, background: "var(--paper-2)" }}>
          <div style={{
            display: "flex", alignItems: "flex-end", justifyContent: "space-between",
            marginBottom: 20, gap: 24, flexWrap: "wrap",
          }}>
            <div>
              <div className="kicker" style={{ color: "var(--muted)" }}>Collections · 168</div>
              <h1 className="display" style={{ fontSize: 56, lineHeight: 0.96, margin: "8px 0 0", letterSpacing: "-0.02em" }}>
                Curated <span className="italic-d">selections.</span>
              </h1>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <Btn tone="ghost" size="sm" active>All</Btn>
              <Btn tone="ghost" size="sm">Editorial</Btn>
              <Btn tone="ghost" size="sm">Following</Btn>
              <Btn tone="ghost" size="sm">Yours</Btn>
              <div style={{ width: 1, height: 22, background: "var(--hair)", margin: "auto 6px" }} />
              <Btn tone="ink" size="sm"><I.plus size={13} /> New collection</Btn>
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 24 }}>
            {COLLECTIONS.map((c) => <CollectionCard key={c.id} coll={c} />)}
          </div>

          <Pagination current={1} total={6} />
        </main>
      </div>
    </div>
  );
}

// ─── Collection detail ─────────────────────────────────────────────

function CollectionDetail() {
  const coll = COLLECTIONS[2]; // "Bismuth and other glows" by studio.glo
  const items = [SPECIMENS[3], SPECIMENS[12], SPECIMENS[7], SPECIMENS[15], SPECIMENS[10], SPECIMENS[1], SPECIMENS[6], SPECIMENS[5]];
  const cover = SPECIMENS[3];

  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Collections" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in">
          <button style={{
            display: "inline-flex", alignItems: "center", gap: 8,
            background: "transparent", border: "1px solid var(--hair)", padding: "8px 14px",
            fontFamily: "var(--sans)", fontSize: 13, borderRadius: 999, color: "var(--ink)",
          }}>
            <span style={{ transform: "rotate(180deg)", display: "inline-flex" }}><I.arrow size={13} /></span>
            All collections
          </button>
        </ArchiveTopbar>

        <main style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
          {/* Hero spread */}
          <div style={{
            display: "grid", gridTemplateColumns: "1fr 1fr",
            background: "var(--paper)", borderBottom: "1px solid var(--hair)",
          }}>
            <div style={{ position: "relative", aspectRatio: "3/2", overflow: "hidden" }}>
              <img src={picsum(cover.seed, 1200, 800)}
                   style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
              <Brackets color="#fff" opacity={0.7} inset={16} size={22} />
            </div>
            <div style={{ padding: "40px 48px", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
              <div>
                <div className="kicker" style={{ color: "var(--muted)" }}>Collection №{String(coll.id).padStart(3, "0")} · 16 SPECIMENS · CURATED</div>
                <h1 className="display" style={{
                  fontSize: 76, lineHeight: 0.92, margin: "12px 0 0", letterSpacing: "-0.02em",
                }}>
                  Bismuth & <span className="italic-d">other glows.</span>
                </h1>
                <p className="display italic-d" style={{
                  marginTop: 20, fontSize: 19, color: "var(--ink-2)", lineHeight: 1.45, maxWidth: 480,
                }}>
                  Crystal growth, oxidation, and slow-cooked iridescence. Studio shots, mostly.
                </p>
              </div>
              <div style={{ marginTop: 24, display: "flex", alignItems: "center", gap: 12 }}>
                <div style={{
                  width: 36, height: 36, borderRadius: "50%", background: "var(--paper-2)",
                  border: "1px solid var(--hair)", display: "flex", alignItems: "center",
                  justifyContent: "center", fontFamily: "var(--display)", fontSize: 18,
                }}>S</div>
                <div>
                  <div className="display" style={{ fontSize: 17, lineHeight: 1.1 }}>@{coll.curator}</div>
                  <div style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)", letterSpacing: "0.06em" }}>
                    UPDATED 2 DAYS AGO · 412 LIKES
                  </div>
                </div>
                <div style={{ marginLeft: "auto", display: "flex", gap: 8 }}>
                  <Btn tone="ghost" size="sm"><I.heart size={13} /> 412</Btn>
                  <Btn tone="ink" size="sm"><I.layers size={13} /> Subscribe</Btn>
                </div>
              </div>
            </div>
          </div>

          {/* Grid */}
          <div style={{ padding: "28px 40px", overflow: "hidden", flex: 1, background: "var(--paper-2)" }}>
            <div className="label-rule" style={{ marginBottom: 14 }}>SPECIMENS · 8 OF 16</div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14 }}>
              {items.map((s) => (
                <UploadsTile key={s.id} spec={s} />
              ))}
            </div>
            <Pagination current={1} total={2} />
          </div>
        </main>
      </div>
    </div>
  );
}

Object.assign(window, { COLLECTIONS, CollectionsBrowse, CollectionDetail });
