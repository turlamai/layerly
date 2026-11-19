// History — print records with lessons called out under failed rows, the
// metrics row and the feedback (photo) archive. CSV export walks the
// loaded rows.

import { Fragment, useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { PrintJob } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, StatusPill, minutesText, shortDate } from '../components/ui';

export default function History() {
  const { t, showToast } = useApp();
  const [jobs, setJobs] = useState<PrintJob[]>([]);

  useEffect(() => {
    void api.jobs
      .list(200)
      .then((r) => setJobs(r.jobs))
      .catch(() => void 0);
  }, []);

  const done = jobs.filter((j) => j.status === 'done').length;
  const failed = jobs.filter((j) => j.status === 'failed').length;
  const totalMinutes = jobs
    .filter((j) => j.status === 'done')
    .reduce((acc, j) => acc + j.minutes, 0);

  const exportCsv = () => {
    const rows = [
      ['date', 'status', 'material', 'pieces', 'minutes', 'grams', 'lesson'],
      ...jobs.map((j) => [
        j['queued-at'],
        j.status,
        j['material-name'],
        `${j.seq}/${j.total}`,
        String(j.minutes),
        String(j.grams),
        j.lesson.replace(/"/g, '""'),
      ]),
    ];
    const csv = '\uFEFF' + rows.map((r) => r.map((c) => `"${c}"`).join(',')).join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'layerly-history.csv';
    a.click();
    URL.revokeObjectURL(url);
    showToast(t('history.export'));
  };

  return (
    <>
      <div className="topbar">
        <h1>{t('history.title')}</h1>
        <span className="sub">
          <span className="num">{jobs.length}</span> {t('history.records')}{' '}
          <span className="num">30</span> {t('history.days')}
        </span>
        <span className="sp" />
        <button className="btn small" onClick={exportCsv}>
          <Icon name="history" />
          {t('history.export')}
        </button>
      </div>
      <div className="content">
        <div className="grid" style={{ gridTemplateColumns: 'repeat(3,1fr)', marginBottom: 14 }}>
          <div className="card metric">
            <span className="k">{t('history.done-count')}</span>
            <span className="v">
              {done}
              <small> {t('dash.piece')}</small>
            </span>
          </div>
          <div className="card metric">
            <span className="k">{t('history.failed-count')}</span>
            <span className="v">
              {failed}
              <small> {t('dash.piece')}</small>
            </span>
          </div>
          <div className="card metric">
            <span className="k">{t('history.total-time')}</span>
            <span className="v">
              {minutesText(totalMinutes).replace(' ', '')}
            </span>
          </div>
        </div>

        <div className="card">
          <div className="card-h">
            {t('history.records-card')}
            <span className="sp" />
            <span className="badge num">{jobs.length}</span>
          </div>
          <div className="table">
            {jobs.map((j) => (
              <Fragment key={j.id}>
                <div className="trow">
                  <StatusPill status={j.status === 'queued' ? 'printing' : j.status} />
                  <div className="grow">
                    {t('history.piece-n', { n: `${j.seq}/${j.total}` })}
                    <span className="dim">
                      {j.status === 'failed' && j.lesson ? ` · ${j.lesson}` : ''}
                      {j.status === 'cancelled' ? ` · ${t('status.cancelled')}` : ''}
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
                  <span className="dim num">{shortDate(j['queued-at'])}</span>
                </div>
                {j.status === 'failed' && j.lesson ? (
                  <div className="lesson-note" key={`${j.id}-lesson`}>
                    <span className="l-tag">▸ {t('history.lesson')}</span>
                    <span>{j.lesson}</span>
                  </div>
                ) : null}
              </Fragment>
            ))}
            {jobs.length === 0 ? <Empty icon="history" title={t('history.title')} /> : null}
          </div>
        </div>

        <div className="card pad" style={{ marginTop: 14 }}>
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 12 }}>{t('history.archive')}</div>
          <div style={{ display: 'flex', gap: 16 }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div className="photo-slot">
                <Icon name="camera" size={36} />
              </div>
              <div style={{ fontSize: 12, color: 'var(--mute)' }}>{t('history.demo-note')}</div>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
