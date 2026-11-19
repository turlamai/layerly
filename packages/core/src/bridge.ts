// Bridge to the Layerly Racket backend.
//
// Two transports behind one interface (same shape the family uses):
//  - native: the page runs on the controlled glaze:// origin; calls ride
//    the GLZ1 message handler (window.__glz1, injected at document
//    start). No TCP port exists in production.
//  - http: the page is served by the loopback server (vite dev) and
//    talks plain relative fetch.
//
// Streaming (advisor chat) uses the family line protocol on both
// transports: first line `OK` then NDJSON event lines, or an
// `ERR <status> <message>` line instead of opening the stream.

interface Glz1 {
  invoke(
    path: string,
    args?: unknown,
    opts?: { method?: string; timeoutMs?: number }
  ): Promise<unknown>;
  invokeStream(
    path: string,
    args?: unknown,
    opts?: {
      onDelta?: OnDelta;
      signal?: AbortSignal;
      timeoutMs?: number;
    }
  ): Promise<string>;
}

type OnDelta = (chunk: string) => void;

declare global {
  interface Window {
    __glz1?: Glz1;
  }
}

function nativeBridge(): Glz1 | null {
  return (typeof window !== 'undefined' && window.__glz1) || null;
}

let probe: Promise<boolean> | null = null;

/** True once a backend answers — native bridge present, or /api/health ok. */
export function hasBackend(): Promise<boolean> {
  if (!probe) {
    const g = nativeBridge();
    probe = g
      ? Promise.resolve(true)
      : fetch('/api/health', { method: 'POST' })
          .then((r) => r.ok)
          .catch(() => false);
  }
  return probe;
}

/** POST JSON to the backend; returns the parsed response. */
export async function apiPost<T>(path: string, body?: unknown): Promise<T> {
  const g = nativeBridge();
  if (g) {
    return (await g.invoke(path, body ?? {})) as T;
  }
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`${path} failed: ${res.status} ${detail.slice(0, 200)}`);
  }
  return (await res.json()) as T;
}

/**
 * Family line protocol over both transports. Buffers chunks until the
 * first `\n` (the OK / ERR status line), throws on ERR, then forwards
 * the remainder plus subsequent chunks to onChunk.
 */
export async function apiStream(
  path: string,
  body: unknown,
  onChunk: OnDelta,
  signal?: AbortSignal
): Promise<string> {
  const g = nativeBridge();
  if (g) {
    return g.invokeStream(path, body, {
      onDelta: withLineProtocol(onChunk),
      signal,
    });
  }
  // HTTP: fetch with a streaming body reader.
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
    signal,
  });
  if (!res.ok || !res.body) {
    throw new Error(`${path} failed: ${res.status}`);
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let statusSeen = false;
  let tail = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    for (;;) {
      const idx = buffer.indexOf('\n');
      if (idx < 0) break;
      const line = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 1);
      if (!statusSeen) {
        statusSeen = true;
        if (line.startsWith('OK')) {
          tail = buffer;
          buffer = '';
          // forward any bytes that arrived with the OK line
          if (tail) onChunk(tail);
          continue;
        }
        throw new Error(line);
      }
      onChunk(line + '\n');
    }
  }
  if (buffer && statusSeen) onChunk(buffer);
  return '';
}

// The native invokeStream already hands raw deltas; apply the same
// status-line discipline and NDJSON framing as the HTTP path.
function withLineProtocol(onChunk: OnDelta): OnDelta {
  let first = true;
  let buffer = '';
  return (chunk: string) => {
    if (first) {
      buffer += chunk;
      const idx = buffer.indexOf('\n');
      if (idx < 0) return;
      const line = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 1);
      first = false;
      if (!line.startsWith('OK')) {
        throw new Error(line);
      }
      if (buffer) onChunk(buffer);
      buffer = '';
      return;
    }
    buffer += chunk;
    for (;;) {
      const idx = buffer.indexOf('\n');
      if (idx < 0) break;
      onChunk(buffer.slice(0, idx) + '\n');
      buffer = buffer.slice(idx + 1);
    }
  };
}

// ---- entity types (mirror the SQLite projections in backend/store.rkt) ----

