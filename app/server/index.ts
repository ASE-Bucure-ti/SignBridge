// =============================================================================
// SignBridge Mock Backend Server
// Simulates ALL endpoints required by the standard:
//   - Download endpoints  (serve test documents as raw bytes)
//   - Upload endpoints    (accept raw bytes POST)
//   - Callback endpoints  (onSuccess / onError / progress)
//   - Event log API       (for the frontend to poll)
// =============================================================================

import express from 'express';
import cors from 'cors';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import type {
  ProgressCallbackPayload,
  SuccessCallbackPayload,
  ErrorCallbackPayload,
} from '../shared/protocol';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
const PORT = 3001;

// ── State ────────────────────────────────────────────────────────────────────
interface EventLogEntry {
  id: string;
  timestamp: string;
  category: 'download' | 'upload' | 'callback-success' | 'callback-error' | 'callback-progress';
  objectId?: string;
  requestId?: string;
  details: Record<string, unknown>;
}

interface StoredUpload {
  id: string;
  objectId: string;
  receivedAt: string;
  contentType: string;
  size: number;
  data: Buffer;
  endpoint: string;
  headers: Record<string, string>;
}

interface StoredCallback {
  id: string;
  objectId: string;
  requestId: string;
  receivedAt: string;
  type: 'success' | 'error' | 'progress';
  payload: Record<string, unknown>;
}

let eventLog: EventLogEntry[] = [];
let nextEventId = 1;
let uploadStore: StoredUpload[] = [];
let nextUploadId = 1;
let callbackStore: StoredCallback[] = [];
let nextCallbackId = 1;

function logEvent(
  category: EventLogEntry['category'],
  objectId: string | undefined,
  requestId: string | undefined,
  details: Record<string, unknown>,
): void {
  eventLog.push({
    id: String(nextEventId++),
    timestamp: new Date().toISOString(),
    category,
    objectId,
    requestId,
    details,
  });
}

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors());
// For callback JSON bodies
app.use('/api/callbacks', express.json());
// For upload endpoints: accept raw bytes
app.use('/api/upload', express.raw({ type: '*/*', limit: '50mb' }));

// ── Test Document Data ───────────────────────────────────────────────────────
// These simulate the documents a real server would serve.

// Load the real test PDF (with AcroForm 'Signature1' field) from fixtures
const SAMPLE_PDF = readFileSync(join(__dirname, 'fixtures', 'test-document.pdf'));

const SAMPLE_TEXT: Record<string, string> = {
  'grade-STU001': 'STU001|CS101|2026-S1|A|95|PROF-001|2026-01-15',
  'grade-STU002': 'STU002|CS101|2026-S1|B+|87|PROF-001|2026-01-15',
  'grade-STU003': 'STU003|CS101|2026-S1|A-|91|PROF-001|2026-01-15',
  'honors-STU001': 'STU001|SUMMA_CUM_LAUDE|3.95|2026',
  'honors-STU002': 'STU002|MAGNA_CUM_LAUDE|3.82|2026',
  'honors-STU003': 'STU003|CUM_LAUDE|3.65|2026',
};

const SAMPLE_XML = `<?xml version="1.0" encoding="UTF-8"?>
<Document>
  <Header>
    <Title>Test Report</Title>
    <Date>2026-01-20</Date>
  </Header>
  <Body>
    <Section id="s1">
      <Paragraph>This is a sample document for XML signing.</Paragraph>
    </Section>
  </Body>
  <Signature Id="sig-placeholder"/>
</Document>`;

const SAMPLE_JSON = JSON.stringify({
  type: 'invoice',
  invoiceNumber: 'INV-2026-001',
  amount: 1500.0,
  currency: 'EUR',
  items: [
    { description: 'Consulting', qty: 10, unitPrice: 150.0 },
  ],
});

const SAMPLE_BINARY = Buffer.from(
  Array.from({ length: 256 }, (_, i) => i),
);

// ── Download Endpoints (Section 5.3 / 5.4) ──────────────────────────────────
// The standard requires raw bytes responses with proper Content-Type.

// PDF download — used by single-object and group-remote scenarios
app.get('/api/documents/download', (req, res) => {
  const id = req.query.id as string;
  if (!id) {
    res.status(400).send('Missing id parameter');
    return;
  }

  logEvent('download', id, undefined, { method: 'GET', query: req.query });

  // Simulate a 404 for a specific ID (test error handling)
  if (id === 'doc-MISSING' || id === 'doc-002') {
    res.status(404).send('Document not found');
    return;
  }

  // Simulate slow download for a specific ID
  if (id === 'doc-SLOW') {
    setTimeout(() => {
      res.setHeader('Content-Type', 'application/pdf');
      res.send(SAMPLE_PDF);
    }, 5000);
    return;
  }

  res.setHeader('Content-Type', 'application/pdf');
  res.send(SAMPLE_PDF);
});

