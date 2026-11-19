// Projects — the card wall with lifecycle filters and search, plus the
// new-project modal. Idea cards render the brief-only empty state; no
// print dispatch lives here (dispatch is print-prep's job only).

import { useEffect, useState } from 'react';
import { api } from '@layerly/core';
import type { LifecycleStatus, ProjectSummary } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, Layerbar, StatusPill } from '../components/ui';

const filters: (LifecycleStatus | 'all')[] = [
  'all',
  'printing',
  'slicing',
  'done',
  'failed',
  'idea',
];

function Cover({ seed }: { seed: number }) {
  const rows = [0, 1, 2].map((i) => {
    const y = 34 + i * 20;
    return `M-10 ${y + (seed % 3) * 4} Q60 ${y - 16} 110 ${y - 2} T210 ${y - 6}`;
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

export default function Projects() {
  const { go, t, showToast } = useApp();
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [filter, setFilter] = useState<LifecycleStatus | 'all'>('all');
  const [query, setQuery] = useState('');
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const [brief, setBrief] = useState('');

  useEffect(() => {
    void api.projects
      .list()
      .then((r) => setProjects(r.projects))
      .catch(() => void 0);
  }, []);

  const countFor = (f: LifecycleStatus | 'all') =>
    f === 'all' ? projects.length : projects.filter((p) => p.status === f).length;
  const visible = projects.filter(
    (p) =>
      (filter === 'all' || p.status === filter) &&
      (!query || p.name.toLowerCase().includes(query.toLowerCase()))
  );

  return (
    <>
      <div className="topbar">
        <h1>{t('projects.title')}</h1>
        <span className="sub">
          <span className="num">{projects.length}</span> {t('projects.count')} ·{' '}
          <span className="num">
            {projects.filter((p) => p.job || p.status === 'printing').length}
          </span>{' '}
          {t('projects.in-progress')}
        </span>
        <span className="sp" />
        <div className="search">
          <Icon name="search" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('projects.search')}
            aria-label={t('projects.search')}
          />
        </div>
        <button className="btn primary" onClick={() => setCreating(true)}>
          <Icon name="plus" />
          {t('dash.new-project')}
        </button>
      </div>
      <div className="content">
        <div className="filter-row">
          {filters.map((f) => (
            <button
              key={f}
              className={`pill ${f === 'all' ? 'dark-solid' : f} ${filter === f ? 'active' : ''}`}
              style={filter === f ? { outline: '2px solid var(--accent)' } : undefined}
              onClick={() => setFilter(f)}
            >
              <i />
              {t(f === 'all' ? 'status.all' : `status.${f}`)} <span className="num">{countFor(f)}</span>
            </button>
          ))}
        </div>
        {projects.length === 0 ? (
          <div className="card">
            <Empty
              icon="projects"
              title={t('projects.title')}
              sub={t('settings.data-note')}
              action={
                <button className="btn primary" onClick={() => setCreating(true)}>
                  {t('dash.new-project')}
                </button>
              }
            />
          </div>
        ) : (
          <div className="grid" style={{ gridTemplateColumns: 'repeat(3,1fr)' }}>
            {visible.map((p) => (
              <div key={p.id} className="card project-card" onClick={() => go('project', p.id)}>
                <Cover seed={p.name.length} />
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
                      <Layerbar percent={p.job.layers ? (p.job.layer / p.job.layers) * 100 : 0} />
                      <div className="pc-meta">
                        <span className="num">
                          L{p.job.layer} / {p.job.layers}
                        </span>
                      </div>
                    </>
                  ) : p.status === 'failed' ? (
                    <div className="pc-meta">
                      <span>{t('projects.lesson-archived')}</span>
                    </div>
                  ) : p.status === 'idea' ? (
                    <div className="pc-meta">
                      <span>{t('projects.only-brief')}</span>
                    </div>
                  ) : (
                    <div className="pc-meta">
                      <span className="num">{shortDate2(p['updated-at'])}</span>
                    </div>
                  )}
                </div>
              </div>
            ))}
            {visible.length === 0 ? <Empty icon="search" title={t('projects.search')} /> : null}
          </div>
        )}
      </div>

      {creating ? (
        <div className="modal-backdrop" onClick={() => setCreating(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="m-title">{t('dash.new-project')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="np-name">
                {t('materials.name')}
              </label>
              <input id="np-name" className="input" value={name} onChange={(e) => setName(e.target.value)} />
              <label className="label" htmlFor="np-brief">
                {t('project.brief')}
              </label>
              <textarea id="np-brief" className="input" value={brief} onChange={(e) => setBrief(e.target.value)} />
            </div>
            <div className="m-actions">
              <button className="btn ghost" onClick={() => setCreating(false)}>
                {t('confirm.cancel')}
              </button>
              <button
                className="btn primary"
                disabled={!name.trim()}
                onClick={() => {
                  void api.projects
                    .create(name.trim(), brief)
                    .then((p) => {
                      setCreating(false);
                      showToast(t('settings.saved'));
                      go('project', p.id);
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

function shortDate2(iso: string): string {
  if (!iso) return '';
  const [, m, d] = iso.split('-');
  return `${m}-${Number(d)}`;
}
