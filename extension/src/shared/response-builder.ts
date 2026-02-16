// =============================================================================
// SignBridge Response Builder — creates standard-compliant responses
// Used when the extension itself must respond (Section 10, 13.2)
// =============================================================================

import { SignResponse, ErrorCode, ErrorObject } from '../types/protocol';
import { PROTOCOL_VERSION } from './constants';

/**
 * Build an error acknowledgment from a (possibly partial) request.
 * Used when validation fails or the native host is unreachable.
 */
export function buildErrorResponse(
  request: {
    protocolVersion?: string;
    requestId?: string;
    metadata?: Record<string, unknown>;
  } | null,
  code: ErrorCode,
  message: string,
): SignResponse {
  const error: ErrorObject = { code, message };

  return {
    protocolVersion: request?.protocolVersion ?? PROTOCOL_VERSION,
    requestId: request?.requestId ?? 'unknown',
    status: 'error',
    errors: [error],
    metadata: request?.metadata ?? {},
  };
}

/**
 * Build an "accepted" acknowledgment.
 * Returned immediately after the request is forwarded to the native host.
 * Actual signing results are delivered exclusively via callbacks.
 */
export function buildAcceptedResponse(
  request: {
    protocolVersion?: string;
    requestId?: string;
    metadata?: Record<string, unknown>;
  },
): SignResponse {
  return {
    protocolVersion: request.protocolVersion ?? PROTOCOL_VERSION,
    requestId: request.requestId ?? 'unknown',
    status: 'accepted',
    metadata: request.metadata ?? {},
  };
}
