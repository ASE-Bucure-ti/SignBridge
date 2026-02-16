// =============================================================================
// SignBridge Test Scenarios
// Every scenario from the standard + additional edge-case / error scenarios.
// Each scenario is a factory function returning a ready-to-send SignRequest.
// =============================================================================

import { v4 as uuidv4 } from 'uuid';
import type { SignRequest } from '../../shared/protocol';

/** Base URL the mock backend is reachable at (via Vite proxy) */
const API = 'http://localhost:3001/api';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function id(): string {
  return uuidv4();
}

function callbacks(path: string, withProgress = true) {
  return {
    onSuccess: `${API}/callbacks/success`,
    onError: `${API}/callbacks/error`,
    ...(withProgress ? { progress: `${API}/callbacks/progress` } : {}),
    headers: { 'X-API-Key': 'test-api-key-12345' },
  };
}

function upload(endpoint: string, signedContentType: 'string' | 'pdf' | 'xml' | 'binary') {
  return {
    uploadUrl: `${API}/upload/${endpoint}?id=<objectId>`,
    httpMethod: 'POST' as const,
    headers: { 'X-API-Key': 'test-api-key-12345' },
    signedContentType,
  };
}

// =============================================================================
// Standard Example Scenarios (Section 12)
// =============================================================================

export interface TestScenario {
  id: string;
  name: string;
  description: string;
  category: 'standard' | 'validation' | 'error' | 'edge-case';
  /** Standard section reference */
  section?: string;
  /** Build the request (fresh UUID each time) */
  build: () => SignRequest;
  /** Expected outcome description */
  expectedOutcome: string;
}

// ─── Example A: Single PDF Document (Section 12.1) ──────────────────────────

const exampleA: TestScenario = {
  id: 'example-a',
  name: 'Example A — Single PDF',
  description:
    'Sign a single PDF document using the objects array. ' +
    'The native host downloads the PDF from downloadUrl, signs it via PKCS#11, ' +
    'uploads the signed PDF, and calls the success callback.',
  category: 'standard',
  section: '12.1',
  expectedOutcome: 'ACK status "accepted". Signing result for report-001 delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'student-portal',
    cert: { certId: '1B15EC34000000123D9B', label: 'University Signing Certificate' },
    metadata: { studentId: 'STU-2026-001', documentType: 'grade-report' },
    objects: [
      {
        id: 'report-001',
        dataType: 'pdf',
        content: {
          mode: 'remote',
          downloadUrl: `${API}/documents/download?id=report-001`,
          httpMethod: 'GET',
          headers: { 'X-API-Key': 'university-api-key-12345' },
        },
        pdfOptions: { label: 'Signature1' },
        upload: upload('signed-document', 'pdf'),
        callbacks: callbacks('pdf-sign'),
      },
    ],
  }),
};

// ─── Example B: Multiple Text Items via objectGroups (Section 12.2) ──────────

const exampleB: TestScenario = {
  id: 'example-b',
  name: 'Example B — Text Batch (Grades)',
  description:
    'Sign 3 student grade strings using objectGroups with inline mode. ' +
    'All grades share the same callbacks and upload config.',
  category: 'standard',
  section: '12.2',
  expectedOutcome: 'ACK status "accepted". 3 results (grade-STU001..003) delivered via callbacks.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'grades-system',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {
      batchId: 'BATCH-2026-CS101-FINAL',
      courseCode: 'CS101',
      semester: '2025-2026-S1',
      professorId: 'PROF-001',
    },
    objectGroups: [
      {
        dataType: 'text',
        mode: 'inline',
        callbacks: callbacks('grade-batch'),
        upload: upload('signed-grade', 'string'),
        objects: [
          { id: 'grade-STU001', content: { encoding: 'utf8' as const, value: 'STU001|CS101|2026-S1|A|95|PROF-001|2026-01-15' } },
          { id: 'grade-STU002', content: { encoding: 'utf8' as const, value: 'STU002|CS101|2026-S1|B+|87|PROF-001|2026-01-15' } },
          { id: 'grade-STU003', content: { encoding: 'utf8' as const, value: 'STU003|CS101|2026-S1|A-|91|PROF-001|2026-01-15' } },
        ],
      },
    ],
  }),
};

