// Bridge to the Layerly Racket backend.
//
// Two transports behind one interface (same shape the family uses):
//  - native: the page runs on the controlled glaze:// origin; calls ride
//    the GLZ1 message handler (window.__glz1, injected at document
//    start). No TCP port exists in production.
//  - http: the page is served by the loopback server (vite dev) and
//    talks plain relative fetch.
//
// Streaming routes (advisor chat) will adopt the family line protocol:
// first line `OK` then raw bytes, or `ERR <status> <message>`.

interface Glz1 {
  invoke(
    path: string,
    args?: unknown,
    opts?: { method?: string; timeoutMs?: number }
  ): Promise<unknown>;
}

declare global {
  interface Window {
    __glz1?: Glz1;
  }
}

function nativeBridge(): Glz1 | null {
  return (typeof window !== 'undefined' && window.__glz1) || null;
}

let probe: Promise<boolean> | null = null;

/** True once a backend answers — native bridge present, or /api/health ok. */
export function hasBackend(): Promise<boolean> {
  if (!probe) {
    const g = nativeBridge();
    probe = g
      ? Promise.resolve(true)
      : fetch('/api/health', { method: 'POST' })
          .then((r) => r.ok)
          .catch(() => false);
  }
  return probe;
}

/** POST JSON to the backend; returns the parsed response. */
export async function apiPost<T>(path: string, body?: unknown): Promise<T> {
  const g = nativeBridge();
  if (g) {
    return (await g.invoke(path, body ?? {})) as T;
  }
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`${path} failed: ${res.status} ${detail.slice(0, 200)}`);
  }
  return (await res.json()) as T;
}

// ---- typed helpers over the backend routes -------------------------------

export interface AppInfo {
  name: string;
  version: string;
}

export const api = {
  health: () => apiPost<{ ok: boolean; version: string }>('/api/health'),
  appInfo: () => apiPost<AppInfo>('/api/app/info'),
};
