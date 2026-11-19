// Single zustand store — view routing, theme/language, the polled device
// snapshot + library counts, and transient feedback (toast). Screens own
// their data fetches; the store only holds what more than one screen
// needs (the family store pattern).

import { create } from 'zustand';
import { api, hasBackend } from '@layerly/core';
import type { DeviceSnapshot, LibraryCounts } from '@layerly/core';
import { detectLang, translate, type Lang } from '../i18n';

export type View =
  | 'onboarding'
  | 'dashboard'
  | 'projects'
  | 'project'
  | 'print-prep'
  | 'model-viewer'
  | 'devices'
  | 'history'
  | 'materials'
  | 'advisor'
  | 'settings';

export type Theme = 'light' | 'dark';

interface AppState {
  booted: boolean;
  backendOk: boolean;
  version: string;
  view: View;
  viewId: string | null;
  theme: Theme;
  lang: Lang;
  device: DeviceSnapshot | null;
  counts: LibraryCounts | null;
  toast: string | null;
  t: (key: string, vars?: Record<string, string | number>) => string;

  boot: () => Promise<void>;
  go: (view: View, id?: string) => void;
  setTheme: (theme: Theme) => void;
  setLang: (lang: Lang) => void;
  poll: () => Promise<void>;
  showToast: (message: string) => void;
  seedDemo: () => Promise<void>;
}

let pollTimer: ReturnType<typeof setInterval> | null = null;
let toastTimer: ReturnType<typeof setTimeout> | null = null;

function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
}

export const useApp = create<AppState>((set, get) => ({
  booted: false,
  backendOk: false,
  version: '',
  view: 'dashboard',
  viewId: null,
  theme: 'light',
  lang: detectLang(),
  device: null,
  counts: null,
  toast: null,
  t: (key, vars) => translate(get().lang, key, vars),

  boot: async () => {
    const backendOk = await hasBackend();
    let version = '';
    let theme: Theme = 'light';
    let view: View = 'dashboard';
    if (backendOk) {
      try {
        version = (await api.appInfo()).version;
        const [t, onboarding] = await Promise.all([
          api.settings.get('theme'),
          api.settings.get('onboarding-done'),
        ]);
        if (t.value === 'light' || t.value === 'dark') theme = t.value;
        if (onboarding.value !== true) view = 'onboarding';
      } catch {
        // first boot without persisted settings — defaults hold
      }
    }
    applyTheme(theme);
    set({ booted: true, backendOk, version, theme, view });
    // reconnect the last session's device so the sidebar foot is live
    // (the fixture/printer link does not survive a backend restart)
    try {
      const last = await api.settings.get('last-device');
      if (typeof last.value === 'string' && last.value) {
        await api.device.connect(last.value);
      }
    } catch {
      // no last device or it refuses the handshake — Devices screen handles it
    }
    // poll the workbench summary: device snapshot + counts
    void get().poll();
    if (!pollTimer) {
      pollTimer = setInterval(() => void get().poll(), 1500);
    }
  },

  go: (view, id) => set({ view, viewId: id ?? null }),

  setTheme: (theme) => {
    applyTheme(theme);
    set({ theme });
    void api.settings.set('theme', theme).catch(() => void 0);
  },

  setLang: (lang) => {
    set({ lang });
    void api.settings.set('lang', lang).catch(() => void 0);
  },

  poll: async () => {
    if (!get().backendOk) return;
    try {
      const summary = await api.librarySummary();
      set({ device: summary.device, counts: summary.counts });
    } catch {
      // transient backend hiccup — the next tick retries
    }
  },

  showToast: (message) => {
    set({ toast: message });
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => set({ toast: null }), 2600);
  },

  seedDemo: async () => {
    await api.demo.seed();
    const summary = await api.librarySummary();
    set({ counts: summary.counts, device: summary.device });
  },
}));
