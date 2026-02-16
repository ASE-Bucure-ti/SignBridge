// =============================================================================
// SignBridge Protocol Types (shared between client, server, and SDK)
// Mirror of extension/src/types/protocol.ts for the test app
// =============================================================================

// Section 4: Data Types
export type DataType = 'text' | 'xml' | 'json' | 'pdf' | 'binary';
export type SignedContentType = 'string' | 'pdf' | 'xml' | 'binary';

// Section 5: Content Representation
export interface InlineContent {
  mode: 'inline';
  encoding: 'utf8';
  content: string;
}

export interface RemoteContent {
  mode: 'remote';
  downloadUrl: string;
  httpMethod?: string;
  headers?: Record<string, string>;
}

export type ContentDefinition = InlineContent | RemoteContent;

// Section 6: Object Structure
export interface PdfOptions {
  label: string;
}

export interface XmlOptions {
  xpath: string;
  idAttribute?: string;
}

export interface UploadConfig {
  uploadUrl: string;
  httpMethod?: string;
  headers?: Record<string, string>;
  signedContentType: SignedContentType;
}

export interface CallbacksConfig {
  onSuccess: string;
  onError: string;
  progress?: string;
  headers?: Record<string, string>;
}

export interface SignObject {
  id: string;
  dataType: DataType;
  content: ContentDefinition;
  pdfOptions?: PdfOptions;
  xmlOptions?: XmlOptions;
  upload: UploadConfig;
  callbacks: CallbacksConfig;
}

// Section 7: Object Grouping
export interface InlineGroupedObject {
  id: string;
  content: {
    encoding: 'utf8';
    value: string;
  };
}

export interface RemoteGroupedObject {
  id: string;
}

export type GroupedObject = InlineGroupedObject | RemoteGroupedObject;

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

// Section 9: Request
export interface CertificateSelection {
  certId: string;
  label?: string;
}

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

// Section 10: Acknowledgment Response (v1.0.3 — fire-and-forget)
export type ResponseStatus = 'accepted' | 'error';

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

export interface ErrorObject {
  id?: string;
  code: ErrorCode;
  message: string;
}

export interface SignResponse {
  protocolVersion: string;
  requestId: string;
  status: ResponseStatus;
  errors?: ErrorObject[];
  metadata: Record<string, unknown>;
}

// Section 8.5: Callback Payloads
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

// postMessage envelope
export interface PostMessageRequest {
  type: 'HSM_SIGN_REQUEST';
  data: SignRequest;
}

export interface PostMessageResponse {
  type: 'HSM_SIGN_RESPONSE';
  data: SignResponse;
}
