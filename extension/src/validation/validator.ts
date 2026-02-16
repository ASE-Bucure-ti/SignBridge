// =============================================================================
// SignBridge Request Validator
//
// Manual validation — no ajv dependency.
// MV3 Content Security Policy forbids `new Function()` / eval, which ajv
// relies on for schema compilation.  This module performs the same structural
// and semantic checks entirely in plain TypeScript.
// =============================================================================

import { SignRequest, ObjectGroup, SignObject } from '../types/protocol';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

const VALID_DATA_TYPES = ['text', 'xml', 'json', 'pdf', 'binary'];
const VALID_SIGNED_CONTENT_TYPES = ['string', 'pdf', 'xml', 'binary'];

/**
 * Validate an incoming signing request against the standard v1.0.
 * Returns a clean list of human-readable error strings.
 */
export function validateRequest(data: unknown): ValidationResult {
  // Guard: must be a non-null object
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    return { valid: false, errors: ['Request must be a JSON object'] };
  }

  const req = data as Record<string, unknown>;
  const errors: string[] = [];

  // Phase 1 — Structural checks
  validateStructure(req, errors);
  if (errors.length > 0) {
    return { valid: false, errors };
  }

  // Phase 2 — Semantic rules (URLs, placeholders, conditional requirements)
  const request = data as SignRequest;
  runSemanticChecks(request, errors);

  return {
    valid: errors.length === 0,
    errors,
  };
}

// ---------------------------------------------------------------------------
// Structural validation (replaces JSON Schema)
// ---------------------------------------------------------------------------

function validateStructure(req: Record<string, unknown>, errors: string[]): void {
  // Top-level required fields
  requireString(req, 'protocolVersion', errors);
  requireString(req, 'requestId', errors);
  requireString(req, 'appId', errors);

  // Protocol version
  if (typeof req.protocolVersion === 'string' && req.protocolVersion !== '1.0') {
    errors.push(`protocolVersion: must be "1.0", got "${req.protocolVersion}"`);
  }

  // cert
  if (!req.cert || typeof req.cert !== 'object' || Array.isArray(req.cert)) {
    errors.push('cert: required and must be an object');
  } else {
    const cert = req.cert as Record<string, unknown>;
    requireString(cert, 'certId', errors, 'cert.certId');
  }

  // metadata
  if (!req.metadata || typeof req.metadata !== 'object' || Array.isArray(req.metadata)) {
    errors.push('metadata: required and must be an object');
  }

  // objects XOR objectGroups
  const hasObjects = Array.isArray(req.objects);
  const hasGroups = Array.isArray(req.objectGroups);

  if (hasObjects && hasGroups) {
    errors.push('Request must have either "objects" or "objectGroups", not both');
    return;
  }
  if (!hasObjects && !hasGroups) {
    errors.push('Request must have either "objects" or "objectGroups"');
    return;
  }

  if (hasObjects) {
    const objects = req.objects as unknown[];
    if (objects.length === 0) {
      errors.push('objects: must contain at least 1 item');
    }
    for (let i = 0; i < objects.length; i++) {
      validateSignObjectStructure(objects[i], `objects[${i}]`, errors);
    }
  }

  if (hasGroups) {
    const groups = req.objectGroups as unknown[];
    if (groups.length === 0) {
      errors.push('objectGroups: must contain at least 1 item');
    }
    for (let i = 0; i < groups.length; i++) {
      validateObjectGroupStructure(groups[i], `objectGroups[${i}]`, errors);
    }
  }
}

function validateSignObjectStructure(obj: unknown, ctx: string, errors: string[]): void {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    errors.push(`${ctx}: must be an object`);
    return;
  }
  const o = obj as Record<string, unknown>;

  requireString(o, 'id', errors, `${ctx}.id`);
  requireEnum(o, 'dataType', VALID_DATA_TYPES, errors, `${ctx}.dataType`);

  // content
  if (!o.content || typeof o.content !== 'object' || Array.isArray(o.content)) {
    errors.push(`${ctx}.content: required and must be an object`);
  } else {
    const c = o.content as Record<string, unknown>;
    if (c.mode !== 'inline' && c.mode !== 'remote') {
      errors.push(`${ctx}.content.mode: must be "inline" or "remote"`);
    }
  }

  // upload
  validateUploadStructure(o.upload, `${ctx}.upload`, errors);

  // callbacks
  validateCallbacksStructure(o.callbacks, `${ctx}.callbacks`, errors);
}

