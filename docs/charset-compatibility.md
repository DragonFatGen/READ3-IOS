# Charset compatibility

## Scope and Android baseline

This document compares READ3-IOS with the read-only Android reference at
`Reference/READ3.0`, commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`.

The relevant Android implementation is primarily:

- `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt`;
- `app/src/main/java/io/legado/app/help/http/OkHttpUtils.kt`;
- `app/src/main/java/io/legado/app/utils/EncodingDetect.kt`;
- `app/src/main/java/io/legado/app/utils/Utf8BomUtils.kt`.

The reference tree is evidence only and is not modified by this implementation.

## Android behavior

### Request encoding

`AnalyzeUrl.analyzeFields` parses GET query parameters and form POST bodies.
Its URL option `charset` controls parameter-value encoding:

1. no charset: keep an already URL-encoded value, otherwise use UTF-8;
2. `escape`: use the JavaScript-style escape helper;
3. another charset: run `URLEncoder.encode(value, charset)`.

Only values are passed through `URLEncoder`; field names are not transformed by
that branch. Form POST uses the same pre-encoded field map. JSON, XML, or a body
with an explicit Content-Type remains a raw request body. OkHttp encodes a raw
string with the media type charset, defaulting to UTF-8 when the media type does
not declare one. The URL option charset does not override raw-body encoding.

### Response decoding

`ResponseBody.text` reads the bytes once and removes a leading UTF-8 BOM. It
then selects the charset in this order:

1. explicit decoder argument;
2. HTTP Content-Type charset;
3. charset detected from HTML meta declarations or the bundled ICU detector.

The normal `AnalyzeUrl.getStrResponseAwait` path does not pass its request URL
option charset as the explicit response charset. Request encoding and response
decoding are separate concerns.

Java `String(bytes, Charset)` replaces malformed input rather than throwing for
ordinary decoder errors. An invalid or unknown charset name can still fail when
`Charset.forName` resolves it.

## Swift behavior

`FoundationTextDecoder` and `FoundationTextEncoder` delegate to one internal
cross-platform codec. The public supported set is:

- UTF-8;
- UTF-16, UTF-16LE, and UTF-16BE;
- ASCII;
- ISO-8859-1 / Latin-1;
- GBK;
- GB2312;
- GB18030;
- Big5.

Common aliases are normalized case-insensitively. Windows uses code pages 936,
54936, and 950. GB2312 decoding validates the narrower GB2312 byte ranges before
using CP936, and encoding rejects CP936 output outside those ranges. Darwin
decodes GB2312 and GBK runs directly with `CFStringCreateWithBytes` and the
official `CFStringEncodings` cases. Other supported Chinese encodings use the
documented CoreFoundation-to-`NSStringEncoding` conversion. Chinese response
data is decoded in contiguous valid runs so stateful platform codecs receive
the complete byte stream. No UI or other Apple-only framework is imported into
LegadoCore.

On Darwin, GB2312 and GBK encoding uses the system-supported GB18030 codec and
then validates every emitted unit against the narrower requested byte range.
This avoids unsupported legacy Foundation encoding identifiers while still
rejecting GBK-only characters for GB2312 and four-byte GB18030 output for GBK.
The Windows code-page path is unchanged.

Malformed GBK-family or Big5 units produce U+FFFD while valid following bytes
continue decoding, matching Android's replacement behavior. Unknown names
produce `HTTPError.unsupportedCharset`. A supported encoding that cannot
represent a string produces `HTTPError.encodingFailed`; invalid bytes for the
existing strict Foundation codecs may produce `HTTPError.decodingFailed`.

`HTTPResponse.text` converts response bytes to a Swift Unicode string before a
search, explore, book-info, TOC, or content parser sees the body. It uses:

1. UTF-8, UTF-16LE, or UTF-16BE BOM;
2. an explicit caller charset, when supplied;
3. HTTP Content-Type charset;
4. HTML meta charset found in the first 16 KiB, including legacy http-equiv;
5. strict UTF-8, then GB18030 (which includes GBK/GB2312), then Big5.

Unknown declarations and decoders that reject malformed bytes do not stop the
candidate sequence. A candidate containing replacement characters is retained
only as a final lossy result while cleaner declarations and fallbacks are tried.
If every candidate fails, `HTTPError.responseDecodingFailed` lists the attempted
charsets without response data or credentials, making the affected runtime's
existing `responseDecodeFailed` diagnostic actionable.

`RequestBuilder` uses URL option charset for GET and form values. It preserves
existing percent escapes only in the no-explicit-charset GET path. Raw POST uses
the Content-Type charset, or UTF-8 when absent.

## Offline test coverage

Binary-style hexadecimal fixtures live under `TestSources/charset` for GBK,
GB2312, GB18030, Big5, and malformed GBK input. Tests cover:

- decoding all four Chinese encodings;
- encoding representative simplified and traditional Chinese text;
- aliases;
- UTF-8 BOM removal;
- malformed-byte replacement;
- typed unsupported and encoding errors;
- BOM/explicit/Header/meta/fallback response priority;
- missing, unknown, and incorrect declaration recovery;
- UTF-16 BOM recognition and diagnostic aggregation when all decoders fail;
- GBK GET values;
- GB18030 form POST values;
- raw POST Content-Type charset;
- UTF-8, UTF-16, ASCII, and Latin-1 regression behavior through the existing
  networking tests.

All formal tests are fixture-based and perform no live network access.

## Compatibility differences and unsupported behavior

- Android can use bundled ICU statistical detection when neither HTTP nor HTML
  declares a charset. Swift uses the deterministic UTF-8/GB18030/Big5 sequence;
  it does not attempt statistical language detection, so byte streams valid as
  both GB18030 and Big5 require a correct declaration for reliable distinction.
- URL option `charset: "escape"` remains unsupported.
- Arbitrary JVM charset names outside the documented set remain unsupported.
- Darwin compilation and behavior require macOS/iOS CI verification; Windows
  verification does not prove Apple-platform compilation.

These boundaries return typed errors. They are not silently treated as UTF-8
and are never bypassed for a particular source URL or source name.
