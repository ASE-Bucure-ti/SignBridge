// =============================================================================
// SignBridge Constants — derived from Standard v1.0.2
// =============================================================================

/** Current protocol version (Section 3.1) */
export const PROTOCOL_VERSION = '1.0';

/** Native messaging host identifier */
export const NATIVE_HOST_NAME = 'com.ase.signer';

// ---------------------------------------------------------------------------
// postMessage type discriminators (Web App ↔ Content Script)
// ---------------------------------------------------------------------------

export const MSG_SIGN_REQUEST = 'HSM_SIGN_REQUEST';
export const MSG_SIGN_RESPONSE = 'HSM_SIGN_RESPONSE';

// ---------------------------------------------------------------------------
// Internal message type (Content Script ↔ Background Service Worker)
// ---------------------------------------------------------------------------

export const INTERNAL_SIGN_REQUEST = 'SIGNBRIDGE_SIGN_REQUEST';

// ---------------------------------------------------------------------------
// chrome.storage keys
// ---------------------------------------------------------------------------

export const STORAGE_ALLOWED_ORIGINS = 'allowedOrigins';

// ---------------------------------------------------------------------------
// Section 4.1 — Supported data types
// ---------------------------------------------------------------------------

export const DATA_TYPES = ['text', 'xml', 'json', 'pdf', 'binary'] as const;

/** Data types that MUST use remote mode (Section 4.2) */
export const BINARY_ONLY_TYPES = ['pdf', 'binary'] as const;

// ---------------------------------------------------------------------------
// Section 8.2 — Signed content types
// ---------------------------------------------------------------------------

export const SIGNED_CONTENT_TYPES = ['string', 'pdf', 'xml', 'binary'] as const;

// ---------------------------------------------------------------------------
// Section 13.1 — Error codes
// ---------------------------------------------------------------------------

export const ERROR_CODES = {
  BAD_REQUEST: 'BAD_REQUEST',
  UNSUPPORTED_VERSION: 'UNSUPPORTED_VERSION',
  UNSUPPORTED_TYPE: 'UNSUPPORTED_TYPE',
  CERT_NOT_FOUND: 'CERT_NOT_FOUND',
  DOWNLOAD_FAILED: 'DOWNLOAD_FAILED',
  SIGN_FAILED: 'SIGN_FAILED',
  UPLOAD_FAILED: 'UPLOAD_FAILED',
  CALLBACK_FAILED: 'CALLBACK_FAILED',
  PROGRESS_ENDPOINT_FAILED: 'PROGRESS_ENDPOINT_FAILED',
  TIMEOUT: 'TIMEOUT',
  CANCELLED_BY_USER: 'CANCELLED_BY_USER',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
} as const;
