import { useEffect, useState } from 'react';
import LoginScreen from './screens/LoginScreen';
import HomeScreen from './screens/HomeScreen';
import { getToken } from './lib/auth';
import './App.css';

// App swaps between the Login screen and the Home (browse + download)
// screen based on whether a JWT is sitting in app-local storage. No
// router yet — the surface is one window of fixed content, like the
// macOS popover.
export default function App() {
  const [token, setToken] = useState<string | null>(null);
  const [booted, setBooted] = useState(false);

  useEffect(() => {
    getToken().then((t) => {
      setToken(t);
      setBooted(true);
    });
  }, []);

  if (!booted) {
    return <div className="screen-center muted">Loading…</div>;
  }

  return token ? (
    <HomeScreen onSignOut={() => setToken(null)} />
  ) : (
    <LoginScreen onSignedIn={(t) => setToken(t)} />
  );
}