function validateObjectGroupStructure(grp: unknown, ctx: string, errors: string[]): void {
  if (!grp || typeof grp !== 'object' || Array.isArray(grp)) {
    errors.push(`${ctx}: must be an object`);
    return;
  }
  const g = grp as Record<string, unknown>;

  requireEnum(g, 'dataType', VALID_DATA_TYPES, errors, `${ctx}.dataType`);
  requireEnum(g, 'mode', ['inline', 'remote'], errors, `${ctx}.mode`);

  // upload
  validateUploadStructure(g.upload, `${ctx}.upload`, errors);

  // callbacks
  validateCallbacksStructure(g.callbacks, `${ctx}.callbacks`, errors);

  // objects array
  if (!Array.isArray(g.objects)) {
    errors.push(`${ctx}.objects: required and must be an array`);
  } else if (g.objects.length === 0) {
    errors.push(`${ctx}.objects: must contain at least 1 item`);
  } else {
    for (let i = 0; i < g.objects.length; i++) {
      const item = g.objects[i] as Record<string, unknown> | null;
      if (!item || typeof item !== 'object') {
        errors.push(`${ctx}.objects[${i}]: must be an object`);
      } else if (typeof item.id !== 'string' || item.id.length === 0) {
        errors.push(`${ctx}.objects[${i}].id: required non-empty string`);
      }
    }
  }
}

function validateUploadStructure(upload: unknown, ctx: string, errors: string[]): void {
  if (!upload || typeof upload !== 'object' || Array.isArray(upload)) {
    errors.push(`${ctx}: required and must be an object`);
    return;
  }
  const u = upload as Record<string, unknown>;
  requireString(u, 'uploadUrl', errors, `${ctx}.uploadUrl`);
  requireEnum(u, 'signedContentType', VALID_SIGNED_CONTENT_TYPES, errors, `${ctx}.signedContentType`);
}

function validateCallbacksStructure(callbacks: unknown, ctx: string, errors: string[]): void {
  if (!callbacks || typeof callbacks !== 'object' || Array.isArray(callbacks)) {
    errors.push(`${ctx}: required and must be an object`);
    return;
  }
  const cb = callbacks as Record<string, unknown>;
  requireString(cb, 'onSuccess', errors, `${ctx}.onSuccess`);
  requireString(cb, 'onError', errors, `${ctx}.onError`);
}

// ---------------------------------------------------------------------------
// Helpers for structural checks
// ---------------------------------------------------------------------------

function requireString(
  obj: Record<string, unknown>,
  key: string,
  errors: string[],
  path?: string,
): void {
  const p = path ?? key;
  if (typeof obj[key] !== 'string' || (obj[key] as string).length === 0) {
    errors.push(`${p}: required non-empty string`);
  }
}

function requireEnum(
  obj: Record<string, unknown>,
  key: string,
  allowed: string[],
  errors: string[],
  path?: string,
): void {
  const p = path ?? key;
  const val = obj[key];
  if (typeof val !== 'string') {
    errors.push(`${p}: required string`);
  } else if (!allowed.includes(val)) {
    errors.push(`${p}: must be one of [${allowed.join(', ')}]`);
  }
}

// ---------------------------------------------------------------------------
// Semantic validation
// ---------------------------------------------------------------------------

function runSemanticChecks(request: SignRequest, errors: string[]): void {
  if (request.objects) {
    validateObjects(request.objects, errors);
  }

  if (request.objectGroups) {
    validateObjectGroups(request.objectGroups, errors);
  }

  // Unique IDs across the entire request
  validateUniqueIds(request, errors);
}

// --- Objects (non-grouped) -------------------------------------------------

function validateObjects(objects: SignObject[], errors: string[]): void {
  for (const obj of objects) {
    const ctx = `objects[${obj.id}]`;

    // Section 6.3 — pdfOptions required when dataType is "pdf"
    if (obj.dataType === 'pdf' && !obj.pdfOptions) {
      errors.push(`${ctx}: pdfOptions is required when dataType is "pdf"`);
    }

    // Section 6.4 — xmlOptions required when dataType is "xml"
    if (obj.dataType === 'xml' && !obj.xmlOptions) {
      errors.push(`${ctx}: xmlOptions is required when dataType is "xml"`);
    }

    // Section 4.2 — pdf/binary MUST use remote mode
    if ((obj.dataType === 'pdf' || obj.dataType === 'binary') && obj.content.mode !== 'remote') {
      errors.push(`${ctx}: dataType "${obj.dataType}" must use remote content mode`);
    }

    // Inline content must have required fields
    if (obj.content.mode === 'inline') {
      const inline = obj.content as any;
      if (!inline.content && inline.content !== '') {
        errors.push(`${ctx}.content: inline mode requires "content" field`);
      }
    }

    // Remote content must have downloadUrl
    if (obj.content.mode === 'remote') {
      const remote = obj.content as any;
      if (!remote.downloadUrl) {
        errors.push(`${ctx}.content: remote mode requires "downloadUrl" field`);
      }
    }

    // Upload URL must contain <objectId> (Section 8.1)
    validatePlaceholder(obj.upload.uploadUrl, `${ctx}.upload.uploadUrl`, errors);

    // All URLs must be HTTPS (Section 14.1)
    validateUrl(obj.upload.uploadUrl, `${ctx}.upload.uploadUrl`, errors);
    validateUrl(obj.callbacks.onSuccess, `${ctx}.callbacks.onSuccess`, errors);
    validateUrl(obj.callbacks.onError, `${ctx}.callbacks.onError`, errors);
    if (obj.callbacks.progress) {
      validateUrl(obj.callbacks.progress, `${ctx}.callbacks.progress`, errors);
    }

    if (obj.content.mode === 'remote') {
      const remote = obj.content as { downloadUrl: string };
      if (remote.downloadUrl) {
        validateUrl(remote.downloadUrl, `${ctx}.content.downloadUrl`, errors);
      }
    }
  }
}

