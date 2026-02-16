import { useState, useCallback, useRef, useEffect } from 'react';
import type { SignRequest, SignResponse } from '../shared/protocol';
import { SignBridgeClient } from './sdk/signbridge-client';
import type { SignBridgeEvent } from './sdk/signbridge-client';
import { ALL_SCENARIOS, SCENARIOS_BY_CATEGORY, type TestScenario } from './tests/scenarios';
import BackendStore from './BackendStore';

// ── Types ────────────────────────────────────────────────────────────────────

interface TestRun {
  id: string;
  scenarioId: string;
  scenarioName: string;
  request: SignRequest;
  response: SignResponse | null;
  error: string | null;
  status: 'pending' | 'accepted' | 'error' | 'timeout' | 'validation-error';
  sentAt: number;
  completedAt: number | null;
  durationMs: number | null;
}

interface ServerEvent {
  id: string;
  timestamp: string;
  category: string;
  objectId?: string;
  requestId?: string;
  details: Record<string, unknown>;
}

interface Toast {
  id: string;
  type: 'success' | 'error' | 'info';
  message: string;
}

// ── App ──────────────────────────────────────────────────────────────────────

export default function App() {
  const [page, setPage] = useState<'tester' | 'store'>('tester');
  const [selectedScenario, setSelectedScenario] = useState<TestScenario | null>(null);
  const [previewRequest, setPreviewRequest] = useState<SignRequest | null>(null);
  const [runs, setRuns] = useState<TestRun[]>([]);
  const [events, setEvents] = useState<ServerEvent[]>([]);
  const [activeTab, setActiveTab] = useState<'response' | 'request-json'>('response');
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [backendUp, setBackendUp] = useState<boolean | null>(null);
  const [sdkEvents, setSdkEvents] = useState<SignBridgeEvent[]>([]);

  const clientRef = useRef(new SignBridgeClient({ timeout: 10_000 }));
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastEventIdRef = useRef(0);

  // ── Toast helper ───────────────────────────────────────────────────────────
  const toast = useCallback((type: Toast['type'], message: string) => {
    const t: Toast = { id: String(Date.now()), type, message };
    setToasts((prev) => [...prev, t]);
    setTimeout(() => setToasts((prev) => prev.filter((x) => x.id !== t.id)), 4000);
  }, []);

  // ── Backend health check ───────────────────────────────────────────────────
  useEffect(() => {
    const check = () => {
      fetch('/api/health')
        .then((r) => { setBackendUp(r.ok); })
        .catch(() => { setBackendUp(false); });
    };
    check();
    const interval = setInterval(check, 5000);
    return () => clearInterval(interval);
  }, []);

  // ── SDK event listener ─────────────────────────────────────────────────────
  useEffect(() => {
    const unsub = clientRef.current.on((event) => {
      setSdkEvents((prev) => [...prev, event]);
    });
    return unsub;
  }, []);

  // ── Poll server events ────────────────────────────────────────────────────
  useEffect(() => {
    const poll = () => {
      fetch(`/api/events/since/${lastEventIdRef.current}`)
        .then((r) => r.json())
        .then((data: { events: ServerEvent[] }) => {
          if (data.events.length > 0) {
            setEvents((prev) => [...prev, ...data.events]);
            lastEventIdRef.current = Math.max(
              ...data.events.map((e) => parseInt(e.id, 10)),
            );
          }
        })
        .catch(() => { /* ignore poll errors */ });
    };
    pollRef.current = setInterval(poll, 1000);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  // ── Select scenario ────────────────────────────────────────────────────────
  const handleSelect = useCallback((scenario: TestScenario) => {
    setSelectedScenario(scenario);
    const req = scenario.build();
    setPreviewRequest(req);
  }, []);

  // ── Send request ───────────────────────────────────────────────────────────
  const handleSend = useCallback(async () => {
    if (!selectedScenario || !previewRequest) return;

    const run: TestRun = {
      id: previewRequest.requestId,
      scenarioId: selectedScenario.id,
      scenarioName: selectedScenario.name,
      request: previewRequest,
      response: null,
      error: null,
      status: 'pending',
      sentAt: Date.now(),
      completedAt: null,
      durationMs: null,
    };

    setRuns((prev) => [run, ...prev]);
    setActiveTab('response');
    toast('info', `Sent: ${selectedScenario.name}`);

    try {
      const response = await clientRef.current.sign(previewRequest);
      const now = Date.now();
      setRuns((prev) =>
        prev.map((r) =>
          r.id === run.id
            ? {
                ...r,
                response,
                status: response.status === 'accepted' ? 'accepted' : 'error',
                completedAt: now,
                durationMs: now - run.sentAt,
              }
            : r,
        ),
      );
      toast(
        response.status === 'accepted' ? 'success' : 'error',
        `${selectedScenario.name}: ${response.status}`,
      );
    } catch (err) {
      const now = Date.now();
      const message = err instanceof Error ? err.message : String(err);
      const isTimeout = message.includes('timeout');
      const isValidation = message.includes('BAD_REQUEST') || message.includes('UNSUPPORTED');
      setRuns((prev) =>
        prev.map((r) =>
          r.id === run.id
            ? {
                ...r,
                error: message,
                status: isTimeout ? 'timeout' : isValidation ? 'validation-error' : 'error',
                completedAt: now,
                durationMs: now - run.sentAt,
              }
            : r,
        ),
      );
      toast('error', `${selectedScenario.name}: ${message.slice(0, 80)}`);
    }

    // Regenerate request with fresh UUID for next send
    const fresh = selectedScenario.build();
    setPreviewRequest(fresh);
  }, [selectedScenario, previewRequest, toast]);

  // ── Run All Scenarios ──────────────────────────────────────────────────────
  const handleRunAll = useCallback(async () => {
    toast('info', `Running all ${ALL_SCENARIOS.length} scenarios...`);
    for (const scenario of ALL_SCENARIOS) {
      setSelectedScenario(scenario);
      const req = scenario.build();
      setPreviewRequest(req);

      const run: TestRun = {
        id: req.requestId,
        scenarioId: scenario.id,
        scenarioName: scenario.name,
        request: req,
        response: null,
        error: null,
        status: 'pending',
        sentAt: Date.now(),
        completedAt: null,
        durationMs: null,
      };

      setRuns((prev) => [run, ...prev]);

      try {
        const response = await clientRef.current.sign(req);
        const now = Date.now();
        setRuns((prev) =>
          prev.map((r) =>
            r.id === run.id
              ? {
                  ...r,
                  response,
                  status: response.status === 'accepted' ? 'accepted' : 'error',
                  completedAt: now,
                  durationMs: now - run.sentAt,
                }
              : r,
          ),
        );
      } catch (err) {
        const now = Date.now();
        const message = err instanceof Error ? err.message : String(err);
        setRuns((prev) =>
          prev.map((r) =>
            r.id === run.id
              ? { ...r, error: message, status: 'error', completedAt: now, durationMs: now - run.sentAt }
              : r,
          ),
        );
      }
    }
    toast('success', 'All scenarios completed!');
  }, [toast]);

  // ── Clear ──────────────────────────────────────────────────────────────────
  const handleClearEvents = useCallback(() => {
    fetch('/api/events', { method: 'DELETE' }).catch(() => {});
    setEvents([]);
    lastEventIdRef.current = 0;
  }, []);

  const handleClearRuns = useCallback(() => {
    setRuns([]);
    setSdkEvents([]);
  }, []);

  // ── Render ─────────────────────────────────────────────────────────────────
  const latestRun = runs[0] ?? null;

  return (
    <div className="app">
      {/* Header */}
      <header className="app-header">
        <h1>
          🔏 SignBridge Test Client
          <span className="version">v1.0 — Protocol v1.0</span>
        </h1>
        <div className="status-bar">
          <nav className="page-nav">
            <button
              className={`nav-btn ${page === 'tester' ? 'active' : ''}`}
              onClick={() => setPage('tester')}
            >
              🧪 Tester
            </button>
            <button
              className={`nav-btn ${page === 'store' ? 'active' : ''}`}
              onClick={() => setPage('store')}
            >
              📦 Backend Store
            </button>
          </nav>
          <div className="connection-status">
            <span className={`connection-dot ${backendUp ? 'connected' : 'disconnected'}`} />
            Mock backend: {backendUp === null ? 'checking...' : backendUp ? 'online' : 'offline'}
          </div>
          {page === 'tester' && (
            <>
              <button className="btn btn-sm btn-ghost" onClick={handleRunAll}>
                ▶ Run All ({ALL_SCENARIOS.length})
              </button>
              <button className="btn btn-sm btn-ghost" onClick={handleClearRuns}>
                Clear Runs
              </button>
            </>
          )}
        </div>
      </header>

      {page === 'store' ? (
        <BackendStore />
      ) : (
      <main className="app-main">
        {/* Left Panel: Scenario List */}
        <div className="panel">
          <div className="panel-header">
            Test Scenarios
            <span className="count-badge">{ALL_SCENARIOS.length}</span>
          </div>
          <div className="panel-body">
            {(
              [
                ['standard', 'Standard Examples'],
                ['validation', 'Validation Tests'],
                ['edge-case', 'Edge Cases'],
              ] as const
            ).map(([key, label]) => (
              <div key={key} className="scenario-category">
                <div className="category-label">{label}</div>
                {SCENARIOS_BY_CATEGORY[key].map((scenario) => (
                  <div
                    key={scenario.id}
                    className={`scenario-item ${selectedScenario?.id === scenario.id ? 'selected' : ''}`}
                    onClick={() => handleSelect(scenario)}
                  >
                    <div className="name">
                      <span className={`badge badge-${scenario.category}`}>
                        {scenario.section ? `§${scenario.section}` : scenario.category}
                      </span>
                      {scenario.name}
                    </div>
                    <div className="desc">{scenario.description}</div>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>

        {/* Center Panel: Request details + Response */}
        <div className="panel">
          {selectedScenario && previewRequest ? (
            <>
              <div className="action-bar">
                <button
                  className="btn btn-primary"
                  onClick={handleSend}
                  disabled={!backendUp}
                >
                  🔏 Send Request
                </button>
                <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>
                  {selectedScenario.name}
                </span>
              </div>

              <div className="expected-outcome" style={{ margin: '12px 12px 0' }}>
                <strong>Expected: </strong>{selectedScenario.expectedOutcome}
              </div>

              <div className="tabs" style={{ padding: '0 12px' }}>
                <div
                  className={`tab ${activeTab === 'response' ? 'active' : ''}`}
                  onClick={() => setActiveTab('response')}
                >
                  Response {latestRun?.scenarioId === selectedScenario.id ? `(${latestRun.status})` : ''}
                </div>
                <div
                  className={`tab ${activeTab === 'request-json' ? 'active' : ''}`}
                  onClick={() => setActiveTab('request-json')}
                >
                  Request JSON
                </div>
              </div>

              <div className="panel-body">
                {activeTab === 'request-json' && (
                  <div className="detail-section">
                    <div className="detail-section-header">
                      Request Payload
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text-muted)' }}>
                        {JSON.stringify(previewRequest).length} bytes
                      </span>
                    </div>
                    <div className="json-viewer">
                      {JSON.stringify(previewRequest, null, 2)}
                    </div>
                  </div>
                )}

                {activeTab === 'response' && (
                  <div className="request-details">
                    {/* Run History */}
                    {runs
                      .filter((r) => r.scenarioId === selectedScenario.id)
                      .map((run) => (
                        <div key={run.id} className="response-block">
                          <div className="response-header">
                            <span className={`status-dot ${run.status === 'pending' ? 'pending' : run.status === 'accepted' ? 'ok' : 'error'}`} />
                            <span>{run.status.toUpperCase()}</span>
                            {run.durationMs !== null && (
                              <span style={{ color: 'var(--text-muted)', marginLeft: 'auto', fontFamily: 'var(--font-mono)', fontSize: '11px' }}>
                                {run.durationMs}ms
                              </span>
                            )}
                          </div>
                          <div className="json-viewer" style={{ maxHeight: '300px' }}>
                            {run.response
                              ? JSON.stringify(run.response, null, 2)
                              : run.error
                                ? `Error: ${run.error}`
                                : 'Waiting for response...'}
                          </div>
                        </div>
                      ))}
                    {runs.filter((r) => r.scenarioId === selectedScenario.id).length === 0 && (
                      <div className="empty-state">
                        <div className="icon">📤</div>
                        <div>Click "Send Request" to run this scenario</div>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="empty-state">
              <div className="icon">🔏</div>
              <div>Select a test scenario from the left panel</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '8px' }}>
                {ALL_SCENARIOS.length} scenarios covering Standard v1.0.3
              </div>
            </div>
          )}
        </div>

        {/* Right Panel: Server Events + SDK Events */}
        <div className="panel">
          <div className="panel-header">
            Event Log
            <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
              <span className="count-badge">{events.length}</span>
              <button className="btn btn-sm btn-ghost" onClick={handleClearEvents}>
                Clear
              </button>
            </div>
          </div>
          <div className="panel-body">
            {events.length === 0 && sdkEvents.length === 0 ? (
              <div className="empty-state">
                <div className="icon">📋</div>
                <div>No events yet</div>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Events will appear here as the native host hits callback endpoints
                </div>
              </div>
            ) : (
              <>
                {/* SDK events */}
                {sdkEvents.map((evt, i) => (
                  <div key={`sdk-${i}`} className="event-entry">
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span className="event-type" style={{ color: 'var(--accent)' }}>
                        SDK: {evt.type}
                      </span>
                      <span className="event-time">
                        {new Date(evt.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                    <div className="event-details">
                      {evt.requestId ? evt.requestId.slice(0, 8) + '...' : '(no requestId)'}
                      {evt.error && <span style={{ color: 'var(--error)' }}> {evt.error.slice(0, 60)}</span>}
                    </div>
                  </div>
                ))}
                {/* Server events */}
                {[...events].reverse().map((evt) => (
                  <div key={evt.id} className="event-entry">
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span className={`event-type ${evt.category}`}>
                        {evt.category}
                      </span>
                      <span className="event-time">
                        {new Date(evt.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                    <div className="event-details">
                      {evt.objectId && <span>obj: {evt.objectId} </span>}
                      {evt.requestId && <span>req: {evt.requestId.slice(0, 8)}... </span>}
                    </div>
                    {evt.details && Object.keys(evt.details).length > 0 && (
                      <div style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', color: 'var(--text-muted)', marginTop: '4px' }}>
                        {JSON.stringify(evt.details).slice(0, 120)}
                        {JSON.stringify(evt.details).length > 120 && '...'}
                      </div>
                    )}
                  </div>
                ))}
              </>
            )}
          </div>
        </div>
      </main>
      )}

      {/* Toasts */}
      <div className="toast-container">
        {toasts.map((t) => (
          <div key={t.id} className={`toast ${t.type}`}>
            {t.message}
          </div>
        ))}
      </div>
    </div>
  );
}
