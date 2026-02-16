import { useState, useEffect, useCallback } from 'react';

// ── Types ────────────────────────────────────────────────────────────────────

interface UploadEntry {
  id: string;
  objectId: string;
  receivedAt: string;
  contentType: string;
  size: number;
  preview: string | null;
  isText: boolean;
  isPdf: boolean;
  endpoint: string;
  headers: Record<string, string>;
}

interface CallbackEntry {
  id: string;
  objectId: string;
  requestId: string;
  receivedAt: string;
  type: 'success' | 'error' | 'progress';
  payload: Record<string, unknown>;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(i > 0 ? 1 : 0)} ${sizes[i]}`;
}

function timeAgo(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString();
}

// ── Component ────────────────────────────────────────────────────────────────

export default function BackendStore() {
  const [uploads, setUploads] = useState<UploadEntry[]>([]);
  const [callbacks, setCallbacks] = useState<CallbackEntry[]>([]);
  const [activeTab, setActiveTab] = useState<'uploads' | 'callbacks'>('uploads');
  const [expandedUpload, setExpandedUpload] = useState<string | null>(null);
  const [expandedCallback, setExpandedCallback] = useState<string | null>(null);
  const [textPreview, setTextPreview] = useState<Record<string, string>>({});
  const [autoRefresh, setAutoRefresh] = useState(true);

  // ── Fetch data ─────────────────────────────────────────────────────────

  const fetchData = useCallback(() => {
    Promise.all([
      fetch('/api/store/uploads').then((r) => r.json()),
      fetch('/api/store/callbacks').then((r) => r.json()),
    ])
      .then(([uploadsData, callbacksData]) => {
        setUploads(uploadsData.uploads || []);
        setCallbacks(callbacksData.callbacks || []);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    fetchData();
    if (!autoRefresh) return;
    const interval = setInterval(fetchData, 2000);
    return () => clearInterval(interval);
  }, [fetchData, autoRefresh]);

  // ── Load text preview ──────────────────────────────────────────────────

  const loadTextPreview = useCallback((uploadId: string) => {
    if (textPreview[uploadId]) return;
    fetch(`/api/store/uploads/${uploadId}/text`)
      .then((r) => r.text())
      .then((text) => {
        setTextPreview((prev) => ({ ...prev, [uploadId]: text }));
      })
      .catch(() => {
        setTextPreview((prev) => ({ ...prev, [uploadId]: '(failed to load)' }));
      });
  }, [textPreview]);

  // ── Toggle expanded ────────────────────────────────────────────────────

  const toggleUpload = useCallback((id: string) => {
    setExpandedUpload((prev) => {
      const newVal = prev === id ? null : id;
      if (newVal) {
        const entry = uploads.find((u) => u.id === id);
        if (entry?.isText) loadTextPreview(id);
      }
      return newVal;
    });
  }, [uploads, loadTextPreview]);

  const toggleCallback = useCallback((id: string) => {
    setExpandedCallback((prev) => (prev === id ? null : id));
  }, []);

  // ── Clear store ────────────────────────────────────────────────────────

  const handleClear = useCallback(() => {
    fetch('/api/store', { method: 'DELETE' }).then(() => {
      setUploads([]);
      setCallbacks([]);
      setTextPreview({});
    });
  }, []);

  // ── Render ─────────────────────────────────────────────────────────────

  return (
    <div className="store-page">
      <div className="store-header">
        <div className="store-title">
          <h2>📦 Backend Store</h2>
          <span className="store-subtitle">
            Everything the native host uploaded or called back to this server
          </span>
        </div>
        <div className="store-actions">
          <label className="store-auto-refresh">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
            />
            Auto-refresh
          </label>
          <button className="btn btn-sm btn-ghost" onClick={fetchData}>
            ⟳ Refresh
          </button>
          <button className="btn btn-sm btn-danger" onClick={handleClear}>
            🗑 Clear Store
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="store-tabs">
        <div
          className={`store-tab ${activeTab === 'uploads' ? 'active' : ''}`}
          onClick={() => setActiveTab('uploads')}
        >
          📤 Uploads
          <span className="count-badge">{uploads.length}</span>
        </div>
        <div
          className={`store-tab ${activeTab === 'callbacks' ? 'active' : ''}`}
          onClick={() => setActiveTab('callbacks')}
        >
          📡 Callbacks
          <span className="count-badge">{callbacks.length}</span>
        </div>
      </div>

      {/* Content */}
      <div className="store-content">
        {activeTab === 'uploads' && (
          <>
            {uploads.length === 0 ? (
              <div className="empty-state">
                <div className="icon">📤</div>
                <div>No uploads received yet</div>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Run a signing scenario and the native host will upload signed content here
                </div>
              </div>
            ) : (
              <div className="store-list">
                {/* Column header */}
                <div className="store-list-header">
                  <span className="col-id">Object ID</span>
                  <span className="col-type">Content-Type</span>
                  <span className="col-size">Size</span>
                  <span className="col-time">Time</span>
                  <span className="col-actions">Actions</span>
                </div>

                {[...uploads].reverse().map((u) => (
                  <div key={u.id} className="store-item">
                    <div
                      className="store-item-row"
                      onClick={() => toggleUpload(u.id)}
                    >
                      <span className="col-id">
                        <span className={`type-icon ${u.isPdf ? 'pdf' : u.isText ? 'text' : 'binary'}`}>
                          {u.isPdf ? '📄' : u.isText ? '📝' : '🔢'}
                        </span>
                        {u.objectId}
                      </span>
                      <span className="col-type">
                        <code>{u.contentType}</code>
                      </span>
                      <span className="col-size">{formatBytes(u.size)}</span>
                      <span className="col-time">{timeAgo(u.receivedAt)}</span>
                      <span className="col-actions">
                        <a
                          href={`/api/store/uploads/${u.id}/download`}
                          className="btn btn-sm btn-ghost"
                          onClick={(e) => e.stopPropagation()}
                          title="Download raw file"
                        >
                          ⬇ Download
                        </a>
                      </span>
                    </div>

                    {expandedUpload === u.id && (
                      <div className="store-item-detail">
                        <div className="detail-row">
                          <span className="detail-label">Endpoint:</span>
                          <code>{u.endpoint}?id={u.objectId}</code>
                        </div>
                        <div className="detail-row">
                          <span className="detail-label">Received:</span>
                          <span>{new Date(u.receivedAt).toLocaleString()}</span>
                        </div>
                        <div className="detail-row">
                          <span className="detail-label">Headers:</span>
                          <code>{JSON.stringify(u.headers, null, 2)}</code>
                        </div>

                        {u.isText && (
                          <div className="detail-preview">
                            <div className="detail-label">Content Preview:</div>
                            <pre className="preview-text">
                              {textPreview[u.id] ?? u.preview ?? 'Loading...'}
                            </pre>
                          </div>
                        )}

                        {u.isPdf && (
                          <div className="detail-preview">
                            <div className="detail-label">PDF Preview:</div>
                            <div className="pdf-preview-frame">
                              <object
                                data={`/api/store/uploads/${u.id}/preview`}
                                type="application/pdf"
                                style={{
                                  width: '100%',
                                  height: '500px',
                                  border: 'none',
                                  borderRadius: '4px',
                                  background: '#fff',
                                }}
                              >
                                <p style={{ padding: '16px', color: 'var(--text-muted)' }}>
                                  PDF preview not supported in this browser.{' '}
                                  <a href={`/api/store/uploads/${u.id}/download`}>Download</a> instead.
                                </p>
                              </object>
                            </div>
                          </div>
                        )}

                        {!u.isText && !u.isPdf && (
                          <div className="detail-preview">
                            <div className="detail-label">Binary content ({formatBytes(u.size)})</div>
                            <div style={{ color: 'var(--text-muted)', fontSize: '12px' }}>
                              Use the Download button to save this file
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </>
        )}

        {activeTab === 'callbacks' && (
          <>
            {callbacks.length === 0 ? (
              <div className="empty-state">
                <div className="icon">📡</div>
                <div>No callbacks received yet</div>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Callback payloads from the native host will appear here
                </div>
              </div>
            ) : (
              <div className="store-list">
                <div className="store-list-header">
                  <span className="col-id">Object ID</span>
                  <span className="col-type">Type</span>
                  <span className="col-size">Request ID</span>
                  <span className="col-time">Time</span>
                </div>

                {[...callbacks].reverse().map((c) => (
                  <div key={c.id} className="store-item">
                    <div
                      className="store-item-row"
                      onClick={() => toggleCallback(c.id)}
                    >
                      <span className="col-id">{c.objectId}</span>
                      <span className="col-type">
                        <span className={`callback-badge ${c.type}`}>
                          {c.type === 'success' ? '✓' : c.type === 'error' ? '✗' : '⟳'} {c.type}
                        </span>
                      </span>
                      <span className="col-size" style={{ fontFamily: 'var(--font-mono)', fontSize: '11px' }}>
                        {c.requestId.slice(0, 8)}...
                      </span>
                      <span className="col-time">{timeAgo(c.receivedAt)}</span>
                    </div>

                    {expandedCallback === c.id && (
                      <div className="store-item-detail">
                        <div className="detail-label">Full Callback Payload:</div>
                        <pre className="preview-text">
                          {JSON.stringify(c.payload, null, 2)}
                        </pre>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
