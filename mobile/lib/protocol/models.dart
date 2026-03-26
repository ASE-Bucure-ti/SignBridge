// SignBridge Protocol v1.0.3 — Data models
// Mirrors app/shared/protocol.ts

import 'errors.dart';

// ── Section 4: Data Types ────────────────────────────────────────────────────

enum DataType {
  text('text'),
  xml('xml'),
  json('json'),
  pdf('pdf'),
  binary('binary');

  final String value;
  const DataType(this.value);

  factory DataType.fromJson(String json) => DataType.values.firstWhere(
    (e) => e.value == json,
    orElse: () => throw SigningError(
      ErrorCode.unsupportedType,
      'Unknown dataType: $json',
    ),
  );

  String toJson() => value;
}

enum SignedContentType {
  string('string'),
  pdf('pdf'),
  xml('xml'),
  binary('binary');

  final String value;
  const SignedContentType(this.value);

  factory SignedContentType.fromJson(String json) =>
      SignedContentType.values.firstWhere(
        (e) => e.value == json,
        orElse: () => throw SigningError(
          ErrorCode.unsupportedType,
          'Unknown signedContentType: $json',
        ),
      );

  String toJson() => value;
}

// ── Section 5: Content Representation ────────────────────────────────────────

class InlineContent {
  final String encoding; // always 'utf8'
  final String content;

  const InlineContent({this.encoding = 'utf8', required this.content});

  factory InlineContent.fromJson(Map<String, dynamic> json) => InlineContent(
    encoding: json['encoding'] as String? ?? 'utf8',
    content: json['content'] as String,
  );
}

class RemoteContent {
  final String downloadUrl;
  final String? httpMethod;
  final Map<String, String>? headers;

  const RemoteContent({
    required this.downloadUrl,
    this.httpMethod,
    this.headers,
  });

  factory RemoteContent.fromJson(Map<String, dynamic> json) => RemoteContent(
    downloadUrl: json['downloadUrl'] as String,
    httpMethod: json['httpMethod'] as String?,
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v as String),
    ),
  );
}

class ContentDefinition {
  final String mode; // 'inline' or 'remote'
  final InlineContent? inline;
  final RemoteContent? remote;

  const ContentDefinition._({required this.mode, this.inline, this.remote});

  bool get isInline => mode == 'inline';
  bool get isRemote => mode == 'remote';

  factory ContentDefinition.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] as String;
    if (mode == 'inline') {
      return ContentDefinition._(
        mode: mode,
        inline: InlineContent.fromJson(json),
      );
    } else {
      return ContentDefinition._(
        mode: mode,
        remote: RemoteContent.fromJson(json),
      );
    }
  }
}

// ── Section 6: Object Structure ──────────────────────────────────────────────

class PdfOptions {
  final String label;

  const PdfOptions({required this.label});

  factory PdfOptions.fromJson(Map<String, dynamic> json) =>
      PdfOptions(label: json['label'] as String);
}

class XmlOptions {
  final String xpath;
  final String? idAttribute;

  const XmlOptions({required this.xpath, this.idAttribute});

  factory XmlOptions.fromJson(Map<String, dynamic> json) => XmlOptions(
    xpath: json['xpath'] as String,
    idAttribute: json['idAttribute'] as String?,
  );
}

class UploadConfig {
  final String uploadUrl;
  final String? httpMethod;
  final Map<String, String>? headers;
  final SignedContentType signedContentType;

  const UploadConfig({
    required this.uploadUrl,
    this.httpMethod,
    this.headers,
    required this.signedContentType,
  });

  factory UploadConfig.fromJson(Map<String, dynamic> json) => UploadConfig(
    uploadUrl: json['uploadUrl'] as String,
    httpMethod: json['httpMethod'] as String?,
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v as String),
    ),
    signedContentType: SignedContentType.fromJson(
      json['signedContentType'] as String,
    ),
  );
}

class CallbacksConfig {
  final String onSuccess;
  final String onError;
  final String? progress;
  final Map<String, String>? headers;

