# Legado legacy book-source import and normalization

## Scope and evidence

This document describes JSON import only. It does not execute selectors, JavaScript, or network requests. The Android behavior was read from these repository files:

- `Reference/READ3.0/app/src/main/java/io/legado/app/help/SourceAnalyzer.kt`
  - `jsonToBookSource`, lines 69–210
  - `BookSourceAny`, lines 212–238
  - `toNewRule`, lines 240–296
  - `toNewUrls`, lines 298–310
  - `toNewUrl`, lines 312–359
  - `uaToHeader`, lines 361–365
- `Reference/READ3.0/app/src/main/java/io/legado/app/utils/GsonExtensions.kt`
  - GSON registration, lines 14–26
  - `IntJsonDeserializer`, lines 81–104
- `Reference/READ3.0/app/src/main/java/io/legado/app/utils/JsonExtensions.kt`
  - `ReadContext.readString`, line 13
- `Reference/READ3.0/app/src/main/java/io/legado/app/constant/BookType.kt`
  - numeric text/audio/image values

`SourceAnalyzer.jsonToBookSource` first decodes `BookSourceAny`. Android selects the entire legacy branch when `sourceAny?.ruleToc == null` (line 76), rather than detecting individual old fields. The Swift importer deliberately uses per-field detection because a current source is allowed to omit `ruleToc`.

## Import pipeline

```text
raw Data
→ JSONValue
→ legacy and alternate-representation detection
→ LegacySourceNormalizer
→ strict BookSource Codable decoding
→ SourceImportResult
```

`BookSource` only reads and writes the current structured representation and preserves unknown fields. It does not perform migrations. `SourceImportResult.normalizedJSON` is sorted-key UTF-8 JSON produced from the decoded `BookSource`.

## Examples

Legacy root rule:

```json
{
  "bookSourceUrl": "https://example.invalid",
  "ruleSearchList": ".book",
  "ruleSearchName": ".name@text"
}
```

Normalized form:

```json
{
  "bookSourceUrl": "https://example.invalid",
  "ruleSearch": {
    "bookList": ".book",
    "name": ".name@text"
  }
}
```

String rule object:

```json
{"ruleToc":"{\"chapterList\":\".chapter\"}"}
```

Normalized form:

```json
{"ruleToc":{"chapterList":".chapter"}}
```

## Migration matrix

