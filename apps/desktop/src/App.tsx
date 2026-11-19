// App shell: sidebar navigation + screen routing over the native glaze
// window (titlebar chrome belongs to the host). The sidebar foot mirrors
// the device state from the polled snapshot, like the prototype.

import { useEffect, type ComponentType } from 'react';
import { useApp, type View } from './state/store';
import { Icon } from './components/ui';
import Dashboard from './screens/Dashboard';
import Projects from './screens/Projects';
import ProjectDetail from './screens/ProjectDetail';
import PrintPrep from './screens/PrintPrep';
import ModelViewer from './screens/ModelViewer';
import Devices from './screens/Devices';
import History from './screens/History';
import Materials from './screens/Materials';
import Advisor from './screens/Advisor';
import Onboarding from './screens/Onboarding';
import Settings from './screens/Settings';

const screens: Record<View, ComponentType> = {
  onboarding: Onboarding,
  dashboard: Dashboard,
  projects: Projects,
  project: ProjectDetail,
  'print-prep': PrintPrep,
  'model-viewer': ModelViewer,
  devices: Devices,
  history: History,
  materials: Materials,
  advisor: Advisor,
  settings: Settings,
};

function Sidebar() {
  const { view, go, t, device, counts } = useApp();
  const state = device?.connected ? device.state : 'off';
  return (
    <aside className="sidebar">
      <div className="brand">
        <div className="mark">L</div>
        <div className="name">{t('app.name')}</div>
      </div>
      <div className="sect">{t('nav.section.workbench')}</div>
      <nav className="nav">
        <button
          className={`nav-item ${view === 'dashboard' ? 'active' : ''}`}
          onClick={() => go('dashboard')}
        >
          <Icon name="overview" />
          {t('nav.overview')}
        </button>
        <button
          className={`nav-item ${view === 'projects' || view === 'project' || view === 'print-prep' || view === 'model-viewer' ? 'active' : ''}`}
          onClick={() => go('projects')}
        >
          <Icon name="projects" />
          {t('nav.projects')}
          <span className="count num">{counts?.projects ?? ''}</span>
        </button>
        <button
          className={`nav-item ${view === 'devices' ? 'active' : ''}`}
          onClick={() => go('devices')}
        >
          <Icon name="devices" />
          {t('nav.devices')}
        </button>
        <button
          className={`nav-item ${view === 'materials' ? 'active' : ''}`}
          onClick={() => go('materials')}
        >
          <Icon name="materials" />
          {t('nav.materials')}
        </button>
        <button
          className={`nav-item ${view === 'history' ? 'active' : ''}`}
          onClick={() => go('history')}
        >
          <Icon name="history" />
          {t('nav.history')}
        </button>
      </nav>
      <div className="sect">{t('nav.section.ai')}</div>
      <nav className="nav">
        <button
          className={`nav-item ${view === 'advisor' ? 'active' : ''}`}
          onClick={() => go('advisor')}
        >
          <Icon name="advisor" />
          {t('nav.advisor')}
        </button>
      </nav>
      <div className="foot">
        <div className="foot-line">
          <span
            className={`dot ${
              state === 'printing' || state === 'heating' ? 'busy' : state === 'off' ? 'off' : 'on'
            }`}
          />
          <span className="name">{device?.connected ? device.name : t('foot.offline')}</span>
        </div>
        <div>
          {device?.connected && device.job
            ? `${t('foot.printing')} · ${t('foot.layer')}${device.job.layer}/${device.job.layers}`
            : device?.connected
              ? t(device.state === 'paused' ? 'status.paused' : 'foot.idle')
              : t('misc.device-none')}
        </div>
      </div>
    </aside>
  );
}

export default function App() {
  const { booted, view, viewId, toast, boot, t, setTheme, theme } = useApp();

  useEffect(() => {
    void boot();
    // The poll timer lives for the app lifetime — a desktop shell never
    // unmounts mid-session, so there is nothing to tear down.
  }, [boot]);

  if (!booted) {
    return (
      <div className="boot">
        <div className="boot-mark">
          <span />
          <span />
          <span />
        </div>
        <p>{t('app.name')}</p>
      </div>
    );
  }

  const Screen = screens[view];
  const showChrome = view !== 'onboarding';

  return (
    <>
      {showChrome ? (
        <div className="app">
          <Sidebar />
          <main className="main">
            <Screen key={view + (viewId ?? '')} />
          </main>
        </div>
      ) : (
        <Screen />
      )}
      {toast ? <div className="toast">{toast}</div> : null}
      <button
        className="toggle"
        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
        title={theme}
      >
        ◐ {t('settings.theme')}
      </button>
    </>
  );
}
