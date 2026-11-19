// Shared UI atoms: icons (inline SVG per the design contract — 1.5px
// stroke, 16px grid, round caps), the lifecycle pill, the layerbar, the
// empty state, modal and toast shells. Component vocabulary comes from
// design/DESIGN.md — screens must not invent private variants.

import type { ReactNode } from 'react';
import { useApp } from '../state/store';

// ---- icons -------------------------------------------------------------------

const paths: Record<string, ReactNode> = {
  overview: (
    <>
      <rect x="1.5" y="1.5" width="5.4" height="5.4" rx="1.2" />
      <rect x="9.1" y="1.5" width="5.4" height="5.4" rx="1.2" />
      <rect x="1.5" y="9.1" width="5.4" height="5.4" rx="1.2" />
      <rect x="9.1" y="9.1" width="5.4" height="5.4" rx="1.2" />
    </>
  ),
  projects: (
    <>
      <path d="M2 5.2c0-1 0-1.5.3-1.9.3-.4.8-.6 1.8-.7l1.6-.2c.7-.1 1.3-.4 1.8-.9l.4-.4c.3-.3.8-.3 1.1 0l.4.4c.5.5 1.1.8 1.8.9l1.6.2c1 .1 1.5.3 1.8.7.3.4.3.9.3 1.9V10c0 1.6 0 2.4-.5 3-.5.5-1.3.5-3 .5H5.5c-1.6 0-2.4 0-3-.5-.5-.6-.5-1.4-.5-3V5.2Z" />
      <path d="M2 8.5h12" />
    </>
  ),
  devices: (
    <>
      <path d="M3 4.5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v1.5M3 4.5h10M3 4.5c-.6 0-1 .4-1 1V11a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V5.5c0-.6-.4-1-1-1M5.5 10.5h5" />
    </>
  ),
  materials: (
    <>
      <circle cx="8" cy="8" r="5.5" />
      <circle cx="8" cy="8" r="2.2" />
      <path d="M8 2.5V1M13.5 8H15" />
    </>
  ),
  history: (
    <>
      <path d="M13.5 8A5.5 5.5 0 1 1 8 2.5c2.3 0 4.3 1.4 5.1 3.4" />
      <path d="M13.5 2v3.9h-3.9" />
    </>
  ),
  advisor: (
    <>
      <path d="M3 3.5h10a1.5 1.5 0 0 1 1.5 1.5v5A1.5 1.5 0 0 1 13 11.5H8l-3.2 2.4c-.4.3-1 0-1-.5v-1.9H3A1.5 1.5 0 0 1 1.5 10V5A1.5 1.5 0 0 1 3 3.5Z" />
      <path d="M5 6.5h6M5 8.7h3.6" />
    </>
  ),
  settings: (
    <>
      <circle cx="8" cy="8" r="2.2" />
      <path d="M8 1.8v1.6M8 12.6v1.6M1.8 8h1.6M12.6 8h1.6M3.6 3.6l1.1 1.1M11.3 11.3l1.1 1.1M12.4 3.6l-1.1 1.1M4.7 11.3l-1.1 1.1" />
    </>
  ),
  search: (
    <>
      <circle cx="7" cy="7" r="4.5" />
      <path d="M10.5 10.5 14 14" />
    </>
  ),
  plus: <path d="M8 3v10M3 8h10" />,
  shield: <path d="M8 1.5 14 4v4c0 3.4-2.4 5.9-6 6.5-3.6-.6-6-3.1-6-6.5V4l6-2.5Z" />,
  layers: (
    <>
      <path d="M2 11l6 3 6-3" />
      <path d="M2 7.5l6 3 6-3" />
      <path d="M2 4l6 3 6-3" />
    </>
  ),
  cube: (
    <>
      <path d="M24 6 40 15v18L24 42 8 33V15L24 6Z" />
      <path d="M8 15l16 9 16-9M24 24v18" />
    </>
  ),
  camera: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <circle cx="9" cy="10" r="1.6" />
      <path d="M3.5 17.5l4.5-4.5 4 4 2.5-2.5 6 6" />
    </>
  ),
  play: <path d="M5 3.5v9l7.5-4.5L5 3.5Z" />,
  back: <path d="M13 3 6 8l7 5" />,
};

