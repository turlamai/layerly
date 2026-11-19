// Materials — filament inventory cards with layerbar fill, filter chips,
// the shopping list (AI suggestions land here only via confirm cards) and
// purchase records. Registering a spool opens a form modal.

import { useCallback, useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { Material, Purchase, ShoppingItem } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, Layerbar, StatusPill } from '../components/ui';

export default function Materials() {
  const { t, showToast } = useApp();
  const [materials, setMaterials] = useState<Material[]>([]);
  const [shopping, setShopping] = useState<ShoppingItem[]>([]);
  const [purchases, setPurchases] = useState<Purchase[]>([]);
  const [filter, setFilter] = useState<'all' | 'low'>('all');
  const [registering, setRegistering] = useState(false);
  const [form, setForm] = useState({ name: '', brand: '', type: 'PLA', 'color-name': '', 'color-hex': '#888888', 'remaining-g': 1000, 'total-g': 1000 });

  const load = useCallback(() => {
    void api.materials.list().then((r) => setMaterials(r.materials)).catch(() => void 0);
    void api.shopping.list().then((r) => setShopping(r.items)).catch(() => void 0);
    void api.purchases.list().then((r) => setPurchases(r.purchases)).catch(() => void 0);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const visible = materials.filter(
    (m) => filter === 'all' || m['remaining-g'] / Math.max(1, m['total-g']) < 0.2
  );
  const stock = materials.reduce((acc, m) => acc + m['remaining-g'], 0);

  return (
    <>
      <div className="topbar">
        <h1>{t('materials.title')}</h1>
        <span className="sub">
          <span className="num">{materials.length}</span> {t('materials.count')}{' '}
          <span className="num">{(stock / 1000).toFixed(1)} {t('misc.kg')}</span>
        </span>
        <span className="sp" />
        <button className="btn primary" onClick={() => setRegistering(true)}>
          <Icon name="plus" />
          {t('materials.register')}
        </button>
      </div>
      <div className="content">
        <div className="grid">
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {(['all', 'low'] as const).map((f) => (
              <button
                key={f}
                className={`chip ${filter === f ? 'accent' : ''}`}
                style={{ cursor: 'pointer' }}
                onClick={() => setFilter(f)}
              >
                {t(f === 'all' ? 'materials.filter.all' : 'materials.filter.low')}
              </button>
            ))}
            {['PLA', 'PETG', 'ABS'].map((ty) => (
              <span className="chip" key={ty}>
                {ty}
              </span>
            ))}
          </div>

          <div className="grid" style={{ gridTemplateColumns: 'repeat(3,1fr)' }}>
            {visible.map((m) => {
              const pct = (m['remaining-g'] / Math.max(1, m['total-g'])) * 100;
              return (
                <div className="card pad material-card" key={m.id}>
                  <div className="m-head">
                    <div className="swatch" style={{ background: m['color-hex'] }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="m-title">
                        {m.name}
                        {m.brand ? ` · ${m.brand}` : ''}
                      </div>
                      <div className="m-grams">
                        {m['remaining-g']} {t('misc.g')}{' '}
                        <small>/ {m['total-g']} {t('misc.g')}</small>
                      </div>
                    </div>
                  </div>
                  <Layerbar
                    percent={pct}
                    variant={pct < 20 ? 'warn' : undefined}
                  />
                  <div className="m-foot">
                    {m.slot > 0 ? (
                      <span className="chip">
                        {t('materials.slot')} <span className="num">{m.slot}</span>
                      </span>
                    ) : (
                      <span className="chip">{t('materials.external')}</span>
                    )}
                    {m['opened-date'] ? (
                      <span className="chip">
                        {t('materials.opened')} <span className="num">{m['opened-date'].slice(5)}</span>
                      </span>
                    ) : (
                      <span className="chip">{t('materials.sealed')}</span>
                    )}
                    <span className="sp" />
                    {m.status === 'moisture-risk' ? (
                      <span className="badge warn">
                        {t('materials.moisture-risk')}{' '}
                        <span className="num">
                          {Math.round((Date.now() - new Date(m['opened-date']).getTime()) / 86400000)}
                        </span>{' '}
                        {t('materials.days')}
                      </span>
                    ) : m.slot > 0 ? (
                      <span className="badge accent">{t('materials.in-use')}</span>
                    ) : null}
                    <button
                      className="btn ghost small"
                      onClick={() =>
                        void api.materials.delete(m.id).then(() => {
                          showToast(t('materials.remove'));
                          load();
                        })
                      }
                    >
                      {t('materials.remove')}
                    </button>
                  </div>
                </div>
              );
            })}
            <div
              className="card pad dashed"
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 8,
                color: 'var(--mute)',
                textAlign: 'center',
                cursor: 'pointer',
              }}
              onClick={() => setRegistering(true)}
            >
              <Icon name="plus" size={20} />
              <div style={{ fontSize: 12.5 }}>{t('materials.register-third-party')}</div>
            </div>
          </div>

          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr', alignItems: 'start' }}>
            <div className="card">
              <div className="card-h">
                {t('materials.shopping')}
                <span className="sp" />
                <span className="badge num">{shopping.length}</span>
              </div>
              <div className="table">
                {shopping.map((s) => (
                  <div className="trow" key={s.id}>
                    <div className="grow">
                      {s.name} · <span className="num">{s.qty}</span> {t('dash.piece')}
                      {s.source === 'ai' ? (
                        <>
                          <span className="dim"> · {t('materials.from-advisor')}</span>{' '}
                          <span className="badge v2">AI</span>
                        </>
                      ) : null}
                    </div>
                    <span className="dim num">¥{s.price}</span>
                    <button
                      className="btn ghost small"
                      onClick={() =>
                        void api.shopping.delete(s.id).then(() => {
                          showToast(t('materials.remove'));
                          load();
                        })
                      }
                    >
                      {t('materials.remove')}
                    </button>
                  </div>
                ))}
                {shopping.length === 0 ? <Empty icon="materials" title={t('materials.shopping')} /> : null}
              </div>
              <div style={{ borderTop: '1px solid var(--line)', padding: '10px 16px', fontSize: 11.5, color: 'var(--mute)' }}>
                {t('materials.no-auto-order')}
              </div>
            </div>

            <div className="card">
              <div className="card-h">{t('materials.purchases')}</div>
              <div className="table">
                {purchases.map((p) => (
                  <div className="trow" key={p.id}>
                    <span className="dim num">{p['purchased-at'].slice(5)}</span>
                    <div className="grow">
                      {p.name} · <span className="num">{p.qty}</span>
                    </div>
                    {p.arrived ? (
                      <StatusPill status="done" />
                    ) : (
                      <button
                        className="btn ghost small"
                        onClick={() => void api.purchases.arrive(p.id).then(load)}
                      >
                        {t('status.arrived')}
                      </button>
                    )}
                  </div>
                ))}
                {purchases.length === 0 ? <Empty icon="history" title={t('materials.purchases')} /> : null}
              </div>
            </div>
          </div>
        </div>
      </div>

      {registering ? (
        <div className="modal-backdrop" onClick={() => setRegistering(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="m-title">{t('materials.register')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="mt-name">{t('materials.name')}</label>
              <input id="mt-name" className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              <label className="label" htmlFor="mt-brand">{t('materials.brand')}</label>
              <input id="mt-brand" className="input" value={form.brand} onChange={(e) => setForm({ ...form, brand: e.target.value })} />
              <label className="label" htmlFor="mt-type">{t('materials.type')}</label>
              <select id="mt-type" className="input" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value })}>
                {['PLA', 'PETG', 'ABS', 'ASA', 'TPU', 'PA'].map((ty) => (
                  <option key={ty}>{ty}</option>
                ))}
              </select>
              <label className="label" htmlFor="mt-cname">{t('materials.color-name')}</label>
              <input id="mt-cname" className="input" value={form['color-name']} onChange={(e) => setForm({ ...form, 'color-name': e.target.value })} />
              <label className="label" htmlFor="mt-chex">{t('materials.color-hex')}</label>
              <input id="mt-chex" className="input" value={form['color-hex']} onChange={(e) => setForm({ ...form, 'color-hex': e.target.value })} />
              <label className="label" htmlFor="mt-rem">{t('materials.remaining')}</label>
              <input id="mt-rem" className="input num" type="number" value={form['remaining-g']} onChange={(e) => setForm({ ...form, 'remaining-g': Number(e.target.value) })} />
              <label className="label" htmlFor="mt-total">{t('materials.total')}</label>
              <input id="mt-total" className="input num" type="number" value={form['total-g']} onChange={(e) => setForm({ ...form, 'total-g': Number(e.target.value) })} />
            </div>
            <div className="m-actions">
              <button className="btn ghost" onClick={() => setRegistering(false)}>
                {t('confirm.cancel')}
              </button>
              <button
                className="btn primary"
                disabled={!form.name.trim()}
                onClick={() => {
                  void api.materials
                    .create({ ...form, name: form.name.trim() })
                    .then(() => {
                      setRegistering(false);
                      setForm({ ...form, name: '', brand: '' });
                      showToast(t('settings.saved'));
                      load();
                    })
                    .catch(() => showToast(t('misc.error')));
                }}
              >
                {t('confirm.ok')}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
