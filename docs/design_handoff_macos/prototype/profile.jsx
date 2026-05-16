/* User profile page — shell with header + tabs.
   Tabs: Uploads · Collections · Favorites · Likes · Downloads · Ledger
   Lists use traditional pagination, not infinite scroll. */

const ME = {
  username: "marin.k",
  nickname: "Marin K.",
  email: "marin@kraken.studio",
  signature: "Capturing slow light. Crete, mostly.",
  joined: "May 2024",
  coins: 12,
  stats: { uploads: 18, collections: 5, favorites: 42, likes: 88, downloads: 64 },
};

// Hand-rolled "in-progress" uploads — only visible in the owner's Uploads tab.
const PROCESSING = [
  { id: 901, seed: "proc-1", w: 1600, h: 1066, status: "processing", progress: 64, uploaded: "2 min ago" },
  { id: 902, seed: "proc-2", w: 1066, h: 1600, status: "processing", progress: 18, uploaded: "12 min ago" },
];

// Owner uploads — published items by @marin.k pulled from SPECIMENS.
function ownerUploads() {
  return SPECIMENS.filter((s) => s.author === "marin.k");
}

function favForUser() {
  // Show varied items for favorites (anyone can favorite anything)
  return [SPECIMENS[1], SPECIMENS[3], SPECIMENS[12], SPECIMENS[7], SPECIMENS[10], SPECIMENS[15]];
}

// ─── Profile shell ─────────────────────────────────────────────────────

function ProfileShell({ activeTab = "uploads", isOwner = true, children }) {
  const counts = {
    uploads: ME.stats.uploads,
    collections: ME.stats.collections,
    favorites: ME.stats.favorites,
    likes: ME.stats.likes,
    downloads: ME.stats.downloads,
  };
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="" auth="in" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="in" />
        <main style={{ padding: "28px 40px", overflow: "hidden", flex: 1 }}>
          <ProfileHeader isOwner={isOwner} />
          <div style={{ marginTop: 24 }}>
            <ProfileTabs active={activeTab} isOwner={isOwner} counts={counts} />
          </div>
          <div style={{ marginTop: 24 }}>{children}</div>
        </main>
      </div>
    </div>
  );
}

// ─── Profile header ────────────────────────────────────────────────────

function ProfileHeader({ isOwner = true }) {
  return (
    <header style={{
      display: "grid", gridTemplateColumns: "120px 1fr auto", gap: 24,
      alignItems: "flex-start",
      paddingBottom: 24, borderBottom: "1px solid var(--hair)",
    }}>
      {/* Avatar */}
      <div style={{ position: "relative" }}>
        <div style={{
          width: 120, height: 120, borderRadius: "50%", overflow: "hidden",
          background: "var(--paper-2)", border: "1px solid var(--hair)",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontFamily: "var(--display)", fontSize: 64, color: "var(--ink)",
        }}>
          M
        </div>
        {isOwner && (
          <button style={{
            position: "absolute", right: 0, bottom: 0,
            width: 32, height: 32, borderRadius: "50%",
            background: "var(--ink)", color: "var(--paper)", border: "2px solid var(--paper)",
            display: "inline-flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
          }}><I.pen size={13} /></button>
        )}
      </div>

      {/* Identity */}
      <div style={{ minWidth: 0, paddingTop: 6 }}>
        <div className="kicker" style={{ color: "var(--muted)" }}>
          CONTRIBUTOR · MEMBER SINCE {ME.joined.toUpperCase()}
        </div>
        <h1 className="display" style={{
          fontSize: 48, lineHeight: 0.96, margin: "8px 0 0", letterSpacing: "-0.02em",
        }}>
          {ME.nickname}
        </h1>
        <div style={{
          marginTop: 6, fontFamily: "var(--mono)", fontSize: 12,
          color: "var(--ink-2)", letterSpacing: "0.04em",
        }}>
          @{ME.username}
          <span style={{ color: "var(--muted)", margin: "0 10px" }}>·</span>
          <span style={{ color: "var(--muted)", display: "inline-flex", alignItems: "center", gap: 6 }}>
            <I.mail size={11} /> {ME.email}
          </span>
        </div>
        <p style={{
          marginTop: 14, fontFamily: "var(--display)", fontStyle: "italic",
          fontSize: 18, color: "var(--ink-2)", maxWidth: 560, lineHeight: 1.4,
        }}>
          "{ME.signature}"
        </p>
      </div>

      {/* Coin card + edit profile */}
      <div style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "flex-end" }}>
        <div style={{
          padding: "14px 22px", background: "var(--ink)", color: "var(--paper)",
          minWidth: 180, textAlign: "right",
        }}>
          <div style={{
            fontFamily: "var(--mono)", fontSize: 10,
            color: "rgba(255,255,255,0.55)", letterSpacing: "0.14em",
          }}>YOUR BALANCE</div>
          <div className="display" style={{
            fontSize: 56, lineHeight: 1, marginTop: 4,
            color: "var(--accent)",
          }}>{ME.coins}<span style={{
            fontSize: 14, color: "rgba(255,255,255,0.55)", fontFamily: "var(--mono)",
            marginLeft: 6, letterSpacing: "0.1em",
          }}>COINS</span></div>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {isOwner ? (
            <>
              <Btn tone="ghost" size="sm"><I.pen size={12} /> Edit profile</Btn>
              <Btn tone="ink" size="sm"><I.plus size={13} /> Upload</Btn>
            </>
          ) : (
            <Btn tone="ink" size="sm">Message</Btn>
          )}
        </div>
      </div>
    </header>
  );
}

