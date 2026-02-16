// =============================================================================
// SignBridge Content Script
//
// Injected into web pages. Bridges window.postMessage ↔ background worker.
//
// Responsibilities (Section 2.3):
//   1. Listen for HSM_SIGN_REQUEST from the web application
//   2. Validate sender origin against user-configured allowlist (Section 14.2)
//   3. Validate request schema (Sections 4-9)
//   4. Forward valid request to background service worker
//   5. Relay acknowledgment (accepted/error) back to the web application
//
//   Does NOT: download content, modify payloads, or perform signing.
//   Actual signing results are delivered via callbacks (v1.0.3).
// =============================================================================

import browser from 'webextension-polyfill';
import { validateRequest } from '../validation/validator';
import { buildErrorResponse } from '../shared/response-builder';
import { logger } from '../shared/logger';
import {
  MSG_SIGN_REQUEST,
  MSG_SIGN_RESPONSE,
  INTERNAL_SIGN_REQUEST,
  STORAGE_ALLOWED_ORIGINS,
} from '../shared/constants';
import type { SignResponse } from '../types/protocol';

// ---------------------------------------------------------------------------
// Main listener — catches postMessage from the host page
// ---------------------------------------------------------------------------

window.addEventListener('message', async (event: MessageEvent) => {
  // Ignore messages that aren't ours
  if (!event.data || event.data.type !== MSG_SIGN_REQUEST) return;

  const origin = event.origin;
  const requestData = event.data.data;

  logger.info(`Received signing request from origin: ${origin}`);

  // 1. Origin validation (Section 14.2)
  const allowed = await isOriginAllowed(origin);
  if (!allowed) {
    logger.warn(`Rejected request from unauthorized origin: ${origin}`);
    postResponse(
      buildErrorResponse(requestData, 'BAD_REQUEST', 'Origin not authorized'),
      origin,
    );
    return;
  }

  // 2. Schema + semantic validation (Sections 4-9, 14.1)
  const validation = validateRequest(requestData);
  if (!validation.valid) {
    logger.warn('Request schema validation failed:', validation.errors);
    postResponse(
      buildErrorResponse(
        requestData,
        'BAD_REQUEST',
        `Validation failed: ${validation.errors.join('; ')}`,
      ),
      origin,
    );
    return;
  }

  // 3. Forward to background service worker via runtime messaging
  try {
    const response: { data: SignResponse } = await browser.runtime.sendMessage({
      type: INTERNAL_SIGN_REQUEST,
      data: requestData,
    });

    logger.info(`Relaying response for request ${requestData.requestId}, status: ${response.data.status}`);
    postResponse(response.data, origin);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : 'Extension internal communication error';
    logger.error('Failed to communicate with background service worker:', message);
    postResponse(
      buildErrorResponse(requestData, 'INTERNAL_ERROR', message),
      origin,
    );
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Check the requesting origin against the user-configured allowlist
 * stored in chrome.storage.sync (managed via the options page).
 */
async function isOriginAllowed(origin: string): Promise<boolean> {
  try {
    const result = await browser.storage.sync.get(STORAGE_ALLOWED_ORIGINS);
    const origins: string[] = (result[STORAGE_ALLOWED_ORIGINS] as string[] | undefined) ?? [];
    return origins.includes(origin);
  } catch (err) {
    logger.error('Failed to read allowed origins from storage:', err);
    return false;
  }
}

/**
 * Post the signing response back to the web application.
 * Uses the request's origin as targetOrigin for security (Section 14.2).
 */
function postResponse(data: SignResponse, targetOrigin: string): void {
  window.postMessage({ type: MSG_SIGN_RESPONSE, data }, targetOrigin);
}

// ---------------------------------------------------------------------------
// Lifecycle log
// ---------------------------------------------------------------------------
logger.info('Content script loaded — listening for HSM_SIGN_REQUEST');
