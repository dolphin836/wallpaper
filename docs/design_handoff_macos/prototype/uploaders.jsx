/* Uploaders / Contributors browse page. */

const UPLOADERS = [
  {
    handle: "marin.k", name: "Marin K.",
    bio: "Capturing slow light. Crete, mostly.",
    uploads: 18, downloads: 4_280, likes: 12_440, joined: "May 2024",
    works: [0, 5, 13, 9],
  },
  {
    handle: "k_otsuka", name: "Kenji Otsuka",
    bio: "City photographer. Tokyo & Osaka. Shoots at blue hour.",
    uploads: 42, downloads: 18_810, likes: 28_300, joined: "Mar 2024",
    works: [1, 10, 11, 14],
  },
  {
    handle: "studio.glo", name: "Studio Glo",
    bio: "Crystal growth, oxidation, controlled mess. Two-person studio in Berlin.",
    uploads: 27, downloads: 26_510, likes: 41_200, joined: "Jan 2024",
    works: [3, 12, 6, 7],
  },
  {
    handle: "fern.atelier", name: "Fern Atelier",
    bio: "Minimal compositions. Architectural details. No people.",
    uploads: 31, downloads: 9_420, likes: 14_100, joined: "Feb 2024",
    works: [2, 7, 11, 5],
  },
  {
    handle: "ohta", name: "S. Ohta",
    bio: "Skies. Cirrus, mostly. Northern Hokkaido.",
    uploads: 14, downloads: 5_120, likes: 8_800, joined: "Aug 2024",
    works: [4, 9, 13, 0],
  },
  {
    handle: "ines.r", name: "Inès R.",
    bio: "Street, light, color. Lisbon based.",
    uploads: 22, downloads: 7_280, likes: 11_900, joined: "Jul 2024",
    works: [8, 14, 1, 11],
  },
];

function UploaderRow({ u }) {
  return (
    <article style={{
      display: "grid", gridTemplateColumns: "68px 1fr auto 380px",
      gap: 24, alignItems: "center",
      padding: "20px 0", borderBottom: "1px solid var(--hair)",
    }}>
      <div style={{
        width: 68, height: 68, borderRadius: "50%",
        background: "var(--paper-2)", border: "1px solid var(--hair)",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
        fontFamily: "var(--display)", fontSize: 32, color: "var(--ink)",
      }}>{u.name[0]}</div>

      <div style={{ minWidth: 0 }}>
        <div className="display" style={{ fontSize: 24, lineHeight: 1.05 }}>{u.name}</div>
        <div style={{
          marginTop: 3, fontFamily: "var(--mono)", fontSize: 11,
          color: "var(--muted)", letterSpacing: "0.04em",
        }}>
          @{u.handle} <span style={{ margin: "0 6px" }}>·</span> joined {u.joined}
        </div>
        <p style={{
          marginTop: 8, fontSize: 13, color: "var(--ink-2)", lineHeight: 1.45, maxWidth: 460,
        }}>{u.bio}</p>
      </div>

      <div style={{
        display: "grid", gridTemplateColumns: "auto auto auto", gap: 18,
        fontFamily: "var(--mono)", fontSize: 11, textAlign: "right",
      }}>
        {[
          ["UPLOADS",   u.uploads],
          ["DOWNLOADS", fmt(u.downloads)],
          ["LIKES",     fmt(u.likes)],
        ].map(([k, v]) => (
          <div key={k}>
            <div style={{
              fontFamily: "var(--mono)", fontSize: 9,
              color: "var(--muted)", letterSpacing: "0.14em",
            }}>{k}</div>
            <div className="display" style={{ fontSize: 22, lineHeight: 1, marginTop: 4 }}>{v}</div>
          </div>
        ))}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 6 }}>
        {u.works.map((idx) => (
          <div key={idx} style={{
            aspectRatio: "1/1", overflow: "hidden",
            border: "1px solid var(--hair)", background: SPECIMENS[idx].color,
          }}>
            <img src={picsum(SPECIMENS[idx].seed, 200, 200)}
                 style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          </div>
        ))}
      </div>
    </article>
  );
}

function UploadersBrowse() {
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Uploaders" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in" />

        <main style={{ padding: "28px 40px", overflow: "hidden", flex: 1 }}>
          <div style={{
            display: "flex", alignItems: "flex-end", justifyContent: "space-between",
            marginBottom: 20, gap: 24, flexWrap: "wrap",
          }}>
            <div>
              <div className="kicker" style={{ color: "var(--muted)" }}>Contributors · 312</div>
              <h1 className="display" style={{ fontSize: 56, lineHeight: 0.96, margin: "8px 0 0", letterSpacing: "-0.02em" }}>
                The people behind <span className="italic-d">the wall.</span>
              </h1>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <Btn tone="ghost" size="sm" active>Top this month</Btn>
              <Btn tone="ghost" size="sm">Most uploaded</Btn>
              <Btn tone="ghost" size="sm">Recently joined</Btn>
              <Btn tone="ghost" size="sm">Following</Btn>
            </div>
          </div>

          <div>
            {UPLOADERS.map((u) => <UploaderRow key={u.handle} u={u} />)}
          </div>

          <Pagination current={1} total={8} />
        </main>
      </div>
    </div>
  );
}

Object.assign(window, { UPLOADERS, UploaderRow, UploadersBrowse });
