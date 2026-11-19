// Model viewer — full-screen isometric wireframe stage with section and
// layer-play controls (SVG示意交互 per the prototype contract — no real
// slicing in v1). The AI modeling chain stays a V2 placeholder.

import { useEffect, useRef, useState } from 'react';
import { api } from '@layerly/core';
import { useApp } from '../state/store';
import { Empty, Icon, Layerbar } from '../components/ui';

export default function ModelViewer() {
  const { viewId, go, t } = useApp();
  const [projectName, setProjectName] = useState('');
  const [versionLabel, setVersionLabel] = useState('');
  const [totalLayers, setTotalLayers] = useState(184);
  const [hasModel, setHasModel] = useState(true);
  const [layer, setLayer] = useState(114);
  const [angle, setAngle] = useState(0);
  const [wire, setWire] = useState(true);
  const [playing, setPlaying] = useState(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const drag = useRef<number | null>(null);

  useEffect(() => {
    if (!viewId) return;
    void api.projects
      .get(viewId)
      .then((d) => {
        if (!d.project) return;
        setProjectName(d.project.name);
        const v = d.versions.find((x) => x.id === d.project?.['current-version-id']);
        setVersionLabel(v?.label ?? d.versions[0]?.label ?? '');
        setHasModel(d.versions.some((x) => x['model-file'] !== ''));
        const plan = d.plans.find((pl) => pl.recommended) ?? d.plans[0];
        if (plan) setTotalLayers(plan['est-layers'] || 184);
      })
      .catch(() => void 0);
  }, [viewId]);

  useEffect(() => {
    if (playing) {
      timer.current = setInterval(() => {
        setLayer((l) => {
          if (l >= totalLayers) {
            if (timer.current) clearInterval(timer.current);
            setPlaying(false);
            return totalLayers;
          }
          return l + 1;
        });
      }, 60);
      return () => {
        if (timer.current) clearInterval(timer.current);
      };
    }
    return undefined;
  }, [playing, totalLayers]);

  const clip = `inset(${100 - (layer / totalLayers) * 100}% 0 0 0)`;

  return (
    <div className="content full" style={{ padding: 0 }}>
      <div className="card viewer-stage">
        <svg className="layers-bg" viewBox="0 0 200 110" preserveAspectRatio="none">
          <g stroke="currentColor" strokeWidth="1" fill="none" opacity=".35">
            {[96, 78, 60, 42, 24].map((y) => (
              <path key={y} vectorEffect="non-scaling-stroke" d={`M-10 ${y} Q56 ${y - 16} 106 ${y - 4} T210 ${y - 8}`} />
            ))}
          </g>
        </svg>

        <div
          className="stage-model"
          onPointerDown={(e) => {
            drag.current = e.clientX;
            (e.target as HTMLElement).setPointerCapture(e.pointerId);
          }}
          onPointerMove={(e) => {
            if (drag.current === null) return;
            setAngle((a) => a + (e.clientX - drag.current!));
            drag.current = e.clientX;
          }}
          onPointerUp={() => {
            drag.current = null;
          }}
        >
          {hasModel ? (
            <svg
              viewBox="0 0 420 420"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinejoin="round"
              strokeLinecap="round"
              style={{ transform: `rotate(${angle}deg)`, opacity: wire ? 1 : 0.45, clipPath: clip }}
            >
              <g opacity=".28">
                <path d="M210 212 L210 230" />
                <path d="M210 230 L400.5 340" />
                <path d="M210 230 L88.8 300" />
              </g>
              <path d="M210 212 L400.5 322 L279.3 392 L88.8 282 Z" />
              <path d="M400.5 322 L279.3 392 L279.3 410 L400.5 340 Z" />
              <path d="M279.3 392 L88.8 282 L88.8 300 L279.3 410 Z" />
              <g opacity=".3" strokeWidth="1.2">
                <path d="M400.5 334 L279.3 404" />
                <path d="M400.5 328 L279.3 398" />
                <path d="M279.3 404 L88.8 294" />
                <path d="M279.3 398 L88.8 288" />
              </g>
              <g opacity=".8" strokeWidth="1.4">
                <ellipse cx="210" cy="242" rx="7.4" ry="4.3" />
                <ellipse cx="348.6" cy="322" rx="7.4" ry="4.3" />
              </g>
              <ellipse cx="270.6" cy="273" rx="24.5" ry="14.1" />
              <ellipse cx="270.6" cy="273" rx="8.6" ry="5" />
              <g opacity=".55" strokeWidth="1.4">
                <path d="M246.1 273 L246.1 287" />
                <path d="M295.1 273 L295.1 287" />
                <path d="M246.1 287 A24.5 14.1 0 0 0 295.1 287" />
              </g>
              <path d="M135.5 243 L308.7 343 L274.1 363 L100.9 263 Z" />
              <path d="M308.7 343 L274.1 363 L274.1 385 L308.7 365 Z" />
              <path d="M274.1 363 L100.9 263 L100.9 285 L274.1 385 Z" />
              <path d="M282.7 312 L308.7 327 L274.1 347 L248.1 332 Z" />
              <path d="M308.7 327 L274.1 347 L274.1 363 L308.7 343 Z" />
              <path d="M274.1 347 L248.1 332 L248.1 350 L274.1 363 Z" />
            </svg>
          ) : (
            <Empty icon="cube" title={t('project.no-model-title')} sub={t('project.no-model-body')} />
          )}
        </div>

        <div className="float tl">
          <button className="btn ghost small" onClick={() => go('project', viewId ?? '')}>
            ← {projectName} {versionLabel}
          </button>
        </div>
        <div className="float tc">
          <span className="pill printing">
            <i />
            {versionLabel} · {t('viewer.current-version')}
          </span>
        </div>
        <div className="float tr">
          <div className="float-bar">
            <button
              className="iconbtn"
              title={t('viewer.wireframe')}
              onClick={() => setWire((w) => !w)}
              aria-pressed={!wire}
            >
              <Icon name="cube" />
            </button>
            <button
              className="iconbtn"
              title={t('viewer.slice')}
              onClick={() => setLayer((l) => (l === totalLayers ? Math.floor(totalLayers / 2) : totalLayers))}
            >
              <Icon name="layers" />
            </button>
            <button
              className="iconbtn"
              title={t('viewer.reset')}
              onClick={() => {
                setAngle(0);
                setLayer(totalLayers);
              }}
            >
              <Icon name="history" />
            </button>
          </div>
        </div>

        <div className="float bl">
          <div className="card pad float-card" style={{ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span className="num" style={{ fontSize: 12, fontWeight: 600 }}>
              64 × 42 × 9 mm
            </span>
            <span className="num" style={{ fontSize: 11, color: 'var(--mute)' }}>
              {t('viewer.volume')} 14.2 cm³ · 42 {t('misc.g')}
            </span>
          </div>
        </div>

        <div className="float bc">
          <div className="card pad float-card slice-ctl">
            <div className="slice-track">
              <input
                type="range"
                min={1}
                max={totalLayers}
                value={layer}
                aria-label={t('viewer.slice')}
                onChange={(e) => setLayer(Number(e.target.value))}
                style={{ flex: 1 }}
              />
            </div>
            <span className="num" style={{ fontSize: 12 }}>
              L {layer} / {totalLayers}
            </span>
            <button
              className="btn ghost small"
              onClick={() => {
                if (playing) {
                  if (timer.current) clearInterval(timer.current);
                  setPlaying(false);
                } else {
                  if (layer >= totalLayers) setLayer(1);
                  setPlaying(true);
                }
              }}
            >
              <Icon name="play" />
              {playing ? t('viewer.pause-play') : t('viewer.play')}
            </button>
          </div>
        </div>

        <div className="float br">
          <div className="card pad float-card hint-card">
            <span className="badge v2">AI 建模 V2</span>
            <span style={{ fontSize: 11, color: 'var(--mute)', lineHeight: 1.5 }}>{t('viewer.v2-note')}</span>
          </div>
        </div>

        <div className="float tl" style={{ top: 52 }}>
          <Layerbar percent={(layer / totalLayers) * 100} />
        </div>
      </div>
    </div>
  );
}