export type LifecycleStatus =
  | 'idea'
  | 'design'
  | 'slicing'
  | 'printing'
  | 'done'
  | 'failed';

export interface ConfirmCard {
  label: string;
  body: string;
  impact: string;
  action: string;
  args: Record<string, unknown>;
}

export interface Message {
  id: string;
  'conversation-id': string;
  role: string;
  content: string;
  refs: string[];
  confirm: ConfirmCard | null;
  'created-at': string;
}

export interface Conversation {
  id: string;
  scope: string;
  'project-id': string;
  title: string;
  'created-at': string;
  'updated-at': string;
}

export interface PrintJob {
  id: string;
  'project-id': string;
  'version-id': string;
  'plan-id': string;
  'device-id': string;
  'device-name': string;
  seq: number;
  total: number;
  status: 'queued' | 'printing' | 'done' | 'failed' | 'cancelled';
  'material-name': string;
  'material-hex': string;
  layer: number;
  layers: number;
  minutes: number;
  grams: number;
  lesson: string;
  'queued-at': string;
  'started-at': string;
  'ended-at': string;
}

export interface JobSummary {
  'job-id': string;
  'project-id': string;
  name: string;
  seq: number;
  total: number;
  layer: number;
  layers: number;
  percent: number;
  'minutes-left': number;
  'material-name': string;
  'material-hex': string;
}

export interface AmsSlot {
  n: number;
  type: string;
  'color-name': string;
  'color-hex': string;
  'remaining-g': number;
  label: string;
}

export interface DeviceSnapshot {
  kind: string;
  connected: boolean;
  state: string;
  name: string;
  'device-id': string;
  'nozzle-temp': number;
  'bed-temp': number;
  'chamber-temp': number;
  'fan-percent': number;
  ams: AmsSlot[];
  job: JobSummary | null;
  queue: string[];
  error?: string;
}

export interface Device {
  id: string;
  name: string;
  model: string;
  host: string;
  serial: string;
  kind: string;
  'has-access-code': boolean;
  'last-seen': string;
  'created-at': string;
}

export interface Project {
  id: string;
  name: string;
  brief: string;
  status: LifecycleStatus;
  'size-text': string;
  'target-qty': number;
  'current-version-id': string;
  'created-at': string;
  'updated-at': string;
}

export interface ProjectSummary extends Project {
  'version-label': string;
  job: PrintJob | null;
}

export interface Version {
  id: string;
  'project-id': string;
  label: string;
  note: string;
  'model-file': string;
  'material-name': string;
  'created-at': string;
}

export interface PlanPart {
  name: string;
  slot: number;
  note?: string;
}

export interface SlicePlan {
  id: string;
  'project-id': string;
  'version-id': string;
  label: string;
  strategy: string;
  walls: number;
  infill: string;
  supports: string;
  'layer-height': number;
  'nozzle-temp': number;
  'bed-temp': number;
  'est-minutes': number;
  'est-grams': number;
  'est-layers': number;
  parts: PlanPart[];
  recommended: boolean;
  'created-at': string;
}

export interface Feedback {
  id: string;
  'job-id': string;
  'project-id': string;
  kind: string;
  text: string;
  'photo-file': string;
  'created-at': string;
}

export interface Material {
  id: string;
  name: string;
  brand: string;
  type: string;
  'color-name': string;
  'color-hex': string;
  'remaining-g': number;
  'total-g': number;
  'opened-date': string;
  slot: number;
  status: string;
  notes: string;
  'created-at': string;
  'updated-at': string;
}

export interface ShoppingItem {
  id: string;
  name: string;
  qty: number;
  price: number;
  source: string;
  'created-at': string;
}

export interface Purchase {
  id: string;
  name: string;
  qty: number;
  price: number;
  arrived: boolean;
  'purchased-at': string;
  'arrived-at': string;
}

export interface LibraryCounts {
  projects: number;
  idea: number;
  design: number;
  slicing: number;
  printing: number;
  done: number;
  failed: number;
  jobs: number;
  materials: number;
  'stock-g': number;
}

export interface ProjectDetail {
  project: ProjectSummary | null;
  versions: Version[];
  plans: SlicePlan[];
  jobs: PrintJob[];
  feedback: Feedback[];
}

