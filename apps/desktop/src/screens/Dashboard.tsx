// Dashboard — workbench overview: in-progress projects with live layer
// bars, recent prints, the device card and the advisor peek, matching the
// prototype's dashboard.html layout.

import { useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { ProjectSummary, PrintJob, ConfirmCard } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, Layerbar, StatusPill, minutesText, shortDate } from '../components/ui';

function ProjectCover({ seed }: { seed: number }) {
  // decorative layer waves behind a model outline — pure SVG, no assets
  const rows = [0, 1, 2].map((i) => {
    const y = 34 + i * 20;
    return `M-10 ${y + (seed % 3) * 3} Q60 ${y - 16} 110 ${y - 2} T210 ${y - 6}`;
  });
  return (
    <div className="cover">
      <svg className="layers-bg" viewBox="0 0 200 110" preserveAspectRatio="none">
        <g stroke="currentColor" strokeWidth="1" fill="none" opacity=".35">
          {rows.map((d) => (
            <path key={d} d={d} />
          ))}
        </g>
      </svg>
      <svg className="model" viewBox="0 0 48 48" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M24 6 40 15v18L24 42 8 33V15L24 6Z" />
        <path d="M8 15l16 9 16-9M24 24v18" />
      </svg>
    </div>
  );
}

export default function Dashboard() {
  const { device, counts, go, t, showToast } = useApp();
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [recent, setRecent] = useState<PrintJob[]>([]);
  const [pending, setPending] = useState<ConfirmCard | null>(null);

  useEffect(() => {
    void api.projects
      .list()
      .then((r) => setProjects(r.projects))
      .catch(() => void 0);
    void api.jobs
      .list(3)
      .then((r) => setRecent(r.jobs))
      .catch(() => void 0);
    // the advisor's pending confirm card (demo seed) — advisory only
    void api.advisor
      .conversations()
      .then(async (r) => {
        const conv = r.conversations[0];
        if (!conv) return;
        const msgs = await api.advisor.messages(conv.id);
        const withCard = msgs.messages.find((m) => m.confirm);
        if (withCard?.confirm) setPending(withCard.confirm);
      })
      .catch(() => void 0);
  }, []);

  const inProgress = projects.filter((p) =>
    ['printing', 'slicing', 'heating'].includes(p.status) || p.job
  );
  const today = new Date();
  const dateLabel = `${today.getMonth() + 1} 月 ${today.getDate()} 日`;
  const liveJob = device?.job ?? null;

  return (
    <>
      <div className="topbar">
        <h1>{t('dash.title')}</h1>
        <span className="sub">
          {dateLabel} · {inProgress.length} {t('dash.day-in-progress')}
        </span>
        <span className="sp" />
        <div className="search">
          <Icon name="search" />
          <input placeholder={t('dash.search')} aria-label={t('dash.search')} />
        </div>
        <button className="btn primary" onClick={() => go('projects')}>
          <Icon name="plus" />
          {t('dash.new-project')}
        </button>
      </div>
      <div className="content">
        {counts && counts.projects === 0 && !device?.connected ? (
          <Empty
            icon="overview"
            title={t('dash.title')}
            sub={t('settings.data-note')}
            action={
              <button
                className="btn primary"
                onClick={() => void api.demo.seed().then(() => showToast(t('settings.seeded')))}
              >
                {t('settings.seed-demo')}
              </button>
            }
          />
        ) : (
          <div className="grid" style={{ gridTemplateColumns: '1fr 320px', alignItems: 'start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div className="card-h no-line" style={{ padding: '2px 2px 0' }}>
                {t('dash.in-progress')}
                <span className="sp" />
                <button className="btn ghost small" onClick={() => go('projects')}>
                  {t('dash.all-projects')}
                </button>
              </div>
              {inProgress.length === 0 ? (
                <div className="card">
                  <Empty icon="projects" title={t('dash.in-progress')} sub={t('projects.only-brief')} />
                </div>
              ) : (
                <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
                  {inProgress.slice(0, 2).map((p) => (
                    <div
                      key={p.id}
                      className="card project-card"
                      onClick={() => go('project', p.id)}
                    >
                      <ProjectCover seed={p.id.length} />
                      <div className="pc-body">
                        <div className="pc-head">
                          <span className="pc-title">
                            {p.name}
                            {p['version-label'] ? ` · ${p['version-label']}` : ''}
                          </span>
                          <span className="sp" style={{ flex: 1 }} />
                          <StatusPill status={p.job ? p.job.status : p.status} />
                        </div>
                        {p.job && p.job.status === 'printing' ? (
                          <>
                            <div className="pc-meta">
                              <span className="num">
                                {t('history.piece-n', { n: `${p.job.seq}/${p.job.total}` })}
                              </span>{' '}
                              · <span>{p.job['material-name']}</span>
                            </div>
                            <Layerbar percent={p.job.layers ? (p.job.layer / p.job.layers) * 100 : 0} />
                            <div className="pc-meta">
                              <span className="num">
                                L{p.job.layer} / {p.job.layers}
                              </span>
                              <span className="sp" style={{ flex: 1 }} />
                              <span className="num">
                                {t('dash.remaining')} {Math.max(0, Math.round(device?.job?.['minutes-left'] ?? 0))}{' '}
                                {t('dash.minutes')}
                              </span>
                            </div>
                          </>
                        ) : (
                          <div className="pc-meta">
                            <span>
                              {p['version-label'] ? `${p['version-label']} · ` : ''}
                              {t(p.status === 'slicing' ? 'status.slicing' : 'status.design')}
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}

              <div className="card-h no-line" style={{ padding: '8px 2px 0' }}>
                {t('dash.recent-prints')}
                <span className="sp" />
                <button className="btn ghost small" onClick={() => go('history')}>
                  {t('dash.history-link')}
                </button>
              </div>
              <div className="card table">
                {recent.map((j) => (
                  <div className="trow" key={j.id}>
                    <StatusPill status={j.status === 'queued' ? 'printing' : j.status} />
                    <div className="grow">
                      {j['project-id'] ? '' : ''}
                      {j['device-name'] ? '' : ''}
                      <span>{j['material-name']}</span>{' '}
                      <span className="dim">
                        · {t('history.piece-n', { n: `${j.seq}/${j.total}` })}
                      </span>
                    </div>
                    <span className="chip">
                      <span className="sw" style={{ background: j['material-hex'] }} />
                      {j['material-name']}
                    </span>
                    <span className="dim num">
                      {minutesText(j.minutes)} · {Math.round(j.grams)}
                      {t('misc.g')}
                    </span>
                    <span className="dim">{shortDate(j['queued-at'])}</span>
                  </div>
                ))}
                {recent.length === 0 ? <Empty icon="history" title={t('dash.recent-prints')} /> : null}
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div className="card">
                <div className="card-h">
                  {t('dash.device-card')}
                  <span className="sp" />
                  <span className="badge">{device?.connected ? device.name : '—'}</span>
                </div>
                <div style={{ padding: '12px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {device?.connected ? (
                    <>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span className={`dot ${device.state === 'printing' ? 'busy' : 'on'}`} />
                        <span style={{ fontSize: 13, fontWeight: 600 }}>
                          {device.job ? t('foot.printing') : t(device.state === 'paused' ? 'status.paused' : 'foot.idle')}
                        </span>
                        <span className="sp" style={{ flex: 1 }} />
                        <span className="num" style={{ fontSize: 12, color: 'var(--mute)' }}>
                          {liveJob ? `${Math.round(liveJob.percent)}%` : ''}
                        </span>
                      </div>
                      <Layerbar percent={liveJob?.percent ?? 0} />
                      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                        {device.ams.slice(0, 4).map((s) => (
                          <div
                            key={s.n}
                            className={`ams-slot ${s.type ? '' : 'empty'}`}
                          >
                            <span className="n">{s.n}</span>
                            {s.type ? (
                              <span className="chip" style={{ border: 'none', padding: 0, background: 'none' }}>
                                <span className="sw" style={{ background: s['color-hex'] }} />
                                {s.type}
                              </span>
                            ) : (
                              t('misc.empty-slot')
                            )}
                            <span className="meta num">{s.type ? s.label : ''}</span>
                          </div>
                        ))}
                      </div>
                      <button className="btn small" style={{ alignSelf: 'flex-start' }} onClick={() => go('devices')}>
                        {t('dash.device-detail')}
                      </button>
                    </>
                  ) : (
                    <Empty
                      icon="devices"
                      title={t('misc.device-none')}
                      action={
                        <button className="btn small" onClick={() => go('devices')}>
                          {t('devices.add')}
                        </button>
                      }
                    />
                  )}
                </div>
              </div>

              <div className="card">
                <div className="card-h">
                  {t('dash.advisor-card')}
                  <span className="sp" />
                  <span className="badge">Sarah</span>
                </div>
                <div style={{ padding: '12px 16px' }}>
                  {pending ? (
                    <div className="chat">
                      <div className="confirm-card">
                        <div className="cc-title">
                          <Icon name="shield" />
                          {pending.label || t('dash.confirm-needed')}
                        </div>
                        <div className="cc-body">{pending.body}</div>
                        <div className="cc-impact">{pending.impact}</div>
                        <div className="cc-actions">
                          <button
                            className="btn primary small"
                            onClick={() => {
                              void api.shopping
                                .create('PETG 黑 · 1 卷', 1, 89, 'ai')
                                .then(() => {
                                  setPending(null);
                                  showToast(t('prep.queued-ok'));
                                })
                                .catch(() => void 0);
                            }}
                          >
                            {t('dash.add-to-list')}
                          </button>
                          <button className="btn ghost small" onClick={() => setPending(null)}>
                            {t('dash.ignore')}
                          </button>
                        </div>
                      </div>
                    </div>
                  ) : (
                    <div style={{ fontSize: 12.5, color: 'var(--mute)' }}>{t('dash.ask')}</div>
                  )}
                  <hr className="divider" />
                  <div className="composer" style={{ padding: '8px 10px' }}>
                    <div style={{ fontSize: 12.5, color: 'var(--mute)' }}>{t('dash.ask')}</div>
                    <div className="row">
                      <span className="hint">{t('dash.enter-hint')}</span>
                      <span className="sp" style={{ flex: 1 }} />
                      <button className="btn primary small" onClick={() => go('advisor')}>
                        {t('dash.open-advisor')}
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              {counts ? (
                <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
                  <div className="card metric">
                    <span className="k">{t('dash.archived-projects')}</span>
                    <span className="v">
                      {counts.done}
                      <small> {t('dash.piece')}</small>
                    </span>
                  </div>
                  <div className="card metric">
                    <span className="k">{t('dash.stock')}</span>
                    <span className="v">
                      {(counts['stock-g'] / 1000).toFixed(1)}
                      <small> {t('misc.kg')}</small>
                    </span>
                  </div>
                </div>
              ) : null}
            </div>
          </div>
        )}
      </div>
    </>
  );
}
