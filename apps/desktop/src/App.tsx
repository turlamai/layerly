import { useEffect, useState } from 'react';
import { api, hasBackend } from '@layerly/core';

// Skeleton shell: proves the typed bridge end to end. The real UI follows
// the design baseline in design/prototype/ (see design/DESIGN.md).
export default function App() {
  const [status, setStatus] = useState('connecting…');

  useEffect(() => {
    hasBackend().then((ok) => {
      if (!ok) {
        setStatus('backend unavailable');
        return;
      }
      api
        .appInfo()
        .then((info) =>
          setStatus(`layerly ${info.version} — backend connected`),
        )
        .catch(() => setStatus('backend unreachable'));
    });
  }, []);

  return (
    <main className="boot">
      <div className="boot-mark" aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
      <p>{status}</p>
    </main>
  );
}
