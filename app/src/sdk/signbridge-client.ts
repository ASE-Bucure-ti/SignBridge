// =============================================================================
// SignBridge Client SDK
// Wraps window.postMessage for sending HSM_SIGN_REQUEST and receiving the
// extension's acknowledgment (v1.0.3 fire-and-forget model).
// On mobile, dispatches via signbridge:// deep link instead.
// Actual signing results are delivered via callbacks to the backend.
// =============================================================================

import type { SignRequest, SignResponse, PostMessageRequest, PostMessageResponse } from '../../shared/protocol';

export type SignBridgeTransport = 'extension' | 'deeplink';

export interface SignBridgeOptions {
  /** Timeout in milliseconds (default: 10000 = 10s — ACK should come fast) */
  timeout?: number;
  /** Target origin for postMessage (default: '*') */
  targetOrigin?: string;
  /** Called when the extension is detected / not detected */
  onExtensionCheck?: (detected: boolean) => void;
  /** Force a specific transport instead of auto-detecting */
  transport?: SignBridgeTransport;
  /** Custom deep link scheme (default: 'signbridge') */
  deepLinkScheme?: string;
}

export type SignBridgeEventType =
  | 'request-sent'
  | 'response-received'
  | 'timeout'
  | 'error';

export interface SignBridgeEvent {
  type: SignBridgeEventType;
  requestId: string;
  data?: SignResponse;
  error?: string;
  timestamp: number;
}

type EventListener = (event: SignBridgeEvent) => void;

/**
 * SignBridge Client SDK — send signing requests to the SignBridge extension.
 *
 * Usage:
 * ```ts
 * const client = new SignBridgeClient({ timeout: 60000 });
 * const response = await client.sign(request);
 * ```
 */
export class SignBridgeClient {
  private timeout: number;
  private targetOrigin: string;
  private listeners: EventListener[] = [];
  private transport: SignBridgeTransport;
  private deepLinkScheme: string;

  constructor(options: SignBridgeOptions = {}) {
    this.timeout = options.timeout ?? 10_000;
    this.targetOrigin = options.targetOrigin ?? '*';
    this.deepLinkScheme = options.deepLinkScheme ?? 'signbridge';
    this.transport = options.transport ?? this.detectTransport();
  }

  /** Auto-detect transport: mobile → deeplink, desktop → extension */
  private detectTransport(): SignBridgeTransport {
    if (typeof navigator === 'undefined') return 'extension';
    const ua = navigator.userAgent;
    const isMobile = /Android|iPhone|iPad|iPod|Mobile/i.test(ua);
    return isMobile ? 'deeplink' : 'extension';
  }

  /** Get the active transport */
  getTransport(): SignBridgeTransport {
    return this.transport;
  }

  /** Override the transport at runtime */
  setTransport(transport: SignBridgeTransport): void {
    this.transport = transport;
  }

  /** Subscribe to SDK lifecycle events */
  on(listener: EventListener): () => void {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  private emit(event: SignBridgeEvent): void {
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch {
        // Swallow listener errors
      }
    }
  }

  /**
   * Send a signing request and wait for the acknowledgment.
   * On desktop: postMessage to the extension, resolves with ACK.
   * On mobile: opens signbridge:// deep link, resolves immediately
   * with a synthetic "accepted" ACK (results come via callbacks).
   */
  sign(request: SignRequest): Promise<SignResponse> {
    if (this.transport === 'deeplink') {
      return this.signViaDeepLink(request);
    }
    return this.signViaExtension(request);
  }

  /**
   * Deep link transport: encode the request as a signbridge:// URL and open it.
   * The mobile app receives the payload, performs signing, and delivers
   * results via the callbacks specified in the request. Returns a synthetic ACK.
   */
  private signViaDeepLink(request: SignRequest): Promise<SignResponse> {
    const requestId = request.requestId;
    try {
      const json = JSON.stringify(request);
      // Base64url encode (browser-safe)
      const base64 = btoa(
        String.fromCharCode(...new Uint8Array(new TextEncoder().encode(json)))
      )
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');

      const deepLinkUrl = `${this.deepLinkScheme}://sign?payload=${base64}`;
      this.emit({ type: 'request-sent', requestId, timestamp: Date.now() });

      // Open deep link
      window.location.href = deepLinkUrl;

      // Return synthetic ACK — actual results come via callbacks
      const ack: SignResponse = {
        protocolVersion: request.protocolVersion,
        requestId,
        status: 'accepted',
        metadata: { transport: 'deeplink' },
      };
      this.emit({ type: 'response-received', requestId, data: ack, timestamp: Date.now() });
      return Promise.resolve(ack);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      this.emit({ type: 'error', requestId, error: errMsg, timestamp: Date.now() });
      return Promise.reject(err);
    }
  }

  /**
   * Extension transport: postMessage to the SignBridge extension.
   * Resolves with the ACK (status "accepted" or "error").
   */
  private signViaExtension(request: SignRequest): Promise<SignResponse> {
    return new Promise<SignResponse>((resolve, reject) => {
      const requestId = request.requestId;
      let settled = false;

      // Timeout handler
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        window.removeEventListener('message', handler);
        const err = `SignBridge: timeout after ${this.timeout}ms for request ${requestId}`;
        this.emit({ type: 'timeout', requestId, error: err, timestamp: Date.now() });
        reject(new Error(err));
      }, this.timeout);

      // Response handler
      const handler = (event: MessageEvent) => {
        if (settled) return;

        const msg = event.data as PostMessageResponse | undefined;
        if (!msg || msg.type !== 'HSM_SIGN_RESPONSE') return;
        // Match by requestId. When the request had no requestId (validation
        // error scenario), the extension responds with 'unknown' — accept that.
        if (requestId && msg.data?.requestId !== requestId) return;
        if (!requestId && msg.data?.requestId !== 'unknown') return;

        settled = true;
        clearTimeout(timer);
        window.removeEventListener('message', handler);

        this.emit({
          type: 'response-received',
          requestId,
          data: msg.data,
          timestamp: Date.now(),
        });

        resolve(msg.data);
      };

      window.addEventListener('message', handler);

      // Send the request
      const envelope: PostMessageRequest = {
        type: 'HSM_SIGN_REQUEST',
        data: request,
      };

      try {
        window.postMessage(envelope, this.targetOrigin);
        this.emit({ type: 'request-sent', requestId, timestamp: Date.now() });
      } catch (err) {
        settled = true;
        clearTimeout(timer);
        window.removeEventListener('message', handler);
        const errMsg = err instanceof Error ? err.message : String(err);
        this.emit({ type: 'error', requestId, error: errMsg, timestamp: Date.now() });
        reject(err);
      }
    });
  }

  /**
   * Fire-and-forget: send a request without waiting for a response.
   * Useful when you only care about callbacks.
   */
  sendOnly(request: SignRequest): void {
    if (this.transport === 'deeplink') {
      this.signViaDeepLink(request);
      return;
    }
    const envelope: PostMessageRequest = {
      type: 'HSM_SIGN_REQUEST',
      data: request,
    };
    window.postMessage(envelope, this.targetOrigin);
    this.emit({ type: 'request-sent', requestId: request.requestId, timestamp: Date.now() });
  }

  /** Update the default timeout */
  setTimeout(ms: number): void {
    this.timeout = ms;
  }
}

export default SignBridgeClient;
