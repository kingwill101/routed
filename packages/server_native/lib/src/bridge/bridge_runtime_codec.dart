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

@pragma('vm:prefer-inline')
int? _bridgeHeaderLookupToken(String name) {
  switch (name) {
    case 'host':
      return 0;
    case 'connection':
      return 1;
    case 'user-agent':
      return 2;
    case 'accept':
      return 3;
    case 'accept-encoding':
      return 4;
    case 'accept-language':
      return 5;
    case 'content-type':
      return 6;
    case 'content-length':
      return 7;
    case 'transfer-encoding':
      return 8;
    case 'cookie':
      return 9;
    case 'set-cookie':
      return 10;
    case 'cache-control':
      return 11;
    case 'pragma':
      return 12;
    case 'upgrade':
      return 13;
    case 'authorization':
      return 14;
    case 'origin':
      return 15;
    case 'referer':
      return 16;
    case 'location':
      return 17;
    case 'server':
      return 18;
    case 'date':
      return 19;
    case 'x-forwarded-for':
      return 20;
    case 'x-forwarded-proto':
      return 21;
    case 'x-forwarded-host':
      return 22;
    case 'x-forwarded-port':
      return 23;
    case 'x-request-id':
      return 24;
    case 'sec-websocket-key':
      return 25;
    case 'sec-websocket-version':
      return 26;
    case 'sec-websocket-protocol':
      return 27;
    case 'sec-websocket-extensions':
      return 28;
  }
  return null;
}
