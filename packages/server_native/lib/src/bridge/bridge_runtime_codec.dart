part of 'bridge_runtime.dart';

/// Current bridge wire protocol version.
const int bridgeFrameProtocolVersion = 1;

/// Legacy bridge protocol version accepted for compatibility.
const int _bridgeFrameProtocolVersionLegacy = 1;

/// Legacy single-frame request type.
const int _bridgeRequestFrameType = 1; // legacy single-frame request
/// Legacy single-frame response type.
const int _bridgeResponseFrameType = 2; // legacy single-frame response
const int _bridgeRequestStartFrameType = 3;
const int _bridgeRequestChunkFrameType = 4;
const int _bridgeRequestEndFrameType = 5;
const int _bridgeResponseStartFrameType = 6;
const int _bridgeResponseChunkFrameType = 7;
const int _bridgeResponseEndFrameType = 8;
const int _bridgeTunnelChunkFrameType = 9;
const int _bridgeTunnelCloseFrameType = 10;
const int _bridgeRequestFrameTypeTokenized = 11;
const int _bridgeResponseFrameTypeTokenized = 12;
const int _bridgeRequestStartFrameTypeTokenized = 13;
const int _bridgeResponseStartFrameTypeTokenized = 14;

/// Token marker indicating a literal (non-tokenized) header name follows.
const int _bridgeHeaderNameLiteralToken = 0xffff;
const Utf8Decoder _strictUtf8Decoder = Utf8Decoder(allowMalformed: false);

/// Whether response/request encoding should emit tokenized header frame types.
const bool _encodeTokenizedHeaderFrameTypes = true;

/// Header name table used by tokenized header encoding.
const List<String> _bridgeHeaderNameTable = <String>[
  'host',
  'connection',
  'user-agent',
  'accept',
  'accept-encoding',
  'accept-language',
  'content-type',
  'content-length',
  'transfer-encoding',
  'cookie',
  'set-cookie',
  'cache-control',
  'pragma',
  'upgrade',
  'authorization',
  'origin',
  'referer',
  'location',
  'server',
  'date',
  'x-forwarded-for',
  'x-forwarded-proto',
  'x-forwarded-host',
  'x-forwarded-port',
  'x-request-id',
  'sec-websocket-key',
  'sec-websocket-version',
  'sec-websocket-protocol',
  'sec-websocket-extensions',
];