// ─── Tab content : Uploads ──────────────────────────────────────────

function UploadsTile({ spec, isProcessing = false }) {
  return (
    <div className="tile-cell" style={{
      position: "relative", aspectRatio: "3/2",
      border: "1px solid var(--hair)", background: spec.color, overflow: "hidden",
    }}>
      <img className="tile-img" src={picsum(spec.seed, 800, 600)}
           style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
      {!isProcessing && (
        <span style={{
          position: "absolute", top: 10, left: 10, padding: "3px 8px",
          background: "rgba(0,0,0,0.55)", color: "#fff", borderRadius: 3,
          fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.08em",
        }}>{spec.res}</span>
      )}
      {isProcessing && <ProcessingOverlay progress={spec.progress || 50} />}
    </div>
  );
}

function ProfileUploads() {
  const published = ownerUploads();
  return (
    <div>
      {/* "In progress" sub-section — only the owner sees this. */}
      <div className="label-rule" style={{ marginBottom: 12 }}>
        IN PROGRESS · {PROCESSING.length}
      </div>
      <p style={{
        margin: "0 0 14px", fontSize: 12, color: "var(--muted)",
        fontFamily: "var(--sans)",
      }}>
        Generating device variants. Wallpapers appear in the public archive when processing finishes.
      </p>
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14, marginBottom: 32,
      }}>
        {PROCESSING.map((p) => (
          <div key={p.id} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <UploadsTile spec={p} isProcessing />
            <div style={{
              display: "flex", justifyContent: "space-between", alignItems: "center",
              fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.08em", color: "var(--muted)",
            }}>
              <span>№{String(p.id).padStart(3, "0")} · QUEUED</span>
              <span>{p.uploaded}</span>
            </div>
          </div>
        ))}
      </div>

      <div className="label-rule" style={{ marginBottom: 14 }}>
        PUBLISHED · {published.length} OF {ME.stats.uploads}
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14 }}>
        {published.slice(0, 4).map((s) => (
          <div key={s.id} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <UploadsTile spec={s} />
            <div style={{
              display: "flex", justifyContent: "space-between", alignItems: "center",
              fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.08em", color: "var(--muted)",
            }}>
              <span>№{String(s.id).padStart(3, "0")} · {s.cat.toUpperCase()}</span>
              <span>♥ {fmt(s.likes)} · ↓ {fmt(s.downloads)}</span>
            </div>
          </div>
        ))}
      </div>

      <Pagination current={1} total={5} />
    </div>
  );
}

// ─── Tab content : Likes (private) ─────────────────────────────────

function ProfileLikes({ isOwner = true, isPublic = false }) {
  const items = favForUser();
  return (
    <div>
      <div style={{ marginBottom: 18 }}>
        <PrivacyNotice listName="likes list" isOwner={isOwner} isPublic={isPublic} />
      </div>

      {!isOwner && !isPublic ? (
        <div style={{
          padding: "60px 24px", textAlign: "center",
          background: "var(--paper-2)", border: "1px dashed var(--hair)",
        }}>
          <I.lock size={28} stroke={1.2} />
          <div className="display" style={{ fontSize: 24, marginTop: 12 }}>Hidden from view</div>
          <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 4 }}>
            This contributor has chosen not to share their likes.
          </div>
        </div>
      ) : (
        <>
          <div className="label-rule" style={{ marginBottom: 14 }}>
            LIKED · {ME.stats.likes} TOTAL
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14 }}>
            {items.map((s) => (
              <div key={s.id} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                <UploadsTile spec={s} />
                <div style={{
                  display: "flex", justifyContent: "space-between",
                  fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)", letterSpacing: "0.08em",
                }}>
                  <span>@{s.author}</span>
                  <span style={{ color: "#b1311f" }}><I.heartFill size={9} /></span>
                </div>
              </div>
            ))}
          </div>
          <Pagination current={2} total={22} />
        </>
      )}
    </div>
  );
}

