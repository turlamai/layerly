// Settings — appearance (theme/language), the BYOK AI config (keys stay
// in the backend; the UI sees the __SAVED__ sentinel), data notes and
// the optional demo seed (refuses when the library isn't empty).

import { useCallback, useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { AdvisorSettings } from '@layerly/core';
import { useApp, type Theme } from '../state/store';
import type { Lang } from '../i18n';
import { Icon } from '../components/ui';

export default function Settings() {
  const { version, t, showToast, theme, setTheme, lang, setLang } = useApp();
  const [ai, setAi] = useState<AdvisorSettings | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    void api.advisor
      .settingsView()
      .then((s) => setAi(s))
      .catch(() => void 0);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <>
      <div className="topbar">
        <h1>{t('settings.title')}</h1>
        <span className="sp" />
        <span className="badge num">v{version}</span>
      </div>
      <div className="content">
        <div className="grid" style={{ gridTemplateColumns: '1fr', maxWidth: 720 }}>
          <div className="card pad">
            <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 12 }}>{t('settings.appearance')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="st-theme">{t('settings.theme')}</label>
              <select
                id="st-theme"
                className="input"
                value={theme}
                onChange={(e) => setTheme(e.target.value as Theme)}
              >
                <option value="light">{t('settings.theme.light')}</option>
                <option value="dark">{t('settings.theme.dark')}</option>
              </select>
              <label className="label" htmlFor="st-lang">{t('settings.language')}</label>
              <select
                id="st-lang"
                className="input"
                value={lang}
                onChange={(e) => setLang(e.target.value as Lang)}
              >
                <option value="zh">简体中文</option>
                <option value="en">English</option>
              </select>
            </div>
          </div>

          <div className="card pad">
            <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 4 }}>{t('settings.ai')}</div>
            <div className="settings-note" style={{ marginBottom: 12 }}>
              {t('settings.ai-note')}
            </div>
            {ai ? (
              <div className="form-grid">
                <label className="label" htmlFor="st-provider">{t('settings.provider')}</label>
                <select
                  id="st-provider"
                  className="input"
                  value={ai.provider}
                  onChange={(e) => setAi({ ...ai, provider: e.target.value })}
                >
                  {ai.presets.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.label}
                    </option>
                  ))}
                </select>
                <label className="label" htmlFor="st-model">{t('settings.model')}</label>
                <input
                  id="st-model"
                  className="input"
                  value={ai.model}
                  placeholder={ai.presets.find((p) => p.id === ai.provider)?.model ?? ''}
                  onChange={(e) => setAi({ ...ai, model: e.target.value })}
                />
                <label className="label" htmlFor="st-key">{t('settings.api-key')}</label>
                <input
                  id="st-key"
                  className="input"
                  type="password"
                  value={apiKey}
                  placeholder={ai['api-key'] || 'sk-…'}
                  onChange={(e) => setApiKey(e.target.value)}
                />
                <span className="label" />
                <div className="m-actions" style={{ justifyContent: 'flex-start' }}>
                  <button
                    className="btn primary small"
                    disabled={busy}
                    onClick={() => {
                      setBusy(true);
                      void api.advisor
                        .settingsSave({
                          provider: ai.provider,
                          model: ai.model,
                          ...(apiKey ? { 'api-key': apiKey } : {}),
                        })
                        .then(() => {
                          setApiKey('');
                          showToast(t('settings.saved'));
                          load();
                        })
                        .catch(() => showToast(t('misc.error')))
                        .finally(() => setBusy(false));
                    }}
                  >
                    <Icon name="shield" />
                    {t('settings.saved')}
                  </button>
                </div>
              </div>
            ) : null}
          </div>

          <div className="card pad">
            <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 4 }}>{t('settings.data')}</div>
            <div className="settings-note" style={{ marginBottom: 12 }}>
              {t('settings.data-note')}
            </div>
            <button
              className="btn"
              onClick={() => {
                void useApp
                  .getState()
                  .seedDemo()
                  .then(() => showToast(t('settings.seeded')))
                  .catch(() => showToast(t('settings.seed-refused')));
              }}
            >
              {t('settings.seed-demo')}
            </button>
          </div>

          <div className="card pad">
            <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8 }}>{t('settings.about')}</div>
            <div className="kv">
              {t('settings.version')} <b>{version}</b>
            </div>
            <div className="settings-note" style={{ marginTop: 8 }}>
              {t('prep.only-here')} · {t('materials.no-auto-order')}
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