// ─── Example C: Mixed Batch — PDFs + Text (Section 12.3) ────────────────────

const exampleC: TestScenario = {
  id: 'example-c',
  name: 'Example C — Mixed Batch (PDF + Text)',
  description:
    'Two groups in one request: 2 PDF certificates (remote) and 3 text honor strings (inline). ' +
    'Exercises multiple objectGroups with different modes in the same request.',
  category: 'standard',
  section: '12.3',
  expectedOutcome: 'ACK status "accepted". 5 results delivered via callbacks.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'graduation-system',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { ceremony: 'GRAD-2026-SPRING', department: 'Computer Science' },
    objectGroups: [
      {
        dataType: 'pdf',
        mode: 'remote',
        downloadUrl: `${API}/documents/download?id=<objectId>`,
        downloadHeaders: { 'X-API-Key': 'grad-key-111' },
        pdfOptions: { label: 'Signature1' },
        callbacks: {
          onSuccess: `${API}/callbacks/success`,
          onError: `${API}/callbacks/error`,
          headers: { 'X-API-Key': 'grad-key-111' },
        },
        upload: upload('signed-document', 'pdf'),
        objects: [{ id: 'cert-STU001' }, { id: 'cert-STU002' }],
      },
      {
        dataType: 'text',
        mode: 'inline',
        callbacks: {
          onSuccess: `${API}/callbacks/success`,
          onError: `${API}/callbacks/error`,
          headers: { 'X-API-Key': 'grad-key-111' },
        },
        upload: upload('signed-content', 'string'),
        objects: [
          { id: 'honors-STU001', content: { encoding: 'utf8' as const, value: 'STU001|SUMMA_CUM_LAUDE|3.95|2026' } },
          { id: 'honors-STU002', content: { encoding: 'utf8' as const, value: 'STU002|MAGNA_CUM_LAUDE|3.82|2026' } },
          { id: 'honors-STU003', content: { encoding: 'utf8' as const, value: 'STU003|CUM_LAUDE|3.65|2026' } },
        ],
      },
    ],
  }),
};

// ─── Example D: Partial Failure (Section 12.4) ──────────────────────────────
// This request includes doc-002 which the mock server returns 404 for.

const exampleD: TestScenario = {
  id: 'example-d',
  name: 'Example D — Partial Failure',
  description:
    'Sign 3 PDF documents where doc-002 will fail to download (404). ' +
    'Expects a "partial" response with 2 successes and 1 error.',
  category: 'standard',
  section: '12.4',
  expectedOutcome: 'ACK status "accepted". doc-001/003 via success callbacks, doc-002 DOWNLOAD_FAILED via error callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'batch-system',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { batchId: 'batch-123' },
    objectGroups: [
      {
        dataType: 'pdf',
        mode: 'remote',
        downloadUrl: `${API}/documents/download?id=<objectId>`,
        downloadHeaders: { 'X-API-Key': 'batch-key-222' },
        pdfOptions: { label: 'Signature1' },
        callbacks: callbacks('batch-pdf'),
        upload: upload('signed-document', 'pdf'),
        objects: [{ id: 'doc-001' }, { id: 'doc-002' }, { id: 'doc-003' }],
      },
    ],
  }),
};

// ─── Example E: Bulk PDF Signing — 500 docs (Section 12.5) ──────────────────

const exampleE: TestScenario = {
  id: 'example-e',
  name: 'Example E — Bulk PDF (500 docs)',
  description:
    'Sign 500 PDF documents in a single request using objectGroups. ' +
    'Demonstrates the efficiency of group-level downloadUrl with <objectId> placeholder.',
  category: 'standard',
  section: '12.5',
  expectedOutcome: 'ACK status "accepted". 500 results delivered via callbacks.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'report-system',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { batchId: 'REPORTS-2026-SEMESTER1', totalDocuments: 500 },
    objectGroups: [
      {
        dataType: 'pdf',
        mode: 'remote',
        downloadUrl: `${API}/documents/download?id=<objectId>`,
        downloadHeaders: {
          'X-API-Key': 'reports-api-key-99999',
          Authorization: 'Bearer batch-token-xyz',
        },
        pdfOptions: { label: 'Signature1' },
        callbacks: callbacks('bulk-pdf'),
        upload: upload('signed-document', 'pdf'),
        objects: Array.from({ length: 500 }, (_, i) => ({
          id: `report-STU${String(i + 1).padStart(3, '0')}`,
        })),
      },
    ],
  }),
};

