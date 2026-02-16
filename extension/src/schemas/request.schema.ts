// =============================================================================
// SignBridge Request JSON Schema — mirrors Standard v1.0.2 exactly
//
// Structural validation is handled by this schema.
// Semantic validation (HTTPS enforcement, <objectId> placeholders, unique IDs,
// conditional requirements like pdfOptions/xmlOptions/remote mode)
// is performed post-schema in validator.ts.
// =============================================================================

/* eslint-disable @typescript-eslint/no-explicit-any */
export const requestSchema: Record<string, any> = {
  type: 'object',
  required: ['protocolVersion', 'requestId', 'appId', 'cert', 'metadata'],
  additionalProperties: false,

  // Section 7.5 Rule 1 — objects XOR objectGroups, never both, never neither.
  oneOf: [
    { required: ['objects'] },
    { required: ['objectGroups'] },
  ],

  properties: {
    // Section 3 — Protocol versioning
    protocolVersion: { type: 'string', enum: ['1.0'] },

    // Section 9.2
    requestId: { type: 'string', minLength: 1 },
    correlationId: { type: 'string' },
    appId: { type: 'string', minLength: 1 },

    // Section 9.3 — Certificate selection
    cert: {
      type: 'object',
      required: ['certId'],
      additionalProperties: false,
      properties: {
        certId: { type: 'string', minLength: 1 },
        label: { type: 'string' },
      },
    },

    // Section 9.4 — Opaque metadata
    metadata: { type: 'object' },

    // Section 6 — Non-grouped objects
    objects: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        required: ['id', 'dataType', 'content', 'upload', 'callbacks'],
        additionalProperties: false,
        properties: {
          id: { type: 'string', minLength: 1 },
          dataType: { type: 'string', enum: ['text', 'xml', 'json', 'pdf', 'binary'] },
          content: {
            type: 'object',
            properties: {
              mode: { type: 'string', enum: ['inline', 'remote'] },
              encoding: { type: 'string' },
              content: { type: 'string' },
              downloadUrl: { type: 'string' },
              httpMethod: { type: 'string' },
              headers: { type: 'object', additionalProperties: { type: 'string' } },
            },
            required: ['mode'],
          },
          pdfOptions: {
            type: 'object',
            required: ['label'],
            additionalProperties: false,
            properties: {
              label: { type: 'string', minLength: 1 },
            },
          },
          xmlOptions: {
            type: 'object',
            required: ['xpath'],
            additionalProperties: false,
            properties: {
              xpath: { type: 'string', minLength: 1 },
              idAttribute: { type: 'string' },
            },
          },
          upload: {
            type: 'object',
            required: ['uploadUrl', 'signedContentType'],
            additionalProperties: false,
            properties: {
              uploadUrl: { type: 'string', minLength: 1 },
              httpMethod: { type: 'string' },
              headers: { type: 'object', additionalProperties: { type: 'string' } },
              signedContentType: { type: 'string', enum: ['string', 'pdf', 'xml', 'binary'] },
            },
          },
          callbacks: {
            type: 'object',
            required: ['onSuccess', 'onError'],
            additionalProperties: false,
            properties: {
              onSuccess: { type: 'string', minLength: 1 },
              onError: { type: 'string', minLength: 1 },
              progress: { type: 'string', minLength: 1 },
              headers: { type: 'object', additionalProperties: { type: 'string' } },
            },
          },
        },
      },
    },

    // Section 7 — Grouped objects
    objectGroups: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        required: ['dataType', 'mode', 'callbacks', 'upload', 'objects'],
        additionalProperties: false,
        properties: {
          dataType: { type: 'string', enum: ['text', 'xml', 'json', 'pdf', 'binary'] },
          mode: { type: 'string', enum: ['inline', 'remote'] },
          downloadUrl: { type: 'string', minLength: 1 },
          downloadHeaders: { type: 'object', additionalProperties: { type: 'string' } },
          pdfOptions: {
            type: 'object',
            required: ['label'],
            additionalProperties: false,
            properties: {
              label: { type: 'string', minLength: 1 },
            },
          },
          xmlOptions: {
            type: 'object',
            required: ['xpath'],
            additionalProperties: false,
            properties: {
              xpath: { type: 'string', minLength: 1 },
              idAttribute: { type: 'string' },
            },
          },
          callbacks: {
            type: 'object',
            required: ['onSuccess', 'onError'],
            additionalProperties: false,
            properties: {
              onSuccess: { type: 'string', minLength: 1 },
              onError: { type: 'string', minLength: 1 },
              progress: { type: 'string', minLength: 1 },
              headers: { type: 'object', additionalProperties: { type: 'string' } },
            },
          },
          upload: {
            type: 'object',
            required: ['uploadUrl', 'signedContentType'],
            additionalProperties: false,
            properties: {
              uploadUrl: { type: 'string', minLength: 1 },
              httpMethod: { type: 'string' },
              headers: { type: 'object', additionalProperties: { type: 'string' } },
              signedContentType: { type: 'string', enum: ['string', 'pdf', 'xml', 'binary'] },
            },
          },
          objects: {
            type: 'array',
            minItems: 1,
            items: {
              type: 'object',
              required: ['id'],
              properties: {
                id: { type: 'string', minLength: 1 },
                content: {
                  type: 'object',
                  properties: {
                    encoding: { type: 'string' },
                    value: { type: 'string' },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
};