  const CallbacksConfig({
    required this.onSuccess,
    required this.onError,
    this.progress,
    this.headers,
  });

  factory CallbacksConfig.fromJson(Map<String, dynamic> json) =>
      CallbacksConfig(
        onSuccess: json['onSuccess'] as String,
        onError: json['onError'] as String,
        progress: json['progress'] as String?,
        headers: (json['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ),
      );
}

class SignObject {
  final String id;
  final DataType dataType;
  final ContentDefinition content;
  final PdfOptions? pdfOptions;
  final XmlOptions? xmlOptions;
  final UploadConfig upload;
  final CallbacksConfig callbacks;

  const SignObject({
    required this.id,
    required this.dataType,
    required this.content,
    this.pdfOptions,
    this.xmlOptions,
    required this.upload,
    required this.callbacks,
  });

  factory SignObject.fromJson(Map<String, dynamic> json) => SignObject(
    id: json['id'] as String,
    dataType: DataType.fromJson(json['dataType'] as String),
    content: ContentDefinition.fromJson(
      json['content'] as Map<String, dynamic>,
    ),
    pdfOptions: json['pdfOptions'] != null
        ? PdfOptions.fromJson(json['pdfOptions'] as Map<String, dynamic>)
        : null,
    xmlOptions: json['xmlOptions'] != null
        ? XmlOptions.fromJson(json['xmlOptions'] as Map<String, dynamic>)
        : null,
    upload: UploadConfig.fromJson(json['upload'] as Map<String, dynamic>),
    callbacks: CallbacksConfig.fromJson(
      json['callbacks'] as Map<String, dynamic>,
    ),
  );
}

// ── Section 7: Object Grouping ───────────────────────────────────────────────

class GroupedObject {
  final String id;
  // Inline content (optional — only for mode=inline groups)
  final String? inlineValue;
  final String? inlineEncoding;

  const GroupedObject({
    required this.id,
    this.inlineValue,
    this.inlineEncoding,
  });

  factory GroupedObject.fromJson(Map<String, dynamic> json) => GroupedObject(
    id: json['id'] as String,
    inlineValue:
        (json['content'] as Map<String, dynamic>?)?.containsKey('value') == true
        ? (json['content'] as Map<String, dynamic>)['value'] as String
        : null,
    inlineEncoding:
        (json['content'] as Map<String, dynamic>?)?.containsKey('encoding') ==
            true
        ? (json['content'] as Map<String, dynamic>)['encoding'] as String
        : null,
  );
}

class ObjectGroup {
  final DataType dataType;
  final String mode; // 'inline' or 'remote'
  final String? downloadUrl;
  final Map<String, String>? downloadHeaders;
  final PdfOptions? pdfOptions;
  final XmlOptions? xmlOptions;
  final CallbacksConfig callbacks;
  final UploadConfig upload;
  final List<GroupedObject> objects;

  const ObjectGroup({
    required this.dataType,
    required this.mode,
    this.downloadUrl,
    this.downloadHeaders,
    this.pdfOptions,
    this.xmlOptions,
    required this.callbacks,
    required this.upload,
    required this.objects,
  });

  factory ObjectGroup.fromJson(Map<String, dynamic> json) => ObjectGroup(
    dataType: DataType.fromJson(json['dataType'] as String),
    mode: json['mode'] as String,
    downloadUrl: json['downloadUrl'] as String?,
    downloadHeaders: (json['downloadHeaders'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v as String),
    ),
    pdfOptions: json['pdfOptions'] != null
        ? PdfOptions.fromJson(json['pdfOptions'] as Map<String, dynamic>)
        : null,
    xmlOptions: json['xmlOptions'] != null
        ? XmlOptions.fromJson(json['xmlOptions'] as Map<String, dynamic>)
        : null,
    callbacks: CallbacksConfig.fromJson(
      json['callbacks'] as Map<String, dynamic>,
    ),
    upload: UploadConfig.fromJson(json['upload'] as Map<String, dynamic>),
    objects: (json['objects'] as List)
        .map((o) => GroupedObject.fromJson(o as Map<String, dynamic>))
        .toList(),
  );
}

// ── Section 9: Request ───────────────────────────────────────────────────────

class CertificateSelection {
  final String certId;
  final String? label;

  const CertificateSelection({required this.certId, this.label});

  factory CertificateSelection.fromJson(Map<String, dynamic> json) =>
      CertificateSelection(
        certId: json['certId'] as String,
        label: json['label'] as String?,
      );
}

class SignRequest {
  final String protocolVersion;
  final String requestId;
  final String? correlationId;
  final String appId;
  final CertificateSelection cert;
  final Map<String, dynamic> metadata;
  final List<SignObject>? objects;
  final List<ObjectGroup>? objectGroups;

  const SignRequest({
    required this.protocolVersion,
    required this.requestId,
    this.correlationId,
    required this.appId,
    required this.cert,
    required this.metadata,
    this.objects,
    this.objectGroups,
  });

  factory SignRequest.fromJson(Map<String, dynamic> json) => SignRequest(
    protocolVersion: json['protocolVersion'] as String,
    requestId: json['requestId'] as String,
    correlationId: json['correlationId'] as String?,
    appId: json['appId'] as String,
    cert: CertificateSelection.fromJson(json['cert'] as Map<String, dynamic>),
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    objects: (json['objects'] as List?)
        ?.map((o) => SignObject.fromJson(o as Map<String, dynamic>))
        .toList(),
    objectGroups: (json['objectGroups'] as List?)
        ?.map((o) => ObjectGroup.fromJson(o as Map<String, dynamic>))
        .toList(),
  );
}

// ── Section 10: Response ─────────────────────────────────────────────────────

class ErrorObject {
  final String? id;
  final ErrorCode code;
  final String message;

  const ErrorObject({this.id, required this.code, required this.message});

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'code': code.toJson(),
    'message': message,
  };
}

class SignResponse {
  final String protocolVersion;
  final String requestId;
  final String status; // 'accepted' or 'error'
  final List<ErrorObject>? errors;
  final Map<String, dynamic> metadata;

