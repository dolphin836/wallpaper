/* Login + Register pages. Shell uses the standard sidebar + topbar in
   signed-out state; the form lives in a centered card. */

function AuthShell({ children }) {
  return (
    <div className="grain" style={{
      width: 1440, height: 1040, background: "var(--paper)", color: "var(--ink)",
      display: "grid", gridTemplateColumns: "232px 1fr", fontFamily: "var(--sans)",
    }}>
      <ArchiveSidebar active="Discover" auth="out" />
      <div style={{ display: "flex", flexDirection: "column", minWidth: 0 }}>
        <ArchiveTopbar auth="out" />
        <main style={{
          flex: 1, display: "flex", alignItems: "center", justifyContent: "center",
          background: "var(--paper-2)", padding: 40, overflow: "hidden",
        }}>
          {children}
        </main>
      </div>
    </div>
  );
}

function Field({ label, type = "text", value = "", placeholder = "", autoComplete, sub, help, icon, error }) {
  const Icon = icon ? I[icon] : null;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{
        display: "flex", justifyContent: "space-between", alignItems: "baseline",
        fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.14em",
        color: "var(--muted)", textTransform: "uppercase",
      }}>
        <label>{label}</label>
        {sub && <span style={{ color: "var(--ink-2)" }}>{sub}</span>}
      </div>
      <div style={{
        display: "flex", alignItems: "center", gap: 10,
        padding: "12px 14px",
        background: "var(--paper)",
        border: `1px solid ${error ? "#b1311f" : "var(--hair)"}`,
        borderRadius: 4,
      }}>
        {Icon && <Icon size={15} stroke={1.5} />}
        <input
          type={type}
          defaultValue={value}
          placeholder={placeholder}
          autoComplete={autoComplete}
          style={{
            flex: 1, border: "none", outline: "none", background: "transparent",
            fontFamily: "var(--sans)", fontSize: 14, color: "var(--ink)",
          }}
        />
      </div>
      {(help || error) && (
        <div style={{
          fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.06em",
          color: error ? "#b1311f" : "var(--muted)",
        }}>{error || help}</div>
      )}
    </div>
  );
}

function AuthLogin() {
  return (
    <AuthShell>
      <div style={{
        width: 460, padding: 40, background: "var(--paper)",
        border: "1px solid var(--hair)", boxShadow: "0 8px 32px rgba(0,0,0,0.04)",
      }}>
        <div className="kicker" style={{ color: "var(--muted)" }}>Sign in</div>
        <h1 className="display" style={{
          fontSize: 48, lineHeight: 0.98, margin: "8px 0 0", letterSpacing: "-0.02em",
        }}>
          Welcome back, <span className="italic-d">archivist.</span>
        </h1>
        <p style={{ marginTop: 12, fontSize: 13, color: "var(--ink-2)", lineHeight: 1.55 }}>
          Sign in to spend coins, save favorites, and upload your own specimens.
        </p>

        <hr className="spec-rule" style={{ margin: "24px 0" }} />

        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <Field label="Email" type="email" icon="mail" placeholder="you@example.com" autoComplete="email" />
          <Field label="Password" type="password" icon="lock" placeholder="••••••••"
                 autoComplete="current-password" sub="Forgot?" />
        </div>

        <button style={{
          marginTop: 24, width: "100%", padding: "14px 18px",
          background: "var(--ink)", color: "var(--paper)", border: "none",
          fontFamily: "var(--sans)", fontWeight: 600, fontSize: 14, letterSpacing: "-0.01em",
          borderRadius: 999, cursor: "pointer",
          display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 10,
        }}>
          Sign in <I.arrow size={14} />
        </button>

        <div style={{
          marginTop: 18, textAlign: "center",
          fontFamily: "var(--sans)", fontSize: 13, color: "var(--ink-2)",
        }}>
          New to the archive?
          <a href="#" style={{
            marginLeft: 6, color: "var(--ink)", textDecoration: "underline",
            textDecorationColor: "var(--hair)", textUnderlineOffset: 4,
          }}>Register →</a>
        </div>
      </div>
    </AuthShell>
  );
}

function AuthRegister() {
  return (
    <AuthShell>
      <div style={{
        width: 480, padding: 40, background: "var(--paper)",
        border: "1px solid var(--hair)", boxShadow: "0 8px 32px rgba(0,0,0,0.04)",
      }}>
        <div className="kicker" style={{ color: "var(--muted)" }}>Register</div>
        <h1 className="display" style={{
          fontSize: 44, lineHeight: 0.98, margin: "8px 0 0", letterSpacing: "-0.02em",
        }}>
          Join the <span className="italic-d">archive.</span>
        </h1>
        <p style={{ marginTop: 12, fontSize: 13, color: "var(--ink-2)", lineHeight: 1.55 }}>
          Free. Get <span style={{ color: "var(--accent)", fontWeight: 600 }}>3 coins</span> on signup;
          earn <span style={{ color: "var(--accent)", fontWeight: 600 }}>+5</span> for every wallpaper you contribute.
        </p>

        <hr className="spec-rule" style={{ margin: "24px 0" }} />

        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <Field label="Username" icon="user" placeholder="marin.k"
                 help="3–24 chars · letters, numbers, dot, underscore" autoComplete="username" />
          <Field label="Email" type="email" icon="mail" placeholder="you@example.com" autoComplete="email" />
          <Field label="Password" type="password" icon="lock" placeholder="At least 8 characters"
                 autoComplete="new-password" />
        </div>

        <label style={{
          marginTop: 18, display: "flex", gap: 10, alignItems: "flex-start",
          fontFamily: "var(--sans)", fontSize: 12, color: "var(--ink-2)", cursor: "pointer",
        }}>
          <span style={{
            width: 14, height: 14, marginTop: 2, flexShrink: 0,
            borderRadius: 3, border: "1px solid var(--ink)", background: "var(--ink)",
            display: "inline-flex", alignItems: "center", justifyContent: "center", color: "#fff",
          }}>
            <I.check size={9} stroke={2.4} />
          </span>
          <span>
            I accept the <a href="#" style={{ color: "var(--ink)" }}>Terms</a> and
            acknowledge the <a href="#" style={{ color: "var(--ink)" }}>Privacy Policy</a> and
            <a href="#" style={{ color: "var(--ink)" }}> DMCA notice</a>.
          </span>
        </label>

        <button style={{
          marginTop: 22, width: "100%", padding: "14px 18px",
          background: "var(--ink)", color: "var(--paper)", border: "none",
          fontFamily: "var(--sans)", fontWeight: 600, fontSize: 14, letterSpacing: "-0.01em",
          borderRadius: 999, cursor: "pointer",
          display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 10,
        }}>
          Create account · <span style={{ color: "var(--accent)" }}>get 3 coins</span>
        </button>

        <div style={{
          marginTop: 18, textAlign: "center",
          fontFamily: "var(--sans)", fontSize: 13, color: "var(--ink-2)",
        }}>
          Already have an account?
          <a href="#" style={{
            marginLeft: 6, color: "var(--ink)", textDecoration: "underline",
            textDecorationColor: "var(--hair)", textUnderlineOffset: 4,
          }}>Sign in →</a>
        </div>
      </div>
    </AuthShell>
  );
}

Object.assign(window, { AuthLogin, AuthRegister });