// =============================================================================
// Additional Data Type Scenarios
// =============================================================================

const inlineText: TestScenario = {
  id: 'inline-text-single',
  name: 'Single Inline Text',
  description: 'Sign a single inline text string using objects array.',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'text-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { type: 'receipt' },
    objects: [
      {
        id: 'txt-001',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'Receipt #12345 — Total: €150.00' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('text-sign'),
      },
    ],
  }),
};

const inlineXml: TestScenario = {
  id: 'inline-xml-single',
  name: 'Single Inline XML',
  description: 'Sign a single inline XML document. Requires xmlOptions with xpath.',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'xml-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { documentType: 'invoice-xml' },
    objects: [
      {
        id: 'xml-001',
        dataType: 'xml',
        content: {
          mode: 'inline',
          encoding: 'utf8' as const,
          content: '<?xml version="1.0"?><Invoice><Total>1500</Total><Signature/></Invoice>',
        },
        xmlOptions: { xpath: '//Invoice/Signature', idAttribute: 'Id' },
        upload: upload('signed-content', 'xml'),
        callbacks: callbacks('xml-sign'),
      },
    ],
  }),
};

const inlineJson: TestScenario = {
  id: 'inline-json-single',
  name: 'Single Inline JSON',
  description: 'Sign a single inline JSON document.',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'json-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { documentType: 'invoice-json' },
    objects: [
      {
        id: 'json-001',
        dataType: 'json',
        content: {
          mode: 'inline',
          encoding: 'utf8' as const,
          content: '{"invoiceNumber":"INV-001","amount":1500,"currency":"EUR"}',
        },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('json-sign'),
      },
    ],
  }),
};

const remotePdf: TestScenario = {
  id: 'remote-pdf-single',
  name: 'Single Remote PDF',
  description: 'Sign a single remote PDF using objects array (not groups).',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'pdf-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { documentType: 'contract' },
    objects: [
      {
        id: 'pdf-001',
        dataType: 'pdf',
        content: {
          mode: 'remote',
          downloadUrl: `${API}/documents/download?id=pdf-001`,
          httpMethod: 'GET',
          headers: { 'X-API-Key': 'pdf-api-key' },
        },
        pdfOptions: { label: 'Signature1' },
        upload: upload('signed-document', 'pdf'),
        callbacks: callbacks('pdf-sign'),
      },
    ],
  }),
};

const remoteBinary: TestScenario = {
  id: 'remote-binary-single',
  name: 'Single Remote Binary',
  description: 'Sign a single remote binary file.',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'binary-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { documentType: 'firmware' },
    objects: [
      {
        id: 'bin-001',
        dataType: 'binary',
        content: {
          mode: 'remote',
          downloadUrl: `${API}/documents/binary?id=bin-001`,
          httpMethod: 'GET',
        },
        upload: upload('signed-content', 'binary'),
        callbacks: callbacks('binary-sign'),
      },
    ],
  }),
};

const remoteXml: TestScenario = {
  id: 'remote-xml-single',
  name: 'Single Remote XML',
  description: 'Sign a remote XML document with xmlOptions.',
  category: 'standard',
  expectedOutcome: 'ACK status "accepted". Result delivered via callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'xml-remote-signer',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { documentType: 'report-xml' },
    objects: [
      {
        id: 'rxml-001',
        dataType: 'xml',
        content: {
          mode: 'remote',
          downloadUrl: `${API}/documents/xml?id=rxml-001`,
        },
        xmlOptions: { xpath: '//Document/Signature' },
        upload: upload('signed-content', 'xml'),
        callbacks: callbacks('xml-remote'),
      },
    ],
  }),
};

