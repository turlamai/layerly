// Advisor — the cross-project chat screen: conversation list, streaming
// bubbles (family line protocol over the bridge), context column with
// refs + device summary, and confirm cards as data. Honesty first: when
// BYOK is not configured the screen says so instead of faking a reply.

import { useCallback, useEffect, useRef, useState } from 'react';
import { advisorChat, api } from '@layerly/core';
import type { Conversation, Message } from '@layerly/core';
import { useApp } from '../state/store';
import { ConfirmCardView, Icon, StatusPill } from '../components/ui';

export default function Advisor() {
  const { device, t, showToast, go } = useApp();
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [convId, setConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [streamText, setStreamText] = useState('');
  const [refs, setRefs] = useState<string[]>(['device', 'materials']);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [configured, setConfigured] = useState<boolean | null>(null);

  const loadConversations = useCallback(() => {
    void api.advisor
      .conversations()
      .then(async (r) => {
        setConversations(r.conversations);
        if (!convId && r.conversations[0]) {
          setConvId(r.conversations[0].id);
        }
      })
      .catch(() => void 0);
  }, [convId]);

  useEffect(() => {
    loadConversations();
  }, [loadConversations]);

  useEffect(() => {
    void api.advisor
      .settingsView()
      .then((s) => setConfigured(!!s.model && (s['api-key'] === '__SAVED__' || s.provider === 'ollama')))
      .catch(() => setConfigured(false));
  }, []);

  useEffect(() => {
    if (!convId) return;
    void api.advisor
      .messages(convId)
      .then((r) => setMessages(r.messages))
      .catch(() => void 0);
  }, [convId]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [messages, streamText]);

  const send = () => {
    if (!convId || !draft.trim() || streaming) return;
    const text = draft.trim();
    setDraft('');
    setMessages((m) => [
      ...m,
      {
        id: `tmp-${Date.now()}`,
        'conversation-id': convId,
        role: 'user',
        content: text,
        refs: [],
        confirm: null,
        'created-at': '',
      },
    ]);
    setStreaming(true);
    setStreamText('');
    void advisorChat(
      convId,
      text,
      refs,
      (ev) => {
        if (ev.type === 'delta') {
          setStreamText((s) => s + ev.text);
        } else if (ev.type === 'done') {
          setMessages((m) => [...m, ev.message]);
          setStreamText('');
          setStreaming(false);
        } else if (ev.type === 'error') {
          setStreaming(false);
          setStreamText('');
          showToast(ev.message);
        }
      }
    ).catch((e) => {
      setStreaming(false);
      setStreamText('');
      showToast(e instanceof Error ? e.message : t('misc.error'));
    });
  };

  const visibleRefs: { id: string; label: string; status?: string }[] = [
    { id: 'device', label: device?.connected ? device.name : t('misc.device-none') },
    { id: 'materials', label: t('nav.materials') },
    { id: 'history', label: t('nav.history') },
  ];

  return (
    <>
      <div className="topbar">
        <h1>{t('advisor.title')}</h1>
        <span className="badge">Sarah</span>
        <span className="sub">{t('advisor.subtitle')}</span>
        <span className="sp" />
        {conversations.length > 1 ? (
          <select
            className="input"
            value={convId ?? ''}
            onChange={(e) => setConvId(e.target.value)}
            aria-label={t('advisor.new-chat')}
          >
            {conversations.map((c) => (
              <option key={c.id} value={c.id}>
                {c.title}
              </option>
            ))}
          </select>
        ) : null}
        <button
          className="btn ghost small"
          onClick={() => {
            void api.advisor
              .conversationsCreate('advisor', '', t('advisor.title'))
              .then((c) => {
                setConvId(c.id);
                setMessages([]);
                loadConversations();
              });
          }}
        >
          {t('advisor.new-chat')}
        </button>
      </div>
      <div className="adv-grid">
        <section className="card chat-col">
          <div className="chat chat-scroll" ref={scrollRef}>
            {messages.length === 0 && !streaming ? (
              <div className="empty" style={{ margin: 'auto' }}>
                <Icon name="advisor" size={44} />
                <div className="e-title">{t('advisor.title')}</div>
                <div className="e-sub">
                  {configured === false ? t('advisor.not-configured') : t('advisor.empty')}
                </div>
                {configured === false ? (
                  <button className="btn primary small" onClick={() => go('settings')}>
                    {t('advisor.go-settings')}
                  </button>
                ) : null}
              </div>
            ) : null}
            {messages.map((m) => (
              <div key={m.id} className={`msg ${m.role === 'user' ? 'user' : 'ai'}`}>
                <div className="who">
                  {m.role === 'user' ? (
                    t('advisor.you')
                  ) : (
                    <>
                      <span className="tag ai">Advisor</span>Sarah
                    </>
                  )}
                </div>
                <div className="bubble">
                  {m.content}
                  {m.refs.length > 0 ? (
                    <div className="ctx-src">
                      {m.refs.map((r) => (
                        <span className="ref" key={r}>
                          {r}
                        </span>
                      ))}
                    </div>
                  ) : null}
                </div>
              </div>
            ))}
            {streaming ? (
              <div className="msg ai">
                <div className="who">
                  <span className="tag ai">Advisor</span>Sarah
                </div>
                <div className="bubble">
                  {streamText || t('advisor.thinking')}
                </div>
              </div>
            ) : null}
            {messages.filter((m) => m.confirm).length > 0 ? (
              <ConfirmCardView
                card={messages.filter((m) => m.confirm)[0].confirm!}
                onAccept={() => {
                  void api.shopping
                    .create('PETG 黑 · 1 卷', 1, 89, 'ai')
                    .then(() => showToast(t('materials.add-item')));
                }}
                onIgnore={() => showToast(t('dash.ignore'))}
                basis={[t('nav.materials'), t('nav.history')]}
              />
            ) : null}
          </div>
          <div className="composer-wrap">
            <div className="composer">
              <textarea
                placeholder={t('dash.ask')}
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
                <button
                  className="btn ghost small"
                  onClick={() =>
                    setRefs((r) => (r.includes('project:ref') ? r : [...r, 'project:ref']))
                  }
                >
                  {t('advisor.ref-project')}
                </button>
                <span className="hint">{t('advisor.composer-hint')}</span>
                <span style={{ flex: 1 }} />
                <button className="btn primary small" onClick={send} disabled={streaming}>
                  {t('advisor.send')}
                </button>
              </div>
            </div>
          </div>
        </section>

        <aside className="card ctx-col">
          <div className="card-h">
            {t('advisor.ctx-title')}
            <span className="sp" />
            <span className="badge">{t('advisor.ctx-cross')}</span>
          </div>
          <div className="ctx-scroll">
            <div className="sect" style={{ padding: '2px 2px 4px' }}>
              {t('advisor.ctx-referencing')}
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {visibleRefs.map((r) => (
                <span className="chip" key={r.id}>
                  {r.label}
                  {r.id === 'device' && device?.job ? (
                    <StatusPill status={device.state === 'printing' ? 'printing' : 'done'} />
                  ) : null}
                </span>
              ))}
            </div>

            <div className="sect" style={{ padding: '8px 2px 2px' }}>
              {t('advisor.ctx-device')}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 12.5 }}>
                <span className={`dot ${device?.connected ? 'on' : 'off'}`} />
                <span style={{ fontWeight: 600 }}>{device?.connected ? device.name : t('misc.device-none')}</span>
                <span style={{ fontSize: 12, color: 'var(--mute)' }}>{t('devices.lan')}</span>
              </div>
              {device?.connected ? (
                <div className="num" style={{ fontSize: 11.5, color: 'var(--mute)' }}>
                  {t('devices.nozzle')} {Math.round(device['nozzle-temp'])}°C · {t('devices.bed')}{' '}
                  {Math.round(device['bed-temp'])}°C
                </div>
              ) : null}
            </div>

            <div className="sect" style={{ padding: '8px 2px 2px' }}>{t('advisor.ctx-memory')}</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
              <div style={{ fontSize: 11.5, color: 'var(--mute)', lineHeight: 1.5 }}>
                {t('advisor.ctx-foot')}
              </div>
            </div>
          </div>
          <div className="ctx-foot" style={{ fontSize: 11, color: 'var(--faint)' }}>
            {t('advisor.ctx-foot')}
          </div>
        </aside>
      </div>
    </>
  );
}
