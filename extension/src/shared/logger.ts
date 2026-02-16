// =============================================================================
// SignBridge Logger — safe logging that never exposes secrets (Section 14.5)
// =============================================================================

const PREFIX = '[SignBridge]';

/** Keys whose values must be redacted in debug output */
const SENSITIVE_PATTERNS = ['key', 'token', 'auth', 'secret', 'password', 'bearer'];

/**
 * Recursively redact sensitive values from an object for safe logging.
 * Detects header-like keys (api-key, authorization, etc.) and masks them.
 */
function sanitize(obj: unknown): unknown {
  if (typeof obj !== 'object' || obj === null) return obj;
  if (Array.isArray(obj)) return obj.map(sanitize);

  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
    const lower = key.toLowerCase();
    const isSensitive = SENSITIVE_PATTERNS.some((p) => lower.includes(p));

    if (isSensitive && typeof value === 'string') {
      sanitized[key] = '[REDACTED]';
    } else if (typeof value === 'object' && value !== null) {
      sanitized[key] = sanitize(value);
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

export const logger = {
  info(msg: string, ...args: unknown[]): void {
    console.log(`${PREFIX} ${msg}`, ...args);
  },

  warn(msg: string, ...args: unknown[]): void {
    console.warn(`${PREFIX} ${msg}`, ...args);
  },

  error(msg: string, ...args: unknown[]): void {
    console.error(`${PREFIX} ${msg}`, ...args);
  },

  /**
   * Debug-level log that sanitizes structured data so that API keys,
   * tokens, and authorization headers are never written to the console.
   */
  debug(msg: string, data?: unknown): void {
    if (data !== undefined) {
      console.debug(`${PREFIX} ${msg}`, sanitize(data));
    } else {
      console.debug(`${PREFIX} ${msg}`);
    }
  },
};