| Old input | Android function and actual behavior | Swift strategy | Conflict | Warning | Original retained | Difference |
|---|---|---|---|---|---|---|
| `ruleSearchList`, `ruleSearchName`, `ruleSearchAuthor`, `ruleSearchIntroduce`, `ruleSearchKind`, `ruleSearchNoteUrl`, `ruleSearchCoverUrl`, `ruleSearchLastChapter` | `jsonToBookSource` lines 98–107 builds `SearchRule`; every value passes through `toNewRule` | Move safe strings to `ruleSearch` using the same field mapping and syntax rewrite | Existing `ruleSearch` wins | Yes | Safe duplicates removed; unsupported values remain | Per-field detection instead of `ruleToc == null` |
| `ruleFindList`, `ruleFindName`, `ruleFindAuthor`, `ruleFindIntroduce`, `ruleFindKind`, `ruleFindNoteUrl`, `ruleFindCoverUrl`, `ruleFindLastChapter` | Lines 108–117 build `ExploreRule` through `toNewRule` | Move to `ruleExplore` | Existing `ruleExplore` wins | Yes | Same policy | Detection differs |
| `ruleBookInfoInit`, `ruleBookName`, `ruleBookAuthor`, `ruleIntroduce`, `ruleBookKind`, `ruleCoverUrl`, `ruleBookLastChapter`, `ruleChapterUrl` | Lines 118–127 build `BookInfoRule` | Move to `ruleBookInfo` | Existing `ruleBookInfo` wins | Yes | Same policy | Detection differs |
| `ruleChapterList`, `ruleChapterName`, `ruleContentUrl`, `ruleChapterUrlNext` | Lines 128–133 build `TocRule` | Move to `ruleToc` | Existing `ruleToc` wins | Yes | Same policy | Detection differs |
| `ruleBookContent`, `ruleBookContentReplace`, `ruleContentUrlNext` | Lines 134–142 build `ContentRule`; a leading `$` is removed from content unless it begins `$.` | Move to `ruleContent`, apply `toNewRule`, then apply the content `$` special case | Existing `ruleContent` wins | Yes | Same policy | Detection differs |
| `ruleBookUrlPattern` | Line 87 copies to `bookUrlPattern` | Rename | Modern wins | Yes on conflict | Safe duplicate removed | None |
| `serialNumber` | Line 88 reads an integer and copies to `customOrder` | Accept an in-range JSON number or numeric string, then rename | Modern wins | Conflict/coercion as applicable | Unsafe value remains | Numeric strings are accepted beyond Android `IntJsonDeserializer` |
| `enable` | Line 94 copies Boolean to `enabled`, defaulting true | Rename Boolean | Modern wins | Yes on conflict/unsupported type | Unsafe value remains | None |
| `httpUserAgent` | Lines 89 and 361–365 serialize it as a `User-Agent` header object string | Produce a deterministic JSON object string and rename to `header` | Modern wins | Yes on conflict | Safe duplicate removed | Whitespace/key order may differ |
| `ruleSearchUrl` | Line 90 calls `toNewUrl` | Rewrite legacy placeholders/options and move to `searchUrl` | Modern wins | Yes on conflict | Unsafe value remains | Normalized option JSON is compact/sorted |
| `ruleFindUrl` | Line 91 calls `toNewUrls` | Split newline/`&&`, call `toNewUrl`, join with newline, move to `exploreUrl` | Modern wins | Yes on conflict | Unsafe value remains | Normalized option JSON is compact/sorted |
| `bookSourceType` string | Lines 92–93 map exact `AUDIO` to audio type and other legacy strings to text | Map `AUDIO` to `1`; map other strings to `0` and preserve their value as `legacyBookSourceType` | Same-key representation migration | Yes for an unknown name | Unknown names retained under a non-conflicting key | Swift adds preservation for unknown names |
| rule object as JSON string | Lines 171–205 call Gson for each of the five rule types; parse failure becomes null | Require a valid JSON object string and replace it with an object | Not applicable | No | Replaced by object | Malformed strings throw `invalidRuleJSONString` instead of silently producing nil |
| `loginUrl` string | Lines 155–158 retain the string | Retain unchanged | Not applicable | No | Yes | None |
| `loginUrl` object | Lines 155–158 read its `url` member | Extract string `url`; if other members exist, preserve the complete object as `legacyLoginUrl` | Not applicable | Yes when extra members exist | Extra members retained in `legacyLoginUrl` | Swift prevents loss of extra members |
| `loginUrl` array | The non-string branch attempts `readString("url")`; the Android code has no array-specific handling and may fail | Serialize the complete array into the string-valued current field | Not applicable | Yes | Entire array retained semantically | Intentional safe extension |
| blank legacy discovery URL | Lines 95–97 set `enabledExplore = false` after `toNewUrls` returns null | Remove safely handled blank `ruleFindUrl`; set `enabledExplore` false only if it was absent | Existing `enabledExplore` wins | No | Blank duplicate removed | Explicit modern enablement is respected |
| current numeric fields | `IntJsonDeserializer` accepts numeric JSON primitives, uses `toInt`, and returns null for non-numeric primitives; Gson handles `Long` separately | Coerce finite in-range decimals toward zero and numeric strings to integers; use Android 32-bit bounds for Int fields and 64-bit bounds for Long fields | Not applicable | Yes on representation change | Replaced by integer | Numeric strings are an intentional permissive extension; overflow is an error |
| unsupported old value type | Old branch's typed JsonPath reads can fail the whole import | Do not create a modern value; retain the original root key | Modern field, if any, remains authoritative | Yes | Yes | Swift favors recoverable preservation |

## `toNewRule` behavior

Android lines 240–296 preserve a leading `-` and then `+`, skip rewriting for CSS/XPath, `//`, `##`, `:`, and JavaScript-marked rules, and otherwise perform these compatibility changes:

- single `#` becomes `##`;
- single `|` becomes `||` (only before a regex-replacement suffix when present);
- single `&` becomes `&&` unless the rule contains `http` or starts with `/`.

Swift performs these migrations as strings only. It does not parse or execute the resulting rule.

## `toNewUrl` and `toNewUrls` behavior

Android lines 298–359:

- retain leading `@js:`/`<js>` multi-URL values;
- split discovery entries on newline or `&&`;
- change `searchKey` and `searchPage` placeholders to `{{key}}` and `{{page}}` forms;
- move `@Header:{...}` into a request-option object;
- move a pipe charset suffix into `charset`;
- move an `@body` suffix into `method: POST` and `body`;
- temporarily shields `{{...}}` script fragments while replacing placeholders.

Swift normalizes the serialized request string but does not issue an HTTP request.

## Conflict and preservation policy

Modern fields always win. A safe legacy string, number, or Boolean is interpreted before removal, so a duplicate cannot overwrite the modern value. A `modernFieldWonConflict` warning and `discardedLegacyConflict` migration record make the decision explicit. Unsupported legacy types stay under their original root keys and produce `unsupportedLegacyValuePreserved`; they therefore enter `BookSource.extraFields` and are re-encoded.

Unknown fields at the source and nested rule levels continue to use `[String: JSONValue]`. Known typed fields always override same-named entries during encoding.

## Idempotence

The importer emits only current typed fields, deliberately preserved unsupported fields, and unknown fields. Re-importing `normalizedJSON` performs no further migration:

```text
normalize(normalize(input)) == normalize(input)
```

Equality here is byte equality of the sorted-key normalized JSON output, not equality with the original whitespace or object-key order.

## Warnings, migrations, and errors

Warnings are non-fatal observations with a stable code, field, and readable message. Migrations contain a stable kind, all source fields, destination field, and summary. Invalid JSON, a non-object top level, malformed JSON-string rule objects, invalid current-field representations, overflow, and normalized model failures are typed `SourceImportError` values.

No warning or error includes source contents, headers, cookies, tokens, or login form values.