// Text / JSON download (for remote text scenarios)
app.get('/api/documents/text', (req, res) => {
  const id = req.query.id as string;
  if (!id) {
    res.status(400).send('Missing id parameter');
    return;
  }

  logEvent('download', id, undefined, { method: 'GET', type: 'text' });

  const content = SAMPLE_TEXT[id];
  if (!content) {
    res.status(404).send('Text not found');
    return;
  }

  res.setHeader('Content-Type', 'text/plain');
  res.send(content);
});

// XML download
app.get('/api/documents/xml', (req, res) => {
  const id = req.query.id as string;
  logEvent('download', id, undefined, { method: 'GET', type: 'xml' });
  res.setHeader('Content-Type', 'application/xml');
  res.send(SAMPLE_XML);
});

// JSON download
app.get('/api/documents/json', (req, res) => {
  const id = req.query.id as string;
  logEvent('download', id, undefined, { method: 'GET', type: 'json' });
  res.setHeader('Content-Type', 'application/json');
  res.send(SAMPLE_JSON);
});

// Binary download
app.get('/api/documents/binary', (req, res) => {
  const id = req.query.id as string;
  logEvent('download', id, undefined, { method: 'GET', type: 'binary' });
  res.setHeader('Content-Type', 'application/octet-stream');
  res.send(SAMPLE_BINARY);
});

// ── Upload Endpoints (Section 8.3) ───────────────────────────────────────────
// Accept raw bytes POST with <objectId> in query.

function storeUpload(objectId: string, req: express.Request, endpoint: string): StoredUpload {
  const buf = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body || '');
  const entry: StoredUpload = {
    id: String(nextUploadId++),
    objectId,
    receivedAt: new Date().toISOString(),
    contentType: (req.headers['content-type'] as string) || 'unknown',
    size: buf.length,
    data: buf,
    endpoint,
    headers: Object.fromEntries(
      Object.entries(req.headers)
        .filter(([k]) => !['host', 'connection', 'content-length', 'accept'].includes(k))
        .map(([k, v]) => [k, String(v)])
    ),
  };
  uploadStore.push(entry);
  return entry;
}

app.post('/api/upload/signed-document', (req, res) => {
  const id = req.query.id as string;
  if (!id) {
    res.status(400).json({ error: 'Missing id parameter' });
    return;
  }

  // Simulate upload failure for specific ID
  if (id === 'upload-FAIL') {
    res.status(500).json({ error: 'Storage backend unavailable' });
    return;
  }

  const stored = storeUpload(id, req, '/api/upload/signed-document');
  logEvent('upload', id, undefined, {
    method: 'POST',
    contentType: stored.contentType,
    bodySize: stored.size,
    storeId: stored.id,
  });

  res.status(200).json({
    status: 'received',
    documentId: `DOC-${id}`,
    size: stored.size,
  });
});

// Text / string upload
app.post('/api/upload/signed-grade', (req, res) => {
  const id = req.query.id as string;
  const stored = storeUpload(id, req, '/api/upload/signed-grade');

  logEvent('upload', id, undefined, {
    method: 'POST',
    contentType: stored.contentType,
    bodySize: stored.size,
    storeId: stored.id,
  });

  res.status(200).json({
    gradeId: id,
    status: 'signed',
    size: stored.size,
  });
});

// Generic upload (for honors, xml, binary, etc.)
app.post('/api/upload/signed-content', (req, res) => {
  const id = req.query.id as string;
  const stored = storeUpload(id, req, '/api/upload/signed-content');

  logEvent('upload', id, undefined, {
    method: 'POST',
    contentType: stored.contentType,
    bodySize: stored.size,
    storeId: stored.id,
  });

  res.status(200).json({
    objectId: id,
    status: 'received',
    size: stored.size,
  });
});

// ── Callback Endpoints (Section 8.5) ─────────────────────────────────────────

// Success callback
app.post('/api/callbacks/success', (req, res) => {
  const payload = req.body as SuccessCallbackPayload;
  callbackStore.push({
    id: String(nextCallbackId++),
    objectId: payload.objectId,
    requestId: payload.requestId,
    receivedAt: new Date().toISOString(),
    type: 'success',
    payload: payload as unknown as Record<string, unknown>,
  });
  logEvent('callback-success', payload.objectId, payload.requestId, {
    uploadResult: payload.uploadResult,
    timestamp: payload.timestamp,
    metadata: payload.metadata,
  });
  res.status(200).json({ received: true });
});

// Error callback
app.post('/api/callbacks/error', (req, res) => {
  const payload = req.body as ErrorCallbackPayload;
  callbackStore.push({
    id: String(nextCallbackId++),
    objectId: payload.objectId,
    requestId: payload.requestId,
    receivedAt: new Date().toISOString(),
    type: 'error',
    payload: payload as unknown as Record<string, unknown>,
  });
  logEvent('callback-error', payload.objectId, payload.requestId, {
    error: payload.error,
    timestamp: payload.timestamp,
    metadata: payload.metadata,
  });
  res.status(200).json({ received: true });
});

