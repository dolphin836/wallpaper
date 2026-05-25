import { useCallback, useEffect, useState } from 'react';
import LoginScreen from './screens/LoginScreen';
import HomeScreen from './screens/HomeScreen';
import { getToken } from './lib/auth';
import './App.css';

// App boot order:
//   1. Try to read a stored JWT — if present, sign-in is implicit.
//   2. Either way, the Home screen renders. Browsing is open;
//      Login is overlaid on demand (clicking the sign-in button or
//      triggering an action that requires auth, e.g. download).
//
// This matches the macOS client's "browse first, sign in when you
// download" pattern.
export default function App() {
  const [token, setToken] = useState<string | null>(null);
  const [booted, setBooted] = useState(false);
  const [loginOpen, setLoginOpen] = useState(false);

  useEffect(() => {
    getToken().then((t) => {
      setToken(t);
      setBooted(true);
    });
  }, []);

  const requestSignIn = useCallback(() => setLoginOpen(true), []);

  if (!booted) {
    return <div className="screen-center muted">Loading…</div>;
  }

  return (
    <>
      <HomeScreen
        token={token}
        onRequestSignIn={requestSignIn}
        onSignOut={() => setToken(null)}
      />
      {loginOpen && (
        <LoginScreen
          onSignedIn={(t) => {
            setToken(t);
            setLoginOpen(false);
          }}
          onCancel={() => setLoginOpen(false)}
        />
      )}
    </>
  );
}