// ─── Tab content : Collections (created) ──────────────────────────

const MY_COLLECTIONS = [
  { id: 1, name: "Slow morning light",   curator: "marin.k", count: 12, layers: [0, 9, 4],   public: true },
  { id: 2, name: "Cold cities at dusk",  curator: "marin.k", count: 8,  layers: [1, 10, 12], public: true },
  { id: 3, name: "Studio reference",     curator: "marin.k", count: 24, layers: [12, 2, 11], public: false },
  { id: 4, name: "Untitled (2026 spr.)", curator: "marin.k", count: 5,  layers: [3, 13, 6],  public: true },
];

function CollectionCard({ coll, items = SPECIMENS }) {
  const [main, sub1, sub2] = coll.layers;
  const moreCount = Math.max(0, coll.count - 3);
  return (
    <div className="coll-card">
      <div className="coll-stack">
        <div className="coll-main">
          <img src={picsum(items[main].seed, 1200, 900)} alt="" />
        </div>
        <div className="coll-sub">
          <img src={picsum(items[sub1].seed, 600, 400)} alt="" />
        </div>
        <div className="coll-sub">
          <img src={picsum(items[sub2].seed, 600, 400)} alt="" />
          {moreCount > 0 && (
            <span className="coll-more">
              <I.plus size={9} stroke={2.2} />{moreCount}
            </span>
          )}
        </div>
      </div>
      <div style={{ padding: "14px 4px 0" }}>
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "baseline",
          fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em",
          color: "var(--muted)", textTransform: "uppercase",
        }}>
          <span>№{String(coll.id).padStart(3, "0")} · {coll.count} SPECIMENS</span>
          {!coll.public && <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}><I.lock size={10} /> PRIVATE</span>}
        </div>
        <div className="display" style={{
          fontSize: 22, lineHeight: 1.1, marginTop: 4,
        }}>{coll.name}</div>
        <div style={{
          marginTop: 6, fontFamily: "var(--mono)", fontSize: 10,
          color: "var(--muted)", letterSpacing: "0.04em",
        }}>
          @{coll.curator}
        </div>
      </div>
    </div>
  );
}

function ProfileCollections({ isOwner = true }) {
  return (
    <div>
      <div style={{
        display: "flex", alignItems: "baseline", justifyContent: "space-between",
        marginBottom: 14,
      }}>
        <div className="label-rule" style={{ flex: 1 }}>
          CREATED · {MY_COLLECTIONS.length} OF {ME.stats.collections}
        </div>
        {isOwner && (
          <button style={{
            marginLeft: 24, padding: "8px 14px", background: "var(--ink)", color: "var(--paper)",
            border: "none", fontFamily: "var(--sans)", fontSize: 12, fontWeight: 500,
            borderRadius: 999, cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 6,
          }}>
            <I.plus size={12} /> New collection
          </button>
        )}
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 20 }}>
        {MY_COLLECTIONS.map((c) => <CollectionCard key={c.id} coll={c} />)}
      </div>
      <Pagination current={1} total={2} />
    </div>
  );
}

// ─── Tab content : Coin ledger ────────────────────────────────────

const LEDGER = [
  { delta: "+5", label: "Uploaded ‘Limestone in low sun’",   when: "Today, 14:02",   day: "MAY 15" },
  { delta: "−1", label: "Downloaded ‘Cobalt afternoon’",      when: "Today, 09:11",   day: "MAY 15" },
  { delta: "+1", label: "@ines.r downloaded your ‘Crete 04’", when: "Yesterday, 22:48",day: "MAY 14" },
  { delta: "−2", label: "Downloaded ‘Tokyo, twenty-third floor’", when: "Yesterday, 18:30", day: "MAY 14" },
  { delta: "+1", label: "Daily check-in",                      when: "Yesterday, 09:00", day: "MAY 14" },
  { delta: "+5", label: "Uploaded ‘Tide pool, 06:42’",         when: "May 13",           day: "MAY 13" },
  { delta: "+10",label: "Wallpaper featured · Editor's pick",  when: "May 12",           day: "MAY 12" },
  { delta: "−1", label: "Downloaded ‘Inkwash mountain’",       when: "May 12",           day: "MAY 12" },
];