// =============================================================================
// Validation / Error Scenarios — Things the extension SHOULD reject
// =============================================================================

const missingProtocolVersion: TestScenario = {
  id: 'err-missing-version',
  name: 'Missing protocolVersion',
  description: 'Request without protocolVersion. Extension should reject with BAD_REQUEST.',
  category: 'validation',
  section: '3.1',
  expectedOutcome: 'Extension error: BAD_REQUEST — missing protocolVersion.',
  build: () => {
    const req = {
      requestId: id(),
      appId: 'test',
      cert: { certId: '1B15EC34000000123D9B' },
      metadata: {},
      objects: [
        {
          id: 'obj-1',
          dataType: 'text',
          content: { mode: 'inline', encoding: 'utf8', content: 'hello' },
          upload: upload('signed-content', 'string'),
          callbacks: callbacks('test'),
        },
      ],
    };
    // Intentionally omit protocolVersion
    return req as unknown as SignRequest;
  },
};

const unsupportedVersion: TestScenario = {
  id: 'err-unsupported-version',
  name: 'Unsupported protocolVersion',
  description: 'Request with protocolVersion "99.0". Extension should reject with UNSUPPORTED_VERSION.',
  category: 'validation',
  section: '3.3',
  expectedOutcome: 'Extension error: UNSUPPORTED_VERSION.',
  build: () => ({
    protocolVersion: '99.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'obj-1',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'test' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const missingRequestId: TestScenario = {
  id: 'err-missing-request-id',
  name: 'Missing requestId',
  description: 'Request without requestId. Extension should reject with BAD_REQUEST.',
  category: 'validation',
  section: '9.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — missing requestId.',
  build: () => {
    const req = {
      protocolVersion: '1.0',
      appId: 'test',
      cert: { certId: '1B15EC34000000123D9B' },
      metadata: {},
      objects: [
        {
          id: 'obj-1',
          dataType: 'text',
          content: { mode: 'inline', encoding: 'utf8', content: 'test' },
          upload: upload('signed-content', 'string'),
          callbacks: callbacks('test'),
        },
      ],
    };
    return req as unknown as SignRequest;
  },
};

const missingAppId: TestScenario = {
  id: 'err-missing-app-id',
  name: 'Missing appId',
  description: 'Request without appId.',
  category: 'validation',
  section: '9.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — missing appId.',
  build: () => {
    const req = {
      protocolVersion: '1.0',
      requestId: id(),
      cert: { certId: '1B15EC34000000123D9B' },
      metadata: {},
      objects: [
        {
          id: 'obj-1',
          dataType: 'text',
          content: { mode: 'inline', encoding: 'utf8', content: 'test' },
          upload: upload('signed-content', 'string'),
          callbacks: callbacks('test'),
        },
      ],
    };
    return req as unknown as SignRequest;
  },
};

const missingCert: TestScenario = {
  id: 'err-missing-cert',
  name: 'Missing cert object',
  description: 'Request without cert.',
  category: 'validation',
  section: '9.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — missing cert.',
  build: () => {
    const req = {
      protocolVersion: '1.0',
      requestId: id(),
      appId: 'test',
      metadata: {},
      objects: [
        {
          id: 'obj-1',
          dataType: 'text',
          content: { mode: 'inline', encoding: 'utf8', content: 'test' },
          upload: upload('signed-content', 'string'),
          callbacks: callbacks('test'),
        },
      ],
    };
    return req as unknown as SignRequest;
  },
};

const missingMetadata: TestScenario = {
  id: 'err-missing-metadata',
  name: 'Missing metadata',
  description: 'Request without metadata object.',
  category: 'validation',
  section: '9.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — missing metadata.',
  build: () => {
    const req = {
      protocolVersion: '1.0',
      requestId: id(),
      appId: 'test',
      cert: { certId: '1B15EC34000000123D9B' },
      objects: [
        {
          id: 'obj-1',
          dataType: 'text',
          content: { mode: 'inline', encoding: 'utf8', content: 'test' },
          upload: upload('signed-content', 'string'),
          callbacks: callbacks('test'),
        },
      ],
    };
    return req as unknown as SignRequest;
  },
};

const bothObjectsAndGroups: TestScenario = {
  id: 'err-both-objects-and-groups',
  name: 'Both objects AND objectGroups',
  description: 'Request with both objects and objectGroups. Violates Section 7.5 Rule 1.',
  category: 'validation',
  section: '7.5',
  expectedOutcome: 'Extension error: BAD_REQUEST — mutually exclusive.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'obj-1',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'test' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('test'),
      },
    ],
    objectGroups: [
      {
        dataType: 'text',
        mode: 'inline',
        callbacks: callbacks('test'),
        upload: upload('signed-content', 'string'),
        objects: [{ id: 'g-1', content: { encoding: 'utf8' as const, value: 'v' } }],
      },
    ],
  }),
};

