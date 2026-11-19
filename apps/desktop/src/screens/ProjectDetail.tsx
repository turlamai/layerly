// Project detail — the full lifecycle IA core: brief, version timeline,
// slice plans, print records and the task-team chat (project-scoped
// advisor). The v2 AI modeling chain stays a disabled placeholder per the
// design contract. 准备打印 routes to print-prep — the only dispatch path.

import { useCallback, useEffect, useState } from 'react';
import { advisorChat, api } from '@layerly/core';
import type { ProjectDetail as Detail, Version } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, StatusPill, minutesText, shortDate } from '../components/ui';

export default function ProjectDetail() {
  const { viewId, go, t, showToast } = useApp();
  const [data, setData] = useState<Detail | null>(null);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState('');
  const [brief, setBrief] = useState('');
  const [addingVersion, setAddingVersion] = useState(false);
  const [vLabel, setVLabel] = useState('');
  const [vNote, setVNote] = useState('');
  const [vFile, setVFile] = useState<File | null>(null);

  const load = useCallback(() => {
    if (!viewId) return;
    void api.projects
      .get(viewId)
      .then((d) => {
        setData(d);
        if (d.project) {
          setName(d.project.name);
          setBrief(d.project.brief);
        }
      })
      .catch(() => void 0);
  }, [viewId]);

  useEffect(() => {
    load();
  }, [load]);

  if (!viewId) {
    return (
      <>
        <div className="topbar">
          <h1>{t('projects.title')}</h1>
        </div>
        <div className="content">
          <Empty icon="projects" title={t('projects.title')} />
        </div>
      </>
    );
  }

  const p = data?.project;
  const versions = data?.versions ?? [];
  const plans = data?.plans ?? [];
  const jobs = data?.jobs ?? [];

  return (
    <>
      <div className="topbar">
        <button className="btn ghost small" onClick={() => go('projects')}>
          {t('project.back')}
        </button>
        <h1>{p?.name ?? '…'}</h1>
        {p ? <StatusPill status={p.job ? p.job.status : p.status} /> : null}
        <span className="sub num">
          {p ? `${p.id.slice(0, 8).toUpperCase()}${p['version-label'] ? ` · ${p['version-label']}` : ''}` : ''}
        </span>
        <span className="sp" />
        <button className="btn small" onClick={() => go('model-viewer', viewId)}>
          {t('project.viewer')}
        </button>
        <button
          className="btn primary"
          disabled={!p || plans.length === 0}
          title={plans.length === 0 ? t('project.no-model-body') : undefined}
          onClick={() => go('print-prep', viewId)}
        >
          {t('project.prep')}
        </button>
      </div>
      <div className="content">
        {!p ? (
          <Empty icon="projects" title={t('projects.title')} />
        ) : (
          <div className="grid" style={{ gridTemplateColumns: '1fr 340px', alignItems: 'start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div className="card pad">
                <div className="card-h no-line" style={{ padding: '0 0 10px' }}>
                  {t('project.brief')}
                  <span className="sp" />
                  <button className="btn ghost small" onClick={() => setEditing(true)}>
                    {t('project.edit')}
                  </button>
                </div>
                <div style={{ fontSize: 13, lineHeight: 1.6 }}>{p.brief || '—'}</div>
                <div style={{ display: 'flex', gap: 16, marginTop: 10, flexWrap: 'wrap' }}>
                  <span className="kv">
                    {t('project.size')} <b>{p['size-text'] || '—'}</b>
                  </span>
                  <span className="kv">
                    {t('project.target')} <b>{p['target-qty']}</b>
                  </span>
                  <span className="kv">
                    {t('project.created')} <b>{shortDate(p['created-at'])}</b>
                  </span>
                </div>
              </div>

              <div className="card">
                <div className="card-h">
                  {t('project.design')}
                  <span className="sp" />
                  <span className="badge v2">{t('project.v2-badge')}</span>
                  <span className="sp" />
                  <button className="btn ghost small" onClick={() => go('model-viewer', viewId)}>
                    {t('project.viewer')} →
                  </button>
                </div>
                <div style={{ padding: '14px 16px' }}>
                  <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 10 }}>
                    <button className="btn ghost small" onClick={() => setAddingVersion(true)}>
                      <Icon name="plus" />
                      {t('project.add-version')}
                    </button>
                  </div>
                  <div className="timeline">
                    {versions.map((v: Version, i) => {
                      const isCurrent = v.id === p['current-version-id'];
                      const isFirst = i === versions.length - 1;
                      return (
                        <div
                          key={v.id}
                          className={`tl-item ${isCurrent ? 'good' : ''} ${isFirst ? 'current' : ''}`}
                        >
                          <div className="node" />
                          <div className="tl-body">
                            <div className="tl-title">
                              {v.label}
                              {isCurrent ? ` · ${t('project.current-version')}` : ''}
                              {isFirst ? ` · ${t('project.origin')}` : ''}
                            </div>
                            <div className="tl-sub">
                              {v.note} · <span className="num">{shortDate(v['created-at'])}</span>
                              {v['material-name'] ? (
                                <>
                                  {' '}
                                  · <span className="chip">{v['material-name']}</span>
                                </>
                              ) : null}
                            </div>
                          </div>
                        </div>
                      );
                    })}
                    {versions.length === 0 ? (
                      <Empty icon="cube" title={t('project.no-model-title')} sub={t('project.no-model-body')} />
                    ) : null}
                  </div>
                  <hr className="divider" />
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '2px 4px' }}>
                    <span className="badge v2">V2</span>
                    <span style={{ fontSize: 12.5, color: 'var(--mute)' }}>{t('project.v2-note')}</span>
                  </div>
                </div>
              </div>

              <div className="card">
                <div className="card-h">
                  {t('project.plans')}
                  <span className="sp" />
                </div>
                <div className="table">
                  {plans.map((plan) => (
                    <div className="trow" key={plan.id}>
                      <span className="badge">{plan.label.replace('方案 ', '')}</span>
                      <div className="grow">
                        {plan.strategy}
                        <span className="dim"> · {plan.walls} 壁 {plan.infill}</span>
                      </div>
                      <span className="dim num">{minutesText(plan['est-minutes'])}</span>
                      <span className="dim num">
                        {plan['est-grams']} {t('misc.g')}
                      </span>
                      {plan.recommended ? <span className="badge accent">★</span> : null}
                      <button
                        className="btn small"
                        onClick={() => go('print-prep', viewId)}
                      >
                        {t('project.export-package')}
                      </button>
                    </div>
                  ))}
                  {plans.length === 0 ? (
                    <Empty icon="layers" title={t('project.plans')} sub={t('project.v2-note')} />
                  ) : null}
                </div>
              </div>

              <div className="card">
                <div className="card-h">
                  {t('project.print-records')}
                  <span className="sp" />
                  <button className="btn ghost small" onClick={() => go('history')}>
                    {t('project.history-link')}
                  </button>
                </div>
                <div className="table">
                  {jobs.slice(0, 5).map((j) => (
                    <div className="trow" key={j.id}>
                      <StatusPill status={j.status === 'queued' ? 'printing' : j.status} />
                      <div className="grow">
                        {j['version-id'] ? '' : ''}
                        {t('history.piece-n', { n: `${j.seq}/${j.total}` })}
                        <span className="dim">
                          {j.status === 'printing'
                            ? ` · ${t('project.in-use')} ${plans.find((pl) => pl.id === j['plan-id'])?.label ?? ''}`
                            : j.status === 'done'
                              ? ` · ${t('project.photo-archived')}`
                              : j.status === 'failed'
                                ? ` · ${j.lesson || t('projects.lesson-archived')}`
                                : ''}
                        </span>
                      </div>
                      <span className="chip">
                        <span className="sw" style={{ background: j['material-hex'] }} />
                        {j['material-name']}
                      </span>
                      <span className="dim num">
                        {j.status === 'printing' ? `L${j.layer}/${j.layers}` : `${minutesText(j.minutes)} · ${Math.round(j.grams)}g`}
                      </span>
                    </div>
                  ))}
                  {jobs.length === 0 ? <Empty icon="history" title={t('project.print-records')} /> : null}
                </div>
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div className="card" style={{ display: 'flex', flexDirection: 'column' }}>
                <div className="card-h">
                  {t('project.task-team')}
                  <span className="sp" />
                  <span className="badge">{p.name}</span>
                </div>
                <div style={{ padding: '12px 14px' }}>
                  <ProjectTeamChat projectId={viewId} projectName={p.name} />
                </div>
              </div>

              <div className="card pad">
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--mute)', marginBottom: 8 }}>
                  {t('project.related')}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                    <span className="dot on" />
                    {t('project.filament')}：
                    <span className="num" style={{ marginLeft: 'auto', color: 'var(--mute)' }}>
                      {t('project.remain-g')} {Math.round(currentPlanGrams(plans))} {t('misc.g')}
                    </span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                    <span className="dot on" />
                    {t('project.nozzle')}：0.4 · {t('prep.mono-single').split('· ')[2] ?? 'PEI'}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5 }}>
                    <span className="dot off" />
                    {t('project.shopping-list')}
                    <span className="num" style={{ marginLeft: 'auto', color: 'var(--mute)' }}>
                      {t('project.pending-confirm')}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {addingVersion && p ? (
        <div className="modal-backdrop" onClick={() => setAddingVersion(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="m-title">{t('project.add-version')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="av-label">{t('project.version-label')}</label>
              <input id="av-label" className="input" value={vLabel} placeholder={nextVersionLabel(versions)} onChange={(e) => setVLabel(e.target.value)} />
              <label className="label" htmlFor="av-note">{t('project.change-note')}</label>
              <textarea id="av-note" className="input" value={vNote} onChange={(e) => setVNote(e.target.value)} />
              <label className="label" htmlFor="av-file">{t('misc.model')}</label>
              <input
                id="av-file"
                type="file"
                accept=".stl,.3mf,.gcode,.gcode.3mf"
                onChange={(e) => setVFile(e.target.files?.[0] ?? null)}
              />
            </div>
            <div className="settings-note">{t('project.import-note')}</div>
            <div className="m-actions">
              <button className="btn ghost" onClick={() => setAddingVersion(false)}>
                {t('confirm.cancel')}
              </button>
              <button
                className="btn primary"
                disabled={!vLabel.trim()}
                onClick={() => {
                  const label = vLabel.trim();
                  const doCreate = (modelFile: string) =>
                    api.versions
                      .create(viewId, label, vNote, modelFile)
                      .then(() => {
                        setAddingVersion(false);
                        setVLabel('');
                        setVNote('');
                        setVFile(null);
                        load();
                        showToast(t('settings.saved'));
                      })
                      .catch(() => showToast(t('misc.error')));
                  if (vFile) {
                    const reader = new FileReader();
                    reader.onload = () => {
                      const b64 = String(reader.result).split(',')[1] ?? '';
                      void api.files
                        .saveModel(viewId, vFile.name, b64)
                        .then((res) => doCreate(res.path))
                        .catch(() => showToast(t('misc.error')));
                    };
                    reader.readAsDataURL(vFile);
                  } else {
                    void doCreate('');
                  }
                }}
              >
                {t('confirm.ok')}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {editing && p ? (
        <div className="modal-backdrop" onClick={() => setEditing(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="m-title">{t('project.edit')}</div>
            <div className="form-grid">
              <label className="label" htmlFor="pe-name">
                {t('materials.name')}
              </label>
              <input id="pe-name" className="input" value={name} onChange={(e) => setName(e.target.value)} />
              <label className="label" htmlFor="pe-brief">
                {t('project.brief')}
              </label>
              <textarea id="pe-brief" className="input" value={brief} onChange={(e) => setBrief(e.target.value)} />
            </div>
            <div className="m-actions">
              <button className="btn ghost" onClick={() => setEditing(false)}>
                {t('confirm.cancel')}
              </button>
              <button
                className="btn primary"
                onClick={() => {
                  void api.projects
                    .update(viewId, { name, brief })
                    .then(() => {
                      setEditing(false);
                      load();
                      showToast(t('settings.saved'));
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

function nextVersionLabel(versions: { label: string }[]): string {
  let max = 0;
  for (const v of versions) {
    const m = /^V(\d+)$/.exec(v.label);
    if (m) max = Math.max(max, Number(m[1]));
  }
  return `V${max + 1}`;
}

function currentPlanGrams(plans: { recommended: boolean; 'est-grams': number }[]): number {
  const rec = plans.find((p) => p.recommended) ?? plans[0];
  return rec ? rec['est-grams'] : 0;
}

// Project-scoped task team chat: same advisor pipeline, project scope.
function ProjectTeamChat({ projectId, projectName }: { projectId: string; projectName: string }) {
  const { t, showToast } = useApp();
  const [convId, setConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<{ id: string; role: string; content: string; confirm: { label: string; body: string; impact: string } | null }[]>([]);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState(false);

  useEffect(() => {
    void api.advisor
      .conversations(projectId)
      .then(async (r) => {
        let conv = r.conversations[0];
        if (!conv) {
          conv = await api.advisor.conversationsCreate('team', projectId, projectName);
        }
        setConvId(conv.id);
        const m = await api.advisor.messages(conv.id);
        setMessages(m.messages);
      })
      .catch(() => void 0);
  }, [projectId, projectName]);

  const send = () => {
    if (!convId || !draft.trim() || streaming) return;
    const text = draft.trim();
    setDraft('');
    setMessages((m) => [...m, { id: `tmp-${Date.now()}`, role: 'user', content: text, confirm: null }]);
    setStreaming(true);
    void advisorChat(
      convId,
      text,
      [`project:${projectId}`],
      (ev) => {
        if (ev.type === 'done') {
          setMessages((m) => [...m, ev.message]);
          setStreaming(false);
        } else if (ev.type === 'error') {
          setStreaming(false);
          showToast(ev.message);
        }
      }
    );
  };

  return (
    <>
      <div className="chat" style={{ maxHeight: 300, overflowY: 'auto' }}>
        {messages.map((m) => (
          <div key={m.id} className={`msg ${m.role === 'user' ? 'user' : 'ai'}`}>
            <div className="who">
              {m.role === 'user' ? (
                t('advisor.you')
              ) : (
                <>
                  <span className="tag ai">Team</span>
                  {t('project.task-team')}
                </>
              )}
            </div>
            <div className="bubble">{m.content}</div>
          </div>
        ))}
        {streaming ? <div className="hint">{t('advisor.thinking')}</div> : null}
      </div>
      <hr className="divider" />
      <div className="composer">
        <textarea
          placeholder={t('project.task-team')}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
        />
        <div className="row">
          <span className="hint">{t('advisor.composer-hint')}</span>
          <span className="sp" style={{ flex: 1 }} />
          <button className="btn primary small" onClick={send} disabled={streaming}>
            <Icon name="advisor" />
            {t('advisor.send')}
          </button>
        </div>
      </div>
    </>
  );
}
