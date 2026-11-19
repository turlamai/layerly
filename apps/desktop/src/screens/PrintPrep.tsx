// Print package — the ONLY dispatch surface in the whole app (design
// invariant 2). Material mapping, filament check, estimates, dispatch
// options and the explicit confirm button; the advisor's confirm card
// renders as data with explicit actions.

import { useEffect, useMemo, useState } from 'react';
import { api } from '@layerly/core';
import type { DeviceSnapshot, ProjectDetail as Detail, SlicePlan } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, StatusPill, minutesText } from '../components/ui';

export default function PrintPrep() {
  const { viewId, device, go, t, showToast } = useApp();
  const [data, setData] = useState<Detail | null>(null);
  const [planId, setPlanId] = useState<string>('');
  const [dispatching, setDispatching] = useState(false);
  const [optPhoto, setOptPhoto] = useState(true);
  const [optPause, setOptPause] = useState(true);

  useEffect(() => {
    if (!viewId) return;
    void api.projects
      .get(viewId)
      .then((d) => {
        setData(d);
        const rec = d.plans.find((p) => p.recommended) ?? d.plans[0];
        if (rec) setPlanId(rec.id);
      })
      .catch(() => void 0);
  }, [viewId]);

  const plan: SlicePlan | undefined = useMemo(
    () => data?.plans.find((p) => p.id === planId) ?? data?.plans[0],
    [data, planId]
  );

  if (!viewId || !data?.project) {
    return (
      <>
        <div className="topbar">
          <h1>{t('prep.title')}</h1>
        </div>
        <div className="content">
          <Empty icon="cube" title={t('prep.title')} />
        </div>
      </>
    );
  }

  const p = data.project;
  const snapshot: DeviceSnapshot | null = device;
  const busyJob = snapshot?.job ?? null;
  // material naming follows the plan's first part (v1 records estimates;
  // there is no real slicer to derive it)
  const partName = plan?.parts[0]?.name ?? '';
  const materialName = partName.includes('PLA') ? 'PLA 米白' : 'PETG 黑';
  const materialHex = partName.includes('PLA') ? '#d8d3c8' : '#2b2b2e';

  const dispatch = async () => {
    if (!plan) return;
    setDispatching(true);
    try {
      // 1. create the job row (history + queue), 2. dispatch it —
      // the queue route is the single dispatch boundary
      const job = await api.jobs.create({
        'project-id': p.id,
        'version-id': p['current-version-id'],
        'plan-id': plan.id,
        seq: (p['target-qty'] > 1 ? Math.min(p['target-qty'], 4) : 1),
        total: p['target-qty'],
        layers: plan['est-layers'],
        minutes: plan['est-minutes'],
        grams: plan['est-grams'],
        'material-name': materialName,
        'material-hex': materialHex,
      });
      await api.jobs.queue(job.id);
      if (optPhoto || optPause) {
        showToast(t('prep.queued-ok'));
      } else {
        showToast(t('prep.queued-ok'));
      }
      go('devices');
    } catch (e) {
      showToast(e instanceof Error ? e.message : t('misc.error'));
    } finally {
      setDispatching(false);
    }
  };

  return (
    <>
      <div className="topbar">
        <button className="btn ghost small" onClick={() => go('project', p.id)}>
          {t('project.back')}
        </button>
        <h1>{t('prep.title')}</h1>
        <span className="sub num">
          {p.name} · {p['version-label']}
        </span>
        <span className="sp" />
        <span className="pill idea dark-solid big"><i />{t('status.pending-dispatch')}</span>
      </div>
      <div className="content">
        <div className="grid" style={{ gridTemplateColumns: '1fr 360px', alignItems: 'start' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div className="card">
              <div className="card-h">
                {t('prep.mapping')}
                <span className="sp" />
                <span className="sub">{t('prep.mapping-sub')}</span>
              </div>
              <div className="table">
                {(plan?.parts ?? []).map((part, i) => {
                  const slot = snapshot?.ams.find((s) => s.n === part.slot);
                  return (
                    <div className="trow" key={i}>
                      <Icon name="projects" />
                      <div className="grow">
                        {part.name}
                        <span className="dim">{part.note ? ` · ${part.note}` : ''}</span>
                      </div>
                      <span style={{ color: 'var(--faint)' }}>→</span>
                      <div className={`ams-slot bare ${slot?.type ? '' : 'empty'}`}>
                        <span className="n">{part.slot}</span>
                        {slot?.type ? (
                          <span className="chip" style={{ border: 'none', padding: 0, background: 'none' }}>
                            <span className="sw" style={{ background: slot['color-hex'] }} />
                            {slot.type}
                          </span>
                        ) : (
                          t('misc.empty-slot')
                        )}
                        <span className="meta num">{slot?.label ?? part.note ?? ''}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
              <div
                style={{
                  padding: '10px 16px',
                  borderTop: '1px solid var(--line)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                }}
              >
                <StatusPill status="ok" />
                <span style={{ fontSize: 12, color: 'var(--mute)' }}>{t('prep.mono-single')}</span>
              </div>
            </div>

            <div className="card">
              <div className="card-h">{t('prep.check')}</div>
              <div style={{ padding: '12px 16px', display: 'flex', flexDirection: 'column', gap: 9 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                  <span className="dot on" />
                  {t('prep.this-job')} <b className="num">{plan?.['est-grams']} {t('misc.g')}</b>
                  {' · '}
                  {t('prep.slot')} {plan?.parts[0]?.slot ?? 1}{' '}
                  <span className="num">
                    {snapshot?.ams.find((s) => s.n === plan?.parts[0]?.slot)?.label ?? ''}
                  </span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                  <span className="dot busy" />
                  {t('prep.batch-total', {
                    n: p['target-qty'],
                    mat: materialName.split(' ')[0],
                    total: `${Math.round((plan?.['est-grams'] ?? 0) * p['target-qty'])} ${t('misc.g')}`,
                    left: `${Math.max(
                      0,
                      Math.round(
                        (snapshot?.ams.find((s) => s.n === plan?.parts[0]?.slot)?.['remaining-g'] ?? 0) -
                          (plan?.['est-grams'] ?? 0) * p['target-qty']
                      )
                    )} ${t('misc.g')}`,
                  })}
                </div>
              </div>
            </div>

            <div className="grid" style={{ gridTemplateColumns: 'repeat(4,1fr)' }}>
              <div className="card metric">
                <span className="k">{t('prep.estimates')}</span>
                <span className="v">
                  {Math.floor((plan?.['est-minutes'] ?? 0) / 60)}
                  <small>{t('misc.hour')}</small>{' '}
                  {(plan?.['est-minutes'] ?? 0) % 60}
                  <small>{t('misc.min')}</small>
                </span>
              </div>
              <div className="card metric">
                <span className="k">{t('prep.usage')}</span>
                <span className="v">
                  {plan?.['est-grams'] ?? 0}
                  <small> {t('misc.g')}</small>
                </span>
              </div>
              <div className="card metric">
                <span className="k">{t('prep.total-layers')}</span>
                <span className="v">{plan?.['est-layers'] ?? 0}</span>
              </div>
              <div className="card metric">
                <span className="k">{t('prep.layer-height')}</span>
                <span className="v">
                  {plan?.['layer-height'] ?? 0.2}
                  <small> mm</small>
                </span>
              </div>
            </div>

            <div className="card pad">
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span className="badge">{plan?.label ?? '—'}</span>
                <span style={{ fontSize: 13, fontWeight: 600 }}>{plan?.strategy}</span>
                <span className="sp" style={{ flex: 1 }} />
                {data.plans.length > 1 ? (
                  <select
                    className="input"
                    value={planId}
                    onChange={(e) => setPlanId(e.target.value)}
                    aria-label={t('prep.plan')}
                  >
                    {data.plans.map((pl) => (
                      <option key={pl.id} value={pl.id}>
                        {pl.label} · {pl.strategy} · {minutesText(pl['est-minutes'])}
                      </option>
                    ))}
                  </select>
                ) : null}
              </div>
              <div style={{ display: 'flex', gap: 16, marginTop: 10, flexWrap: 'wrap' }}>
                <span className="kv">
                  {t('prep.walls')} <b>{plan?.walls}</b>
                </span>
                <span className="kv">
                  {t('prep.infill')} <b>{plan?.infill}</b>
                </span>
                <span className="kv">
                  {t('prep.supports')} <b>{plan?.supports}</b>
                </span>
                <span className="kv">
                  {t('prep.bed')} <b>{plan?.['bed-temp']}°C</b>
                </span>
                <span className="kv">
                  {t('prep.nozzle')} <b>{plan?.['nozzle-temp']}°C</b>
                </span>
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div className="card">
              <div className="card-h">
                {t('prep.dispatch')}
                <span className="sp" />
                <span className="badge">{snapshot?.connected ? snapshot.name : '—'}</span>
              </div>
              <div style={{ padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                  <span className={`dot ${busyJob ? 'busy' : 'on'}`} />
                  {busyJob
                    ? `${t('prep.current-job')}：${busyJob.name} · ${t('dash.remaining')} ${Math.max(
                        0,
                        Math.round(busyJob['minutes-left'])
                      )} ${t('dash.minutes')}`
                    : t('foot.idle')}
                </div>
                <div style={{ fontSize: 12.5, lineHeight: 1.6, color: 'var(--mute)' }}>
                  {t('prep.dispatch-note')}
                </div>
                <div
                  style={{
                    border: '1px dashed var(--line)',
                    borderRadius: 'var(--radius-ctl)',
                    padding: '10px 12px',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 6,
                  }}
                >
                  <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.3px', color: 'var(--mute)' }}>
                    {t('prep.options')}
                  </span>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                    <input type="checkbox" checked={optPhoto} onChange={(e) => setOptPhoto(e.target.checked)} />
                    {t('prep.opt-photo')}
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                    <input type="checkbox" checked={optPause} onChange={(e) => setOptPause(e.target.checked)} />
                    {t('prep.opt-pause')}
                  </label>
                </div>
                <button
                  className="btn primary wide"
                  disabled={dispatching || !snapshot?.connected}
                  onClick={() => void dispatch()}
                >
                  <Icon name="layers" />
                  {t('prep.confirm-dispatch')}
                  {p['target-qty'] > 1 ? ` ${t('prep.piece-n', { n: 1 })}` : ''}
                </button>
                <span style={{ fontSize: 11, color: 'var(--faint)', textAlign: 'center' }}>
                  {t('prep.only-here')}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
