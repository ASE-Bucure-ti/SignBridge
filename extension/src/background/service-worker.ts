// =============================================================================
// SignBridge Background Service Worker (MV3)
//
// Bridges the content script to the native messaging host (com.ase.signer).
//
// Fire-and-forget model (v1.0.3):
//   1. Receive validated signing request from content script
//   2. Open a native messaging port to the host application
//   3. Forward the request unchanged to the native host
//   4. Return an "accepted" acknowledgment immediately
//   5. Keep the port alive — the native host delivers results via callbacks
//   6. Clean up when the native host disconnects
//
//   Does NOT: wait for a signing response, relay results, download content,
//             modify payloads, or perform signing.
// =============================================================================

import browser from 'webextension-polyfill';
import { logger } from '../shared/logger';
import { buildErrorResponse, buildAcceptedResponse } from '../shared/response-builder';
import { INTERNAL_SIGN_REQUEST, NATIVE_HOST_NAME } from '../shared/constants';
import type { SignRequest, SignResponse } from '../types/protocol';

// ---------------------------------------------------------------------------
// Keep native messaging ports alive (prevent GC during fire-and-forget)
// ---------------------------------------------------------------------------
const activePorts = new Map<string, browser.Runtime.Port>();

// ---------------------------------------------------------------------------
// Message listener — content script → background
// ---------------------------------------------------------------------------

browser.runtime.onMessage.addListener(
  (
    rawMessage: unknown,
    _sender: browser.Runtime.MessageSender,
  ): Promise<{ data: SignResponse }> | undefined => {
    const message = rawMessage as { type: string; data: SignRequest };
    if (!message || message.type !== INTERNAL_SIGN_REQUEST) return undefined;

    const request = message.data;
    logger.info(`Processing signing request: ${request.requestId}`);
    logger.debug('Request payload', { requestId: request.requestId, appId: request.appId });

    // Return a Promise so the messaging channel stays open for the ACK
    return processSignRequest(request).then((response) => ({ data: response }));
  },
);

// ---------------------------------------------------------------------------
// Native messaging bridge — fire-and-forget
// ---------------------------------------------------------------------------

/**
 * Open a native messaging port, send the signing request, and return
 * an immediate acknowledgment.  The native host delivers actual signing
 * results directly to the caller's backend via callbacks.
 *
 * An active connectNative() port keeps the MV3 service worker alive
 * for the duration of the signing operation.
 */
async function processSignRequest(request: SignRequest): Promise<SignResponse> {
  return new Promise<SignResponse>((resolve) => {
    let resolved = false;

    const finish = (response: SignResponse): void => {
      if (resolved) return;
      resolved = true;
      resolve(response);
    };

    // --- Connect to native host -------------------------------------------
    let port: browser.Runtime.Port;
    try {
      port = browser.runtime.connectNative(NATIVE_HOST_NAME);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      logger.error(`Failed to connect to native host '${NATIVE_HOST_NAME}': ${msg}`);
      finish(
        buildErrorResponse(
          request,
          'INTERNAL_ERROR',
          `Native host unavailable: ${msg}`,
        ),
      );
      return;
    }

    // Store port reference to prevent GC
    activePorts.set(request.requestId, port);

    // --- Handle disconnection / errors ------------------------------------
    port.onDisconnect.addListener(() => {
      activePorts.delete(request.requestId);

      const lastError =
        (port as unknown as { error?: { message: string } }).error ??
        browser.runtime.lastError;
      const errorMsg =
        (lastError as { message?: string })?.message ??
        'Native host disconnected';

      if (!resolved) {
        // Disconnected before ACK was sent → connection error (host not found)
        logger.error(`Native host connection failed for ${request.requestId}: ${errorMsg}`);
        finish(
          buildErrorResponse(request, 'INTERNAL_ERROR', `Native host unavailable: ${errorMsg}`),
        );
      } else {
        // Disconnected after ACK was sent → normal completion or crash
        logger.info(`Native host disconnected for ${request.requestId}: ${errorMsg}`);
      }
    });

    // --- Optionally log messages from native host (informational) ---------
    port.onMessage.addListener((rawResponse: unknown) => {
      const response = rawResponse as Record<string, unknown>;
      logger.info(
        `Native host message for ${request.requestId} (informational): status=${response?.status ?? 'unknown'}`,
      );
    });

    // --- Send request to native host --------------------------------------
    try {
      port.postMessage(request);
      logger.debug('Request forwarded to native host', {
        requestId: request.requestId,
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to send message';
      logger.error(`Error sending to native host: ${msg}`);
      activePorts.delete(request.requestId);
      finish(
        buildErrorResponse(request, 'INTERNAL_ERROR', msg),
      );
      safeDisconnect(port);
      return;
    }

    // --- Return ACK after a brief grace period ----------------------------
    // Wait briefly to detect immediate disconnects (host not found/crash).
    // If the port is still alive, return "accepted".
    setTimeout(() => {
      finish(buildAcceptedResponse(request));
    }, 150);
  });
}

/**
 * Disconnect the native messaging port, swallowing errors that occur
 * if the port is already closed.
 */
function safeDisconnect(port: browser.Runtime.Port): void {
  try {
    port.disconnect();
  } catch {
    // Port already disconnected — safe to ignore
  }
}

// ---------------------------------------------------------------------------
// Lifecycle log
// ---------------------------------------------------------------------------
logger.info('Background service worker initialised');