const neitherObjectsNorGroups: TestScenario = {
  id: 'err-neither-objects-nor-groups',
  name: 'Neither objects nor objectGroups',
  description: 'Request with no objects and no objectGroups.',
  category: 'validation',
  section: '7.5',
  expectedOutcome: 'Extension error: BAD_REQUEST — must have objects or objectGroups.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
  }),
};

const inlinePdfForbidden: TestScenario = {
  id: 'err-inline-pdf',
  name: 'Inline PDF (forbidden)',
  description: 'PDF with inline mode — violates Section 4.2 (no inline binary).',
  category: 'validation',
  section: '4.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — PDF must use remote mode.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'pdf-inline',
        dataType: 'pdf',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'not real pdf' },
        pdfOptions: { label: 'Signature1' },
        upload: upload('signed-document', 'pdf'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const inlineBinaryForbidden: TestScenario = {
  id: 'err-inline-binary',
  name: 'Inline Binary (forbidden)',
  description: 'Binary with inline mode — violates Section 4.2.',
  category: 'validation',
  section: '4.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — binary must use remote mode.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'bin-inline',
        dataType: 'binary',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'not real binary' },
        upload: upload('signed-content', 'binary'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const pdfMissingPdfOptions: TestScenario = {
  id: 'err-pdf-missing-options',
  name: 'PDF without pdfOptions',
  description: 'PDF object missing required pdfOptions.',
  category: 'validation',
  section: '6.3',
  expectedOutcome: 'Extension error: BAD_REQUEST — pdfOptions required for pdf dataType.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'pdf-no-opts',
        dataType: 'pdf',
        content: {
          mode: 'remote',
          downloadUrl: `${API}/documents/download?id=pdf-no-opts`,
        },
        // pdfOptions omitted — should fail
        upload: upload('signed-document', 'pdf'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const xmlMissingXmlOptions: TestScenario = {
  id: 'err-xml-missing-options',
  name: 'XML without xmlOptions',
  description: 'XML object missing required xmlOptions.',
  category: 'validation',
  section: '6.4',
  expectedOutcome: 'Extension error: BAD_REQUEST — xmlOptions required for xml dataType.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'xml-no-opts',
        dataType: 'xml',
        content: {
          mode: 'inline',
          encoding: 'utf8' as const,
          content: '<root/>',
        },
        // xmlOptions omitted — should fail
        upload: upload('signed-content', 'xml'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const duplicateObjectIds: TestScenario = {
  id: 'err-duplicate-ids',
  name: 'Duplicate object IDs',
  description: 'Two objects with the same ID. Should fail semantic validation.',
  category: 'validation',
  expectedOutcome: 'Extension error: BAD_REQUEST — duplicate object IDs.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'obj-SAME',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'first' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('test'),
      },
      {
        id: 'obj-SAME',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'second' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const missingUploadUrlPlaceholder: TestScenario = {
  id: 'err-upload-no-placeholder',
  name: 'Upload URL missing <objectId>',
  description: 'uploadUrl without the required <objectId> placeholder.',
  category: 'validation',
  section: '8.1',
  expectedOutcome: 'Extension error: BAD_REQUEST — uploadUrl must contain <objectId>.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'obj-1',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'test' },
        upload: {
          uploadUrl: `${API}/upload/signed-content?id=HARDCODED`,
          signedContentType: 'string' as const,
        },
        callbacks: callbacks('test'),
      },
    ],
  }),
};

const missingDownloadUrlPlaceholder: TestScenario = {
  id: 'err-download-no-placeholder',
  name: 'Group downloadUrl missing <objectId>',
  description: 'Remote group downloadUrl without <objectId> placeholder.',
  category: 'validation',
  section: '7.2.2',
  expectedOutcome: 'Extension error: BAD_REQUEST — downloadUrl must contain <objectId>.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objectGroups: [
      {
        dataType: 'pdf',
        mode: 'remote',
        downloadUrl: `${API}/documents/download?id=HARDCODED`,
        pdfOptions: { label: 'Signature1' },
        callbacks: callbacks('test'),
        upload: upload('signed-document', 'pdf'),
        objects: [{ id: 'doc-1' }, { id: 'doc-2' }],
      },
    ],
  }),
};

