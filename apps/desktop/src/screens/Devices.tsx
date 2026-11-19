// Devices — printer state, AMS slots, live layer progress, pause/resume/
// stop (stop double-confirms — destructive), device onboarding (add by
// IP; the synthetic fixture for demo flows), maintenance rows.

import { useCallback, useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { Device, DeviceSnapshot } from '@layerly/core';
import { useApp } from '../state/store';
import { ConfirmModal, Empty, Icon, Layerbar, StatusPill, type ConfirmState } from '../components/ui';

export default function Devices() {
  const { device, t, showToast } = useApp();
  const [devices, setDevices] = useState<Device[]>([]);
  const [confirm, setConfirm] = useState<ConfirmState | null>(null);
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ name: '', model: 'X1 Carbon', host: '', serial: '', 'access-code': '', kind: 'bambu' });
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    void api.device
      .list()
      .then((r) => setDevices(r.devices))
      .catch(() => void 0);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const snap: DeviceSnapshot | null = device;
  const job = snap?.job ?? null;
  const printing = snap?.state === 'printing';
  const paused = snap?.state === 'paused';

  const connect = async (id: string) => {
    try {
      await api.device.connect(id);
      showToast(t('foot.connected'));
    } catch (e) {
      showToast(e instanceof Error ? e.message : t('misc.error'));
    }
  };

  return (
    <>
      <div className="topbar">
        <h1>{t('devices.title')}</h1>
        <span className="sub">
          <span className="num">{devices.length}</span> {t('devices.connected')}
        </span>
        <span className="sp" />
        <button className="btn" onClick={() => setAdding(true)}>
          <Icon name="plus" />
          {t('devices.add')}
        </button>
      </div>
      <div className="content">
        {devices.length === 0 ? (
          <div className="card">
            <Empty
              icon="devices"
              title={t('devices.title')}
              sub={t('devices.empty')}
              action={
                <button className="btn primary" onClick={() => setAdding(true)}>
                  {t('devices.add')}
                </button>
              }
            />
          </div>
        ) : (
          <div className="grid">
            <div className="card">
              <div className="card-h">
                {snap?.connected ? snap.name : devices[0]?.name}
                <span className="badge">{snap?.kind === 'fixture' ? t('devices.demo-tag') : t('devices.lan')}</span>
                <span className="sp" />
                {snap?.connected ? (
                  <StatusPill status={snap.state === 'idle' ? 'done' : snap.state === 'paused' ? 'paused' : 'printing'} />
                ) : (
                  <button className="btn small" onClick={() => devices[0] && void connect(devices[0].id)}>
                    {t('devices.connect')}
                  </button>
                )}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 280px', gap: 18, padding: '14px 16px' }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10, minWidth: 0 }}>
                  <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.8px', color: 'var(--mute)' }}>
                    {t('devices.current-job')}
                  </div>
                  {job ? (
                    <>
                      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                        <span style={{ fontSize: 14.5, fontWeight: 700 }}>{job.name}</span>
                        <span style={{ fontSize: 12.5, color: 'var(--mute)' }}>
                          {t('history.piece-n', { n: `${job.seq}/${job.total}` })}
                        </span>
                      </div>
                      <Layerbar percent={job.layers ? (job.layer / job.layers) * 100 : 0} />
                      <div style={{ fontSize: 12.5, color: 'var(--mute)' }}>
                        <span className="num">
                          L{job.layer}/{job.layers}
                        </span>{' '}
                        · {t('dash.remaining')} <span className="num">{Math.max(0, Math.round(job['minutes-left']))}</span>{' '}
                        {t('dash.minutes')}
                      </div>
                    </>
                  ) : (
                    <div style={{ fontSize: 12.5, color: 'var(--mute)' }}>
                      {snap?.connected ? t('foot.idle') : t('misc.device-none')}
                    </div>
                  )}
                  <div className="grid" style={{ gridTemplateColumns: 'repeat(4,1fr)', gap: 8 }}>
                    <div className="card metric tight">
                      <span className="k">{t('devices.nozzle')}</span>
                      <span className="v">
                        {Math.round(snap?.['nozzle-temp'] ?? 0)}
                        <small>°C</small>
                      </span>
                    </div>
                    <div className="card metric tight">
                      <span className="k">{t('devices.bed')}</span>
                      <span className="v">
                        {Math.round(snap?.['bed-temp'] ?? 0)}
                        <small>°C</small>
                      </span>
                    </div>
                    <div className="card metric tight">
                      <span className="k">{t('devices.chamber')}</span>
                      <span className="v">
                        {Math.round(snap?.['chamber-temp'] ?? 0)}
                        <small>°C</small>
                      </span>
                    </div>
                    <div className="card metric tight">
                      <span className="k">{t('devices.fan')}</span>
                      <span className="v">
                        {Math.round(snap?.['fan-percent'] ?? 0)}
                        <small>%</small>
                      </span>
                    </div>
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.8px', color: 'var(--mute)' }}>AMS</div>
                  {(snap?.ams ?? []).map((s) => (
                    <div key={s.n} className={`ams-slot ${s.type ? '' : 'empty'}`}>
                      <span className="n">{s.n}</span>
                      {s.type ? (
                        <span className="chip" style={{ border: 'none', padding: 0, background: 'none' }}>
                          <span className="sw" style={{ background: s['color-hex'] }} />
                          {s.type}
                          {s['color-name'] ? ` ${s['color-name']}` : ''}
                        </span>
                      ) : (
                        t('misc.empty-slot')
                      )}
                      <span className="meta num">{s.type ? s.label : ''}</span>
                    </div>
                  ))}
                  <button className="btn small" style={{ alignSelf: 'flex-start' }} onClick={() => showToast(t('devices.inventory'))}>
                    <Icon name="materials" />
                    {t('devices.inventory')}
                  </button>
                </div>
              </div>

              <div
                style={{
                  borderTop: '1px solid var(--line)',
                  padding: '10px 16px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                }}
              >
                <button
                  className="btn ghost small"
                  disabled={!printing && !paused}
                  onClick={() => {
                    void (printing ? api.device.pause() : api.device.resume()).catch(() => void 0);
                  }}
                >
                  <Icon name="layers" />
                  {paused ? t('devices.resume') : t('devices.pause')}
                </button>
                <button
                  className="btn danger small"
                  disabled={!printing && !paused}
                  onClick={() =>
                    setConfirm({
                      title: t('devices.stop-confirm-title'),
                      body: t('devices.stop-confirm-body'),
                      onOk: () => void api.device.stop().catch(() => void 0),
                    })
                  }
                >
                  {t('devices.stop')}
                </button>
                <span className="sp" style={{ flex: 1 }} />
                {snap?.connected && !snap.kind.includes('fixture') ? (
                  <button className="btn ghost small" disabled title={t('devices.camera-off')}>
                    <Icon name="camera" />
                    {t('devices.camera')}
                  </button>
                ) : (
                  <span style={{ fontSize: 11, color: 'var(--faint)' }}>{t('devices.camera-off')}</span>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-h">{t('devices.maintenance')}</div>
              <div className="table">
                <div className="trow">
                  <div className="grow">
                    {t('devices.nozzle')} <span className="num">0.4</span>
                    <span className="dim">
                      {' '}
                      · {t('devices.nozzle-hours')} <span className="num">213h</span> ·{' '}
                      {t('devices.nozzle-budget')} <span className="num">1000h</span>
                    </span>
                  </div>
                </div>
                <div className="trow">
                  <div className="grow">
                    {t('devices.pei')}
                    <span className="dim">
                      {' '}
                      · {t('devices.pei-left')} <span className="num">38</span> {t('devices.prints')}
                    </span>
                  </div>
                </div>
                <div className="trow">
                  <div className="grow">
                    {t('devices.desiccant')}
                    <span className="dim">
                      {' '}
                      · <span className="num">2</span> {t('devices.changed-ago')}
                    </span>
                  </div>
                </div>
                <div className="trow">
                  <div className="grow">
                    {t('devices.firmware')}
                    <span className="dim">
                      {' '}
                      · <span className="num">01.07.00.00</span>
                    </span>
                  </div>
                  <StatusPill status="done" />
                </div>
              </div>
            </div>

            <div className="card">
              <div className="card-h">{t('devices.recent-connections')}</div>
              <div className="table">
                {devices.map((d) => (
                  <div className="trow" key={d.id}>
                    <span className={`dot ${snap?.connected && snap['device-id'] === d.id ? 'on' : 'off'}`} />
                    <div className="grow">
                      {d.name}
                      {d.kind === 'fixture' ? (
                        <span className="dim"> · {t('devices.demo-tag')}</span>
                      ) : (
                        <span className="dim num"> · {d.host}</span>
                      )}
                    </div>
                    {snap?.connected && snap['device-id'] === d.id ? (
                      <button className="btn ghost small" onClick={() => void api.device.disconnect().then(load)}>
                        {t('devices.disconnect')}
                      </button>
                    ) : (
                      <button className="btn ghost small" onClick={() => void connect(d.id)}>
                        {t('devices.connect')}
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {adding ? (
        <div className="modal-backdrop" onClick={() => setAdding(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="m-title">{t('devices.add')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="dv-name">{t('materials.name')}</label>
              <input id="dv-name" className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              <label className="label" htmlFor="dv-model">{t('misc.model')}</label>
              <select id="dv-model" className="input" value={form.model} onChange={(e) => setForm({ ...form, model: e.target.value })}>
                <option>X1 Carbon</option>
                <option>X1</option>
                <option>P1S</option>
                <option>P1P</option>
                <option>A1</option>
                <option>A1 mini</option>
              </select>
              <label className="label" htmlFor="dv-host">IP</label>
              <input id="dv-host" className="input" value={form.host} onChange={(e) => setForm({ ...form, host: e.target.value })} placeholder="192.168.1.x" />
              <label className="label" htmlFor="dv-serial">S/N</label>
              <input id="dv-serial" className="input" value={form.serial} onChange={(e) => setForm({ ...form, serial: e.target.value })} />
              <label className="label" htmlFor="dv-code">{t('project.nozzle')} · access code</label>
              <input id="dv-code" className="input" type="password" value={form['access-code']} onChange={(e) => setForm({ ...form, 'access-code': e.target.value })} />
              <label className="label" htmlFor="dv-kind">kind</label>
              <select id="dv-kind" className="input" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}>
                <option value="bambu">Bambu Lab (LAN)</option>
                <option value="fixture">{t('devices.demo-tag')}</option>
              </select>
            </div>
            <div className="settings-note">
              {t('settings.ai-note')}
            </div>
            <div className="m-actions">
              <button className="btn ghost" onClick={() => setAdding(false)}>
                {t('confirm.cancel')}
              </button>
              <button
                className="btn primary"
                disabled={!form.name.trim() || busy}
                onClick={() => {
                  setBusy(true);
                  void api.device
                    .create({ ...form, name: form.name.trim() })
                    .then(() => {
                      setAdding(false);
                      setForm({ ...form, name: '', host: '', serial: '', 'access-code': '' });
                      showToast(t('settings.saved'));
                      load();
                    })
                    .catch((e) => showToast(e instanceof Error ? e.message : t('misc.error')))
                    .finally(() => setBusy(false));
                }}
              >
                {t('confirm.ok')}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <ConfirmModal state={confirm} onClose={() => setConfirm(null)} />
    </>
  );
}