export interface AdvisorSettings {
  provider: string;
  model: string;
  'base-url': string;
  'api-key': string;
  'redact-enabled': boolean;
  presets: { id: string; label: string; model: string; kind: string }[];
}

/** Chat stream events (NDJSON lines after the OK status line). */
export type ChatEvent =
  | { type: 'start'; 'message-id': string }
  | { type: 'delta'; text: string }
  | { type: 'done'; 'message-id': string; message: Message }
  | { type: 'error'; message: string };

// ---- typed helpers over the backend routes -------------------------------

export interface AppInfo {
  name: string;
  version: string;
}

export interface AppSettings {
  key: string;
  value: unknown;
}

export const api = {
  health: () => apiPost<{ ok: boolean; version: string }>('/api/health'),
  appInfo: () => apiPost<AppInfo>('/api/app/info'),
  librarySummary: () =>
    apiPost<{ counts: LibraryCounts; device: DeviceSnapshot }>('/api/library/summary'),

  projects: {
    list: () => apiPost<{ projects: ProjectSummary[] }>('/api/projects/list'),
    get: (id: string) => apiPost<ProjectDetail>('/api/projects/get', { id }),
    create: (name: string, brief: string, sizeText = '', targetQty = 1) =>
      apiPost<ProjectSummary>('/api/projects/create', {
        name,
        brief,
        'size-text': sizeText,
        'target-qty': targetQty,
      }),
    update: (id: string, patch: Partial<Project>) =>
      apiPost<ProjectSummary>('/api/projects/update', { id, patch }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/projects/delete', { id }),
  },

  versions: {
    create: (
      projectId: string,
      label: string,
      note = '',
      modelFile = '',
      materialName = ''
    ) =>
      apiPost<Version>('/api/versions/create', {
        'project-id': projectId,
        label,
        note,
        'model-file': modelFile,
        'material-name': materialName,
      }),
    setCurrent: (projectId: string, versionId: string) =>
      apiPost<{ ok: boolean }>('/api/versions/set-current', {
        'project-id': projectId,
        'version-id': versionId,
      }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/versions/delete', { id }),
  },

  plans: {
    create: (projectId: string, versionId: string, plan: Partial<SlicePlan>) =>
      apiPost<SlicePlan>('/api/plans/create', {
        'project-id': projectId,
        'version-id': versionId,
        plan,
      }),
    setRecommended: (id: string) =>
      apiPost<{ ok: boolean }>('/api/plans/set-recommended', { id }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/plans/delete', { id }),
  },

  jobs: {
    list: (limit = 200) => apiPost<{ jobs: PrintJob[] }>('/api/jobs/list', { limit }),
    get: (id: string) => apiPost<PrintJob>('/api/jobs/get', { id }),
    create: (args: {
      'project-id': string;
      'version-id'?: string;
      'plan-id'?: string;
      seq?: number;
      total?: number;
      layers?: number;
      minutes?: number;
      grams?: number;
      'material-name'?: string;
      'material-hex'?: string;
    }) => apiPost<PrintJob>('/api/jobs/create', args),
    /** The dispatch boundary — print-prep is the only caller. */
    queue: (jobId: string) =>
      apiPost<{ queued: boolean; device: DeviceSnapshot }>('/api/jobs/queue', {
        'job-id': jobId,
      }),
  },

  feedback: {
    create: (projectId: string, jobId: string, kind: string, text: string, dataB64?: string) =>
      apiPost<Feedback>('/api/feedback/create', {
        'project-id': projectId,
        'job-id': jobId,
        kind,
        text,
        'data-b64': dataB64,
      }),
  },

  materials: {
    list: () => apiPost<{ materials: Material[] }>('/api/materials/list'),
    create: (material: Partial<Material>) =>
      apiPost<Material>('/api/materials/create', { material }),
    update: (id: string, patch: Partial<Material>) =>
      apiPost<Material>('/api/materials/update', { id, patch }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/materials/delete', { id }),
  },

  shopping: {
    list: () => apiPost<{ items: ShoppingItem[] }>('/api/shopping/list'),
    create: (name: string, qty: number, price: number, source = 'manual') =>
      apiPost<ShoppingItem>('/api/shopping/create', { name, qty, price, source }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/shopping/delete', { id }),
  },

  purchases: {
    list: () => apiPost<{ purchases: Purchase[] }>('/api/purchases/list'),
    create: (name: string, qty: number, price: number) =>
      apiPost<Purchase>('/api/purchases/create', { name, qty, price }),
    arrive: (id: string) => apiPost<Purchase>('/api/purchases/arrive', { id }),
  },

  files: {
    saveModel: (projectId: string, filename: string, dataB64: string) =>
      apiPost<{ path: string }>('/api/files/save-model', {
        'project-id': projectId,
        filename,
        'data-b64': dataB64,
      }),
    savePhoto: (projectId: string, filename: string, dataB64: string) =>
      apiPost<{ path: string }>('/api/files/save-photo', {
        'project-id': projectId,
        filename,
        'data-b64': dataB64,
      }),
  },

  demo: {
    seed: () =>
      apiPost<{ counts: LibraryCounts; device: DeviceSnapshot }>('/api/demo/seed'),
  },

  device: {
    state: () => apiPost<DeviceSnapshot>('/api/device/state'),
    list: () => apiPost<{ devices: Device[] }>('/api/device/list'),
    create: (args: {
      name: string;
      model?: string;
      host?: string;
      serial?: string;
      'access-code'?: string;
      kind?: string;
    }) =>
      apiPost<{ device: Device; snapshot: DeviceSnapshot }>('/api/device/create', args),
    update: (id: string, patch: Partial<Device> & { 'access-code'?: string }) =>
      apiPost<Device>('/api/device/update', { id, patch }),
    delete: (id: string) => apiPost<{ ok: boolean }>('/api/device/delete', { id }),
    connect: (id: string) => apiPost<DeviceSnapshot>('/api/device/connect', { id }),
    disconnect: () => apiPost<DeviceSnapshot>('/api/device/disconnect'),
    pause: () => apiPost<{ state: string; snapshot: DeviceSnapshot }>('/api/device/pause'),
    resume: () => apiPost<{ state: string; snapshot: DeviceSnapshot }>('/api/device/resume'),
    stop: () => apiPost<{ state: string; snapshot: DeviceSnapshot }>('/api/device/stop'),
    speed: (layersPerSecond: number) =>
      apiPost<DeviceSnapshot>('/api/device/speed', { 'layers-per-second': layersPerSecond }),
  },

  advisor: {
    settingsView: () => apiPost<AdvisorSettings>('/api/advisor/settings-view'),
    settingsSave: (patch: Partial<AdvisorSettings>) =>
      apiPost<AdvisorSettings>('/api/advisor/settings-save', { patch }),
    conversations: (projectId = '') =>
      apiPost<{ conversations: Conversation[] }>('/api/advisor/conversations/list', {
        'project-id': projectId,
      }),
    conversationsCreate: (scope: string, projectId: string, title: string) =>
      apiPost<Conversation>('/api/advisor/conversations/create', {
        scope,
        'project-id': projectId,
        title,
      }),
    conversationsDelete: (id: string) =>
      apiPost<{ ok: boolean }>('/api/advisor/conversations/delete', { id }),
    messages: (conversationId: string) =>
      apiPost<{ messages: Message[] }>('/api/advisor/messages', {
        'conversation-id': conversationId,
      }),
    redactPreview: (text: string) =>
      apiPost<{ text: string; matches: string[] }>('/api/advisor/redact-preview', { text }),
  },

  settings: {
    get: (key: string) => apiPost<AppSettings>('/api/settings/get', { key }),
    set: (key: string, value: unknown) =>
      apiPost<{ ok: boolean }>('/api/settings/set', { key, value }),
  },
};

/** Stream one advisor chat turn as parsed NDJSON events. */
export async function advisorChat(
  conversationId: string,
  message: string,
  refs: string[],
  onEvent: (event: ChatEvent) => void,
  signal?: AbortSignal
): Promise<void> {
  await apiStream(
    '/api/advisor/chat',
    { 'conversation-id': conversationId, message, refs },
    (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        onEvent(JSON.parse(trimmed) as ChatEvent);
      } catch {
        // one malformed frame never kills the stream
      }
    },
    signal
  );
}
