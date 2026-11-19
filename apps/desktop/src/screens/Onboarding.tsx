// Onboarding — first run: connect a printer (add by IP or use the
// synthetic fixture), optional BYOK AI config, done → workbench. Honest
// about what is and isn't scanned (no LAN auto-discovery in v1).

import { useState } from 'react';
import { api } from '@layerly/core';
import { useApp } from '../state/store';
import { Icon } from '../components/ui';

export default function Onboarding() {
  const { go, t, setLang, lang, setTheme, theme } = useApp();
  const [step, setStep] = useState(1);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({ name: 'X1 Carbon', model: 'X1 Carbon', host: '', serial: '', 'access-code': '', kind: 'fixture' });
  const [connected, setConnected] = useState(false);
  const [provider, setProvider] = useState('ollama');
  const [apiKey, setApiKey] = useState('');

  const finish = async () => {
    setBusy(true);
    try {
      await api.settings.set('onboarding-done', true);
      await api.settings.set('ai-configured', apiKey !== '');
      go('dashboard');
    } finally {
      setBusy(false);
    }
  };

  const connectDevice = async () => {
    setBusy(true);
    try {
      const res = await api.device.create({
        name: form.name || form.model,
        model: form.model,
        host: form.host,
        serial: form.serial,
        'access-code': form['access-code'],
        kind: form.kind,
      });
      setConnected(res.snapshot.connected);
    } catch (e) {
      // a real device that refuses the handshake still lands in the
      // library — connect later from the Devices screen
      setConnected(false);
      void e;
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="ob-wrap">
      <div className="card ob-card">
        <div className="ob-head">
          <div className="brand" style={{ padding: 0 }}>
            <div className="mark">L</div>
            <div className="name" style={{ fontSize: 18 }}>
              {t('app.name')}
            </div>
          </div>
          <div className="ob-sub">{t('ob.tagline')}</div>
        </div>

        <div className="steps">
          {[1, 2, 3].map((n) => (
            <span key={n} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span className={`step ${n === step ? 'cur' : n < step ? 'good' : 'todo'}`}>{n}</span>
              {n < 3 ? <span className="step-bar" /> : null}
            </span>
          ))}
          <span className="steps-label num">{t('ob.step', { n: step })}</span>
        </div>

        {step === 1 ? (
          <div className="ob-step-body">
            <div className="ob-title">{t('ob.step1-title')}</div>
            <div className="ob-desc">{t('ob.step1-desc')}</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <select
                className="input"
                value={form.kind}
                onChange={(e) => setForm({ ...form, kind: e.target.value })}
              >
                <option value="fixture">{t('devices.demo-tag')} — {t('ob.add-demo')}</option>
                <option value="bambu">Bambu Lab (LAN)</option>
              </select>
              {form.kind === 'bambu' ? (
                <div style={{ display: 'grid', gridTemplateColumns: '110px 1fr', gap: 8 }}>
                  <input className="input" placeholder={t('materials.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
                  <input className="input" placeholder="IP · 192.168.1.x" value={form.host} onChange={(e) => setForm({ ...form, host: e.target.value })} />
                  <input className="input" placeholder="S/N" value={form.serial} onChange={(e) => setForm({ ...form, serial: e.target.value })} />
                  <input className="input" type="password" placeholder="Access code" value={form['access-code']} onChange={(e) => setForm({ ...form, 'access-code': e.target.value })} />
                </div>
              ) : null}
            </div>
            <div className="ob-foot-row">
              <button className="btn ghost small" onClick={() => setLang(lang === 'zh' ? 'en' : 'zh')}>
                {lang === 'zh' ? 'English' : '中文'}
              </button>
              <button className="btn ghost small" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}>
                ◐ {t('settings.theme')}
              </button>
            </div>
          </div>
        ) : step === 2 ? (
          <div className="ob-step-body">
            <div className="ob-title">{t('ob.step2-title')}</div>
            <div className="ob-desc">{t('ob.step2-desc')}</div>
            <div style={{ display: 'grid', gridTemplateColumns: '110px 1fr', gap: 8 }}>
              <label className="label" htmlFor="ob-provider">{t('ob.provider')}</label>
              <select id="ob-provider" className="input" value={provider} onChange={(e) => setProvider(e.target.value)}>
                <option value="ollama">Ollama (local)</option>
                <option value="deepseek">DeepSeek</option>
                <option value="glm">GLM (Zhipu)</option>
                <option value="openai">OpenAI</option>
                <option value="anthropic">Anthropic</option>
              </select>
              <label className="label" htmlFor="ob-key">{t('settings.api-key')}</label>
              <input id="ob-key" className="input" type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} placeholder={provider === 'ollama' ? '—' : 'sk-…'} />
            </div>
          </div>
        ) : (
          <div className="ob-step-body">
            <div className="ob-title">{t('ob.finish-title')}</div>
            <div className="ob-desc">{t('ob.finish-body')}</div>
            {connected ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                <span className="dot on" />
                {form.name} · {t('foot.connected')}
              </div>
            ) : null}
          </div>
        )}

        <hr className="divider" style={{ margin: 0 }} />
        <div className="ob-foot-row">
          <button className="btn ghost small" onClick={() => void finish()}>
            {t('ob.skip')}
          </button>
          <span style={{ flex: 1 }} />
          {step === 1 ? (
            <>
              <button className="btn" disabled={busy} onClick={() => void connectDevice().then(() => setStep(2))}>
                <Icon name="devices" />
                {connected ? t('ob.selected') : t('devices.connect')}
              </button>
              <button className="btn primary" onClick={() => setStep(2)}>
                {t('ob.next-ai')}
              </button>
            </>
          ) : step === 2 ? (
            <>
              <button className="btn ghost small" onClick={() => setStep(3)}>
                {t('ob.skip')}
              </button>
              <button
                className="btn primary"
                disabled={busy}
                onClick={() => {
                  void api.advisor
                    .settingsSave({ provider, 'api-key': apiKey || undefined })
                    .then(() => setStep(3))
                    .catch(() => setStep(3));
                }}
              >
                {t('ob.finish')}
              </button>
            </>
          ) : (
            <button className="btn primary" disabled={busy} onClick={() => void finish()}>
              <Icon name="overview" />
              {t('ob.open-workbench')}
            </button>
          )}
        </div>
      </div>

      <div className="ob-note">{t('ob.note')}</div>
    </div>
  );
}
