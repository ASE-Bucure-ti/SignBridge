// =============================================================================
// SignBridge Protocol Types — Generic Web HSM Signing Protocol v1.0
// Derived from STANDARD_v1.0.3 (fire-and-forget acknowledgment model)
// =============================================================================

// ---------------------------------------------------------------------------
// Section 4: Data Types
// ---------------------------------------------------------------------------

/** Supported content types for signing (Section 4.1) */
export type DataType = 'text' | 'xml' | 'json' | 'pdf' | 'binary';

/** Signed output content types (Section 8.2) */
export type SignedContentType = 'string' | 'pdf' | 'xml' | 'binary';

// ---------------------------------------------------------------------------
// Section 5: Content Representation
// ---------------------------------------------------------------------------

/** Inline content — text/xml/json only, under 1 MB (Section 5.2) */
export interface InlineContent {
  mode: 'inline';
  encoding: 'utf8';
  content: string;
}

/** Remote content — required for pdf/binary (Section 5.3) */
export interface RemoteContent {
  mode: 'remote';
  downloadUrl: string;
  httpMethod?: string;
  headers?: Record<string, string>;
}

export type ContentDefinition = InlineContent | RemoteContent;

// ---------------------------------------------------------------------------
// Section 6: Object Structure
// ---------------------------------------------------------------------------

/** PDF-specific options (Section 6.3) */
export interface PdfOptions {
  label: string;
}

/** XML-specific options (Section 6.4) */
export interface XmlOptions {
  xpath: string;
  idAttribute?: string;
}

// ---------------------------------------------------------------------------
// Section 8: Delivery and Callbacks
// ---------------------------------------------------------------------------

/** Upload configuration (Section 8.1) */
export interface UploadConfig {
  uploadUrl: string;
  httpMethod?: string;
  headers?: Record<string, string>;
  signedContentType: SignedContentType;
}

/** Callback endpoints (Section 8.4) */
export interface CallbacksConfig {
  onSuccess: string;
  onError: string;
  progress?: string;
  headers?: Record<string, string>;
}

// ---------------------------------------------------------------------------
// Section 6: Single Object (used in `objects` array)
// ---------------------------------------------------------------------------

export interface SignObject {
  id: string;
  dataType: DataType;
  content: ContentDefinition;
  pdfOptions?: PdfOptions;
  xmlOptions?: XmlOptions;
  upload: UploadConfig;
  callbacks: CallbacksConfig;
}

// ---------------------------------------------------------------------------
// Section 7: Object Grouping
// ---------------------------------------------------------------------------

/** Inline grouped object — carries its own content (Section 7.4) */
export interface InlineGroupedObject {
  id: string;
  content: {
    encoding: 'utf8';
    value: string;
  };
}

/** Remote grouped object — ID only, URL built from template (Section 7.4) */
export interface RemoteGroupedObject {
  id: string;
}

export type GroupedObject = InlineGroupedObject | RemoteGroupedObject;

/** Object group definition (Section 7.2) */
export interface ObjectGroup {
  dataType: DataType;
  mode: 'inline' | 'remote';
  downloadUrl?: string;
  downloadHeaders?: Record<string, string>;
  pdfOptions?: PdfOptions;
  xmlOptions?: XmlOptions;
  callbacks: CallbacksConfig;
  upload: UploadConfig;
  objects: GroupedObject[];
}

// ---------------------------------------------------------------------------
// Section 9: Complete Request Schema
// ---------------------------------------------------------------------------

/** Certificate selection (Section 9.3) */
export interface CertificateSelection {
  certId: string;
  label?: string;
}

/** Top-level signing request (Section 9.1) */
export interface SignRequest {
  protocolVersion: string;
  requestId: string;
  correlationId?: string;
  appId: string;
  cert: CertificateSelection;
  metadata: Record<string, unknown>;
  objects?: SignObject[];
  objectGroups?: ObjectGroup[];
}

// ---------------------------------------------------------------------------
// Section 10: Acknowledgment Response Schema (v1.0.3 — fire-and-forget)
// ---------------------------------------------------------------------------

/**
 * Acknowledgment status (Section 10.3).
 * "accepted" — request validated and forwarded to native host.
 * "error"    — request-level validation failure (see errors array).
 *
 * Actual signing results are delivered exclusively via callbacks.
 */
export type ResponseStatus = 'accepted' | 'error';

/** Top-level acknowledgment response (Section 10.1) */
export interface SignResponse {
  protocolVersion: string;
  requestId: string;
  status: ResponseStatus;
  errors?: ErrorObject[];
  metadata: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Section 13: Error Handling
// ---------------------------------------------------------------------------

/** Error codes (Section 13.1) */
export type ErrorCode =
  | 'BAD_REQUEST'
  | 'UNSUPPORTED_VERSION'
  | 'UNSUPPORTED_TYPE'
  | 'CERT_NOT_FOUND'
  | 'DOWNLOAD_FAILED'
  | 'SIGN_FAILED'
  | 'UPLOAD_FAILED'
  | 'CALLBACK_FAILED'
  | 'PROGRESS_ENDPOINT_FAILED'
  | 'TIMEOUT'
  | 'CANCELLED_BY_USER'
  | 'INTERNAL_ERROR';

/** Error object structure (Section 10.5) */
export interface ErrorObject {
  id?: string;
  code: ErrorCode;
  message: string;
}

// ---------------------------------------------------------------------------
// Section 8.5: Callback Payloads (sent by native host, typed for reference)
// ---------------------------------------------------------------------------

export interface ProgressCallbackPayload {
  objectId: string;
  requestId: string;
  status: 'signing' | 'uploading';
  percentComplete: number;
  message?: string;
  metadata: Record<string, unknown>;
}

export interface SuccessCallbackPayload {
  objectId: string;
  requestId: string;
  status: 'completed';
  uploadResult: {
    statusCode: number;
    responseBody: string;
  };
  timestamp: string;
  metadata: Record<string, unknown>;
}

export interface ErrorCallbackPayload {
  objectId: string;
  requestId: string;
  status: 'failed';
  error: {
    code: ErrorCode;
    message: string;
  };
  timestamp: string;
  metadata: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Internal message envelope (Content Script ↔ Background)
// ---------------------------------------------------------------------------

export interface InternalSignRequest {
  type: 'SIGNBRIDGE_SIGN_REQUEST';
  data: SignRequest;
}

export interface InternalSignResponse {
  type: 'SIGNBRIDGE_SIGN_RESPONSE';
  data: SignResponse;
}