function ProfileLedger() {
  // Group by day for editorial structure
  const days = [];
  LEDGER.forEach((e) => {
    if (!days.length || days[days.length - 1].day !== e.day) days.push({ day: e.day, items: [] });
    days[days.length - 1].items.push(e);
  });
  return (
    <div>
      {/* Summary strip */}
      <div style={{
        display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr",
        border: "1px solid var(--hair)", borderRight: "none", marginBottom: 24,
      }}>
        {[
          ["BALANCE", "12", "coins"],
          ["EARNED",  "+47", "this month"],
          ["SPENT",   "−12", "this month"],
          ["NEXT",    "+5",  "per upload"],
        ].map(([k, v, sub]) => (
          <div key={k} style={{ padding: "16px 20px", borderRight: "1px solid var(--hair)" }}>
            <div className="kicker" style={{ color: "var(--muted)" }}>{k}</div>
            <div className="display" style={{
              fontSize: 36, lineHeight: 1, marginTop: 6,
              color: v.startsWith("+") ? "var(--accent)" : v.startsWith("−") ? "var(--ink-2)" : "var(--ink)",
            }}>{v}</div>
            <div style={{
              fontFamily: "var(--mono)", fontSize: 10, color: "var(--muted)",
              letterSpacing: "0.06em", marginTop: 2, textTransform: "uppercase",
            }}>{sub}</div>
          </div>
        ))}
      </div>

      <div className="label-rule" style={{ marginBottom: 4 }}>RECENT ENTRIES</div>

      <div>
        {days.map((d) => (
          <div key={d.day}>
            <div style={{
              padding: "16px 0 6px",
              fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.14em",
              color: "var(--muted)", textTransform: "uppercase",
            }}>{d.day}</div>
            {d.items.map((e, i) => (
              <div key={i} style={{
                display: "grid", gridTemplateColumns: "60px 1fr auto",
                gap: 16, alignItems: "baseline",
                padding: "12px 0", borderTop: "1px solid var(--hair)",
              }}>
                <span style={{
                  fontFamily: "var(--mono)", fontSize: 16, fontWeight: 600,
                  color: e.delta.startsWith("+") ? "var(--accent)" : "var(--ink-2)",
                }}>{e.delta}</span>
                <span style={{ fontSize: 13, color: "var(--ink)" }}>{e.label}</span>
                <span style={{
                  fontFamily: "var(--mono)", fontSize: 10,
                  color: "var(--muted)", letterSpacing: "0.06em",
                }}>{e.when}</span>
              </div>
            ))}
          </div>
        ))}
      </div>

      <Pagination current={1} total={6} />
    </div>
  );
}

// ─── Composed artboards ────────────────────────────────────────────

function ProfileUploadsPage() {
  return <ProfileShell activeTab="uploads"><ProfileUploads /></ProfileShell>;
}
function ProfileCollectionsPage() {
  return <ProfileShell activeTab="collections"><ProfileCollections /></ProfileShell>;
}
function ProfileLikesPrivatePage() {
  return <ProfileShell activeTab="likes"><ProfileLikes isOwner isPublic={false} /></ProfileShell>;
}
function ProfileLedgerPage() {
  return <ProfileShell activeTab="ledger"><ProfileLedger /></ProfileShell>;
}
function ProfilePublicViewPage() {
  // What the world sees when visiting a stranger's profile: no Ledger tab,
  // Likes tab still visible (hits the "Hidden from view" empty state).
  return (
    <ProfileShell activeTab="likes" isOwner={false}>
      <ProfileLikes isOwner={false} isPublic={false} />
    </ProfileShell>
  );
}

Object.assign(window, {
  ME, PROCESSING, MY_COLLECTIONS, LEDGER,
  ProfileShell, ProfileHeader, ProfileUploads, ProfileCollections, ProfileLikes, ProfileLedger,
  ProfileUploadsPage, ProfileCollectionsPage, ProfileLikesPrivatePage, ProfileLedgerPage, ProfilePublicViewPage,
  CollectionCard, UploadsTile,
});