  const SignResponse({
    required this.protocolVersion,
    required this.requestId,
    required this.status,
    this.errors,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'protocolVersion': protocolVersion,
    'requestId': requestId,
    'status': status,
    if (errors != null) 'errors': errors!.map((e) => e.toJson()).toList(),
    'metadata': metadata,
  };
}

// ── Section 8.5: Callback Payloads ───────────────────────────────────────────

class ProgressCallbackPayload {
  final String objectId;
  final String requestId;
  final String status; // 'signing' or 'uploading'
  final int percentComplete;
  final String? message;
  final Map<String, dynamic> metadata;

  const ProgressCallbackPayload({
    required this.objectId,
    required this.requestId,
    required this.status,
    required this.percentComplete,
    this.message,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'requestId': requestId,
    'status': status,
    'percentComplete': percentComplete,
    if (message != null) 'message': message,
    'metadata': metadata,
  };
}

class SuccessCallbackPayload {
  final String objectId;
  final String requestId;
  final int statusCode;
  final String responseBody;
  final String timestamp;
  final Map<String, dynamic> metadata;

  const SuccessCallbackPayload({
    required this.objectId,
    required this.requestId,
    required this.statusCode,
    required this.responseBody,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'requestId': requestId,
    'status': 'completed',
    'uploadResult': {'statusCode': statusCode, 'responseBody': responseBody},
    'timestamp': timestamp,
    'metadata': metadata,
  };
}

class ErrorCallbackPayload {
  final String objectId;
  final String requestId;
  final ErrorCode errorCode;
  final String errorMessage;
  final String timestamp;
  final Map<String, dynamic> metadata;

  const ErrorCallbackPayload({
    required this.objectId,
    required this.requestId,
    required this.errorCode,
    required this.errorMessage,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'requestId': requestId,
    'status': 'failed',
    'error': {'code': errorCode.toJson(), 'message': errorMessage},
    'timestamp': timestamp,
    'metadata': metadata,
  };
}