// Progress callback
app.post('/api/callbacks/progress', (req, res) => {
  const payload = req.body as ProgressCallbackPayload;
  callbackStore.push({
    id: String(nextCallbackId++),
    objectId: payload.objectId,
    requestId: payload.requestId,
    receivedAt: new Date().toISOString(),
    type: 'progress',
    payload: payload as unknown as Record<string, unknown>,
  });
  logEvent('callback-progress', payload.objectId, payload.requestId, {
    status: payload.status,
    percentComplete: payload.percentComplete,
    message: payload.message,
    metadata: payload.metadata,
  });
  res.status(200).json({ received: true });
});

// Failing progress endpoint — simulates PROGRESS_ENDPOINT_FAILED
app.post('/api/callbacks/progress-failing', (_req, res) => {
  res.status(503).json({ error: 'Service temporarily unavailable' });
});

// ── Event Log API (for the frontend) ─────────────────────────────────────────

app.get('/api/events', (_req, res) => {
  res.json({ events: eventLog, total: eventLog.length });
});

app.get('/api/events/since/:id', (req, res) => {
  const sinceId = parseInt(req.params.id, 10);
  const newEvents = eventLog.filter((e) => parseInt(e.id, 10) > sinceId);
  res.json({ events: newEvents, total: eventLog.length });
});

app.delete('/api/events', (_req, res) => {
  eventLog = [];
  nextEventId = 1;
  res.json({ cleared: true });
});

// ── Store API (browse uploaded content + callbacks) ──────────────────────────

// List all uploads (metadata only, no binary data)
app.get('/api/store/uploads', (_req, res) => {
  const items = uploadStore.map(({ data, ...meta }) => ({
    ...meta,
    preview: data.length <= 4096 ? data.toString('utf-8').slice(0, 500) : null,
    isText: meta.contentType.includes('text') || meta.contentType.includes('json') || meta.contentType.includes('xml'),
    isPdf: meta.contentType.includes('pdf'),
  }));
  res.json({ uploads: items, total: items.length });
});

// Download a specific uploaded file (raw bytes)
app.get('/api/store/uploads/:id/download', (req, res) => {
  const entry = uploadStore.find((u) => u.id === req.params.id);
  if (!entry) {
    res.status(404).json({ error: 'Upload not found' });
    return;
  }
  const ext = entry.contentType.includes('pdf') ? 'pdf'
    : entry.contentType.includes('xml') ? 'xml'
    : entry.contentType.includes('json') ? 'json'
    : 'bin';
  res.setHeader('Content-Type', entry.contentType);
  res.setHeader('Content-Disposition', `attachment; filename="${entry.objectId}.${ext}"`);
  res.setHeader('Content-Length', String(entry.data.length));
  res.send(entry.data);
});

// Inline preview for PDFs (renders in browser instead of downloading)
app.get('/api/store/uploads/:id/preview', (req, res) => {
  const entry = uploadStore.find((u) => u.id === req.params.id);
  if (!entry) {
    res.status(404).json({ error: 'Upload not found' });
    return;
  }
  res.setHeader('Content-Type', entry.contentType);
  res.setHeader('Content-Disposition', 'inline');
  res.setHeader('Content-Length', String(entry.data.length));
  res.send(entry.data);
});

// View upload as text (for text/string/xml/json)
app.get('/api/store/uploads/:id/text', (req, res) => {
  const entry = uploadStore.find((u) => u.id === req.params.id);
  if (!entry) {
    res.status(404).json({ error: 'Upload not found' });
    return;
  }
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.send(entry.data.toString('utf-8'));
});

// List all callbacks
app.get('/api/store/callbacks', (_req, res) => {
  res.json({ callbacks: callbackStore, total: callbackStore.length });
});

// Clear store
app.delete('/api/store', (_req, res) => {
  uploadStore = [];
  nextUploadId = 1;
  callbackStore = [];
  nextCallbackId = 1;
  res.json({ cleared: true });
});

// ── Health Check ─────────────────────────────────────────────────────────────
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    server: 'SignBridge Mock Backend',
    version: '1.0.0',
    endpoints: {
      download: [
        'GET /api/documents/download?id=<objectId>',
        'GET /api/documents/text?id=<objectId>',
        'GET /api/documents/xml?id=<objectId>',
        'GET /api/documents/json?id=<objectId>',
        'GET /api/documents/binary?id=<objectId>',
      ],
      upload: [
        'POST /api/upload/signed-document?id=<objectId>',
        'POST /api/upload/signed-grade?id=<objectId>',
        'POST /api/upload/signed-content?id=<objectId>',
      ],
      callbacks: [
        'POST /api/callbacks/success',
        'POST /api/callbacks/error',
        'POST /api/callbacks/progress',
        'POST /api/callbacks/progress-failing',
      ],
      events: [
        'GET  /api/events',
        'GET  /api/events/since/:id',
        'DELETE /api/events',
      ],
      store: [
        'GET  /api/store/uploads',
        'GET  /api/store/uploads/:id/download',
        'GET  /api/store/uploads/:id/text',
        'GET  /api/store/callbacks',
        'DELETE /api/store',
      ],
    },
  });
});

// ── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n🟢 SignBridge Mock Backend running on http://localhost:${PORT}`);
  console.log(`   Health check: http://localhost:${PORT}/api/health\n`);
});

export default app;