// =============================================================================
// Edge-Case Scenarios
// =============================================================================

const emptyMetadata: TestScenario = {
  id: 'edge-empty-metadata',
  name: 'Empty metadata object',
  description: 'Valid request with metadata: {} — the standard says it can be empty.',
  category: 'edge-case',
  section: '9.4',
  expectedOutcome: 'ACK "accepted". metadata is required but can be empty.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'obj-1',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'test data' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('edge'),
      },
    ],
  }),
};

const singleObjectInGroup: TestScenario = {
  id: 'edge-single-in-group',
  name: 'Single object in objectGroup',
  description: 'objectGroups with only 1 object. Valid per standard (Section 7.5 table).',
  category: 'edge-case',
  section: '7.5',
  expectedOutcome: 'ACK "accepted". Single item in group is valid.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'test-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { note: 'single item in group' },
    objectGroups: [
      {
        dataType: 'text',
        mode: 'inline',
        callbacks: callbacks('edge'),
        upload: upload('signed-content', 'string'),
        objects: [{ id: 'solo-1', content: { encoding: 'utf8' as const, value: 'lone item' } }],
      },
    ],
  }),
};

const withCorrelationId: TestScenario = {
  id: 'edge-correlation-id',
  name: 'With correlationId',
  description: 'Request that includes the optional correlationId for cross-system tracing.',
  category: 'edge-case',
  section: '9.2',
  expectedOutcome: 'ACK "accepted". correlationId is optional.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    correlationId: `trace-${id()}`,
    appId: 'tracing-app',
    cert: { certId: '1B15EC34000000123D9B', label: 'My Cert' },
    metadata: { traceId: 'abc-123' },
    objects: [
      {
        id: 'traced-obj',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'traced content' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('edge'),
      },
    ],
  }),
};

const noProgressCallback: TestScenario = {
  id: 'edge-no-progress',
  name: 'No progress callback',
  description: 'Request without optional progress callback URL.',
  category: 'edge-case',
  section: '8.4',
  expectedOutcome: 'ACK "accepted". progress is optional per Section 8.4.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'no-progress-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'np-obj',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'no progress tracking' },
        upload: upload('signed-content', 'string'),
        callbacks: callbacks('edge', false), // no progress URL
      },
    ],
  }),
};

const failingProgressEndpoint: TestScenario = {
  id: 'edge-failing-progress',
  name: 'Failing progress endpoint',
  description:
    'Request with progress URL that returns 503. Per Section 8.6, native host should ' +
    'cancel signing and report PROGRESS_ENDPOINT_FAILED.',
  category: 'edge-case',
  section: '8.6',
  expectedOutcome: 'ACK "accepted". PROGRESS_ENDPOINT_FAILED delivered via error callback.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'progress-fail-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objects: [
      {
        id: 'pf-obj',
        dataType: 'text',
        content: { mode: 'inline', encoding: 'utf8' as const, content: 'will fail progress' },
        upload: upload('signed-content', 'string'),
        callbacks: {
          onSuccess: `${API}/callbacks/success`,
          onError: `${API}/callbacks/error`,
          progress: `${API}/callbacks/progress-failing`,
          headers: { 'X-API-Key': 'test-key' },
        },
      },
    ],
  }),
};