// --- Object groups ---------------------------------------------------------

function validateObjectGroups(groups: ObjectGroup[], errors: string[]): void {
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    const ctx = `objectGroups[${i}]`;

    // Section 6.3 — pdfOptions required when dataType is "pdf"
    if (group.dataType === 'pdf' && !group.pdfOptions) {
      errors.push(`${ctx}: pdfOptions is required when dataType is "pdf"`);
    }

    // Section 6.4 — xmlOptions required when dataType is "xml"
    if (group.dataType === 'xml' && !group.xmlOptions) {
      errors.push(`${ctx}: xmlOptions is required when dataType is "xml"`);
    }

    // Section 7.5 Rule 3 — pdf/binary MUST use remote mode
    if ((group.dataType === 'pdf' || group.dataType === 'binary') && group.mode !== 'remote') {
      errors.push(`${ctx}: dataType "${group.dataType}" must use remote mode`);
    }

    // Section 7.3 — Remote mode requires downloadUrl with <objectId>
    if (group.mode === 'remote') {
      if (!group.downloadUrl) {
        errors.push(`${ctx}: remote mode requires "downloadUrl"`);
      } else {
        validateUrl(group.downloadUrl, `${ctx}.downloadUrl`, errors);
        validatePlaceholder(group.downloadUrl, `${ctx}.downloadUrl`, errors);
      }
    }

    // Inline mode — objects must have content
    if (group.mode === 'inline') {
      for (let j = 0; j < group.objects.length; j++) {
        const obj = group.objects[j] as any;
        if (!obj.content) {
          errors.push(`${ctx}.objects[${j}]: inline mode requires "content" field`);
        }
      }
    }

    // Upload URL must contain <objectId>
    validatePlaceholder(group.upload.uploadUrl, `${ctx}.upload.uploadUrl`, errors);

    // URLs must be HTTPS
    validateUrl(group.upload.uploadUrl, `${ctx}.upload.uploadUrl`, errors);
    validateUrl(group.callbacks.onSuccess, `${ctx}.callbacks.onSuccess`, errors);
    validateUrl(group.callbacks.onError, `${ctx}.callbacks.onError`, errors);
    if (group.callbacks.progress) {
      validateUrl(group.callbacks.progress, `${ctx}.callbacks.progress`, errors);
    }
  }
}

// --- Unique IDs ------------------------------------------------------------

function validateUniqueIds(request: SignRequest, errors: string[]): void {
  const ids: string[] = [];

  if (request.objects) {
    for (const obj of request.objects) ids.push(obj.id);
  }
  if (request.objectGroups) {
    for (const group of request.objectGroups) {
      for (const obj of group.objects) ids.push(obj.id);
    }
  }

  const seen = new Set<string>();
  for (const id of ids) {
    if (seen.has(id)) {
      errors.push(`Duplicate object ID: '${id}'`);
    }
    seen.add(id);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Section 14.1 — All URLs must use HTTPS.
 * Exception: http://localhost is allowed for development.
 */
function validateUrl(url: string, path: string, errors: string[]): void {
  try {
    // Replace placeholder so URL parsing doesn't choke on angle brackets
    const sanitized = url.replace(/<objectId>/g, '__placeholder__');
    const parsed = new URL(sanitized);

    const isHttps = parsed.protocol === 'https:';
    const isLocalhost =
      parsed.protocol === 'http:' &&
      (parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1');

    if (!isHttps && !isLocalhost) {
      errors.push(`${path}: URL must use HTTPS (got ${parsed.protocol})`);
    }
  } catch {
    errors.push(`${path}: invalid URL format`);
  }
}

/**
 * Section 8.1 / 7.2.2 — URLs that target individual objects MUST contain
 * the literal string "<objectId>" as a placeholder.
 */
function validatePlaceholder(url: string, path: string, errors: string[]): void {
  if (!url.includes('<objectId>')) {
    errors.push(`${path}: must contain the <objectId> placeholder`);
  }
}