export function Icon({ name, size = 16 }: { name: string; size?: number }) {
  return (
    <svg
      viewBox={name === 'cube' ? '0 0 48 48' : '0 0 16 16'}
      fill="none"
      strokeWidth={name === 'cube' ? 1.5 : 1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      width={size}
      height={size}
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

// ---- status pill (lifecycle vocabulary — invariant 1: always present) ----

const statusKeys: Record<string, string> = {
  idea: 'status.idea',
  design: 'status.design',
  slicing: 'status.slicing',
  printing: 'status.printing',
  done: 'status.done',
  failed: 'status.failed',
  queued: 'status.queued',
  cancelled: 'status.cancelled',
  paused: 'status.paused',
  heating: 'status.heating',
};

export function StatusPill({
  status,
  dark,
  big,
}: {
  status: string;
  dark?: boolean;
  big?: boolean;
}) {
  const t = useApp((s) => s.t);
  const cls = ['pill', status, dark ? 'dark-solid' : '', big ? 'big' : '']
    .filter(Boolean)
    .join(' ');
  return (
    <span className={cls}>
      <i />
      {t(statusKeys[status] ?? 'status.idea')}
    </span>
  );
}

// ---- layerbar ----

export function Layerbar({
  percent,
  variant,
}: {
  percent: number;
  variant?: 'teal' | 'warn';
}) {
  const pct = Math.max(0, Math.min(100, percent));
  return (
    <div className={`layerbar ${variant ?? ''}`}>
      <div className="fill" style={{ width: `${pct}%` }} />
    </div>
  );
}

// ---- empty state ----

export function Empty({ icon, title, sub, action }: { icon: string; title: string; sub?: string; action?: ReactNode }) {
  return (
    <div className="empty">
      <Icon name={icon} size={44} />
      <div className="e-title">{title}</div>
      {sub ? <div className="e-sub">{sub}</div> : null}
      {action}
    </div>
  );
}

// ---- confirm modal ----

export interface ConfirmState {
  title: string;
  body?: string;
  onOk: () => void;
}

export function ConfirmModal({ state, onClose }: { state: ConfirmState | null; onClose: () => void }) {
  const t = useApp((s) => s.t);
  if (!state) return null;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <div className="m-title">{state.title}</div>
        {state.body ? <div className="m-body">{state.body}</div> : null}
        <div className="m-actions">
          <button className="btn ghost" onClick={onClose}>
            {t('confirm.cancel')}
          </button>
          <button
            className="btn primary"
            onClick={() => {
              state.onOk();
              onClose();
            }}
          >
            {t('confirm.ok')}
          </button>
        </div>
      </div>
    </div>
  );
}

// ---- confirm card (AI action proposal — data, never executable AI) ----

export function ConfirmCardView({
  card,
  onAccept,
  onIgnore,
  basis,
}: {
  card: { label: string; body: string; impact: string };
  onAccept: () => void;
  onIgnore: () => void;
  basis?: string[];
}) {
  const t = useApp((s) => s.t);
  return (
    <div className="confirm-card">
      <div className="cc-title">
        <Icon name="shield" />
        {card.label || t('dash.confirm-needed')}
      </div>
      <div className="cc-body">{card.body}</div>
      {card.impact ? <div className="cc-impact">{card.impact}</div> : null}
      <div className="cc-actions">
        <button className="btn primary small" onClick={onAccept}>
          {t('dash.add-to-list')}
        </button>
        <button className="btn ghost small" onClick={onIgnore}>
          {t('dash.ignore')}
        </button>
      </div>
      {basis && basis.length > 0 ? (
        <div className="ctx-src">
          <span>{t('prep.basis')}</span>
          {basis.map((b) => (
            <span className="ref" key={b}>
              {b}
            </span>
          ))}
        </div>
      ) : null}
    </div>
  );
}

// ---- time helpers ----

export function shortDate(iso: string): string {
  if (!iso) return '';
  const [datePart] = iso.split('T');
  const [, m, d] = datePart.split('-');
  return `${m}-${Number(d)}`;
}

export function minutesText(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return `${h}h ${String(m).padStart(2, '0')}m`;
}