const remoteTextInGroup: TestScenario = {
  id: 'edge-remote-text-group',
  name: 'Remote text in objectGroup',
  description: 'Text objects in a group with remote mode (valid — text can be remote).',
  category: 'edge-case',
  section: '4.1',
  expectedOutcome: 'ACK "accepted". Text supports both inline and remote modes.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'remote-text-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: {},
    objectGroups: [
      {
        dataType: 'text',
        mode: 'remote',
        downloadUrl: `${API}/documents/text?id=<objectId>`,
        downloadHeaders: { 'X-API-Key': 'test-key' },
        callbacks: callbacks('edge'),
        upload: upload('signed-content', 'string'),
        objects: [{ id: 'grade-STU001' }, { id: 'grade-STU002' }],
      },
    ],
  }),
};

const multipleGroups: TestScenario = {
  id: 'edge-multiple-groups',
  name: 'Multiple objectGroups (3 groups)',
  description:
    'Three groups in one request: PDFs (remote), text (inline), XML (inline). ' +
    'Tests that the extension and host can handle multiple groups.',
  category: 'edge-case',
  expectedOutcome: 'ACK "accepted". Multiple groups are valid per Section 7.5.',
  build: () => ({
    protocolVersion: '1.0',
    requestId: id(),
    appId: 'multi-group-app',
    cert: { certId: '1B15EC34000000123D9B' },
    metadata: { testType: 'multi-group' },
    objectGroups: [
      {
        dataType: 'pdf',
        mode: 'remote',
        downloadUrl: `${API}/documents/download?id=<objectId>`,
        pdfOptions: { label: 'Signature1' },
        callbacks: callbacks('multi'),
        upload: upload('signed-document', 'pdf'),
        objects: [{ id: 'mg-pdf-1' }, { id: 'mg-pdf-2' }],
      },
      {
        dataType: 'text',
        mode: 'inline',
        callbacks: callbacks('multi'),
        upload: upload('signed-content', 'string'),
        objects: [
          { id: 'mg-txt-1', content: { encoding: 'utf8' as const, value: 'text item 1' } },
          { id: 'mg-txt-2', content: { encoding: 'utf8' as const, value: 'text item 2' } },
        ],
      },
      {
        dataType: 'xml',
        mode: 'inline',
        xmlOptions: { xpath: '//Root/Signature' },
        callbacks: callbacks('multi'),
        upload: upload('signed-content', 'xml'),
        objects: [
          { id: 'mg-xml-1', content: { encoding: 'utf8' as const, value: '<Root><Signature/></Root>' } },
        ],
      },
    ],
  }),
};

// =============================================================================
// Export All Scenarios
// =============================================================================

export const ALL_SCENARIOS: TestScenario[] = [
  // Standard examples
  exampleA,
  exampleB,
  exampleC,
  exampleD,
  exampleE,
  // Data type coverage
  inlineText,
  inlineXml,
  inlineJson,
  remotePdf,
  remoteBinary,
  remoteXml,
  // Validation / error scenarios
  missingProtocolVersion,
  unsupportedVersion,
  missingRequestId,
  missingAppId,
  missingCert,
  missingMetadata,
  bothObjectsAndGroups,
  neitherObjectsNorGroups,
  inlinePdfForbidden,
  inlineBinaryForbidden,
  pdfMissingPdfOptions,
  xmlMissingXmlOptions,
  duplicateObjectIds,
  missingUploadUrlPlaceholder,
  missingDownloadUrlPlaceholder,
  // Edge cases
  emptyMetadata,
  singleObjectInGroup,
  withCorrelationId,
  noProgressCallback,
  failingProgressEndpoint,
  remoteTextInGroup,
  multipleGroups,
];

export const SCENARIOS_BY_CATEGORY = {
  standard: ALL_SCENARIOS.filter((s) => s.category === 'standard'),
  validation: ALL_SCENARIOS.filter((s) => s.category === 'validation'),
  error: ALL_SCENARIOS.filter((s) => s.category === 'error'),
  'edge-case': ALL_SCENARIOS.filter((s) => s.category === 'edge-case'),
};

export default ALL_SCENARIOS;
