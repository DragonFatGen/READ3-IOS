# Legado book-source model mapping

## Evidence and scope

This mapping is based on the following Android sources, not inferred from field names:

- `app/src/main/java/io/legado/app/data/entities/BookSource.kt`
- `app/src/main/java/io/legado/app/data/entities/BaseSource.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/BookListRule.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/SearchRule.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/ExploreRule.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/BookInfoRule.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/TocRule.kt`
- `app/src/main/java/io/legado/app/data/entities/rule/ContentRule.kt`
- `app/src/main/java/io/legado/app/help/SourceAnalyzer.kt`
- `app/src/main/java/io/legado/app/constant/BookType.kt`
- `app/src/main/java/io/legado/app/constant/AppConst.kt`
- `app/src/main/java/io/legado/app/utils/GsonExtensions.kt`
- `app/src/main/java/io/legado/app/utils/JsonExtensions.kt`

“Current use” below describes READ3-IOS at this model-only stage. “Stored” means decoded and encoded but not executed. “Preserve” means semantic JSON round-trip preservation, not byte-for-byte whitespace or object-key ordering.

## BookSource and BaseSource fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| BookSource | bookSourceUrl | bookSourceUrl | String | String | `""` | No | Required by old importer; missing current input remains `""` | Stored identity | Yes |
| BookSource | bookSourceName | bookSourceName | String | String | `""` | No | Old importer also defaults to `""` | Stored metadata | Yes |
| BookSource | bookSourceGroup | bookSourceGroup | String? | String? | null | Yes | Same key | Stored metadata | Yes |
| BookSource | bookSourceType | bookSourceType | Int | Int | `0` | No | `"AUDIO"`→1, other old string values→0 | Stored typed value | Yes |
| BookSource | bookUrlPattern | bookUrlPattern | String? | String? | null | Yes | `ruleBookUrlPattern` | Stored | Yes |
| BookSource | customOrder | customOrder | Int | Int | `0` | No | `serialNumber` | Stored | Yes |
| BookSource | enabled | enabled | Boolean | Bool | `true` | No | `enable` | Stored | Yes |
| BookSource | enabledExplore | enabledExplore | Boolean | Bool | `true` | No | Old import sets false when no discovery URL | Stored | Yes |
| BookSource/BaseSource | concurrentRate | concurrentRate | String? | String? | null | Yes | Same key | Stored, not enforced | Yes |
| BookSource/BaseSource | header | header | String? | String? | null | Yes | `httpUserAgent` becomes `{"User-Agent":...}` | Stored, not parsed | Yes |
| BookSource/BaseSource | loginUrl | loginUrl | String? | String? | null | Yes | Object form reads its `url`; string retained | Stored, not executed | Normalized |
| BookSource/BaseSource | loginUi | loginUi | String? | String? | null | Yes | Array/object form becomes a JSON string | Stored, not rendered | Normalized |
| BookSource | loginCheckJs | loginCheckJs | String? | String? | null | Yes | Same key | Stored, not executed | Yes |
| BookSource | bookSourceComment | bookSourceComment | String? | String? | null | Yes | Old importer supplies `""` | Stored metadata | Yes |
| BookSource | lastUpdateTime | lastUpdateTime | Long | Int64 | `0` | No | Same key | Stored metadata | Yes |
| BookSource | respondTime | respondTime | Long | Int64 | `180000L` | No | Same key | Stored metadata | Yes |
| BookSource | weight | weight | Int | Int | `0` | No | Same key | Stored metadata | Yes |
| BookSource | exploreUrl | exploreUrl | String? | String? | null | Yes | `ruleFindUrl` | Stored, not requested | Yes |
| BookSource | ruleExplore | ruleExplore | ExploreRule? | ExploreRule? | null | Yes | Object or JSON-object string; legacy root fields | Stored, not executed | Yes |
| BookSource | searchUrl | searchUrl | String? | String? | null | Yes | `ruleSearchUrl` | Executed by `BookSourceSearchRuntime` | Yes |
| BookSource | ruleSearch | ruleSearch | SearchRule? | SearchRule? | null | Yes | Object or JSON-object string; legacy root fields | Book-list and search fields executed | Yes |
| BookSource | ruleBookInfo | ruleBookInfo | BookInfoRule? | BookInfoRule? | null | Yes | Object or JSON-object string; legacy root fields | Stored, not executed | Yes |
| BookSource | ruleToc | ruleToc | TocRule? | TocRule? | null | Yes | Object or JSON-object string; legacy root fields | Stored, not executed | Yes |
| BookSource | ruleContent | ruleContent | ContentRule? | ContentRule? | null | Yes | Object or JSON-object string; legacy root fields | Stored, not executed | Yes |

`BookType.kt` defines 0=text, 1=audio, and 2=image. Swift intentionally keeps the property as `Int`, matching Kotlin and retaining future numeric values instead of rejecting them through a closed enum.

## SearchRule fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| SearchRule | checkKeyWord | checkKeyWord | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| SearchRule/BookListRule | bookList | bookList | String? | String? | null | Yes | `ruleSearchList` | Stored | Yes |
| SearchRule/BookListRule | name | name | String? | String? | null | Yes | `ruleSearchName` | Stored | Yes |
| SearchRule/BookListRule | author | author | String? | String? | null | Yes | `ruleSearchAuthor` | Stored | Yes |
| SearchRule/BookListRule | intro | intro | String? | String? | null | Yes | `ruleSearchIntroduce` | Stored | Yes |
| SearchRule/BookListRule | kind | kind | String? | String? | null | Yes | `ruleSearchKind` | Stored | Yes |
| SearchRule/BookListRule | lastChapter | lastChapter | String? | String? | null | Yes | `ruleSearchLastChapter` | Stored | Yes |
| SearchRule/BookListRule | updateTime | updateTime | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| SearchRule/BookListRule | bookUrl | bookUrl | String? | String? | null | Yes | `ruleSearchNoteUrl` | Stored | Yes |
| SearchRule/BookListRule | coverUrl | coverUrl | String? | String? | null | Yes | `ruleSearchCoverUrl` | Stored | Yes |
| SearchRule/BookListRule | wordCount | wordCount | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |

## ExploreRule fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| ExploreRule/BookListRule | bookList | bookList | String? | String? | null | Yes | `ruleFindList` | Stored | Yes |
| ExploreRule/BookListRule | name | name | String? | String? | null | Yes | `ruleFindName` | Stored | Yes |
| ExploreRule/BookListRule | author | author | String? | String? | null | Yes | `ruleFindAuthor` | Stored | Yes |
| ExploreRule/BookListRule | intro | intro | String? | String? | null | Yes | `ruleFindIntroduce` | Stored | Yes |
| ExploreRule/BookListRule | kind | kind | String? | String? | null | Yes | `ruleFindKind` | Stored | Yes |
| ExploreRule/BookListRule | lastChapter | lastChapter | String? | String? | null | Yes | `ruleFindLastChapter` | Stored | Yes |
| ExploreRule/BookListRule | updateTime | updateTime | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| ExploreRule/BookListRule | bookUrl | bookUrl | String? | String? | null | Yes | `ruleFindNoteUrl` | Stored | Yes |
| ExploreRule/BookListRule | coverUrl | coverUrl | String? | String? | null | Yes | `ruleFindCoverUrl` | Stored | Yes |
| ExploreRule/BookListRule | wordCount | wordCount | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |

## BookInfoRule fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| BookInfoRule | init | init | String? | String? | null | Yes | `ruleBookInfoInit` | Stored | Yes |
| BookInfoRule | name | name | String? | String? | null | Yes | `ruleBookName` | Stored | Yes |
| BookInfoRule | author | author | String? | String? | null | Yes | `ruleBookAuthor` | Stored | Yes |
| BookInfoRule | intro | intro | String? | String? | null | Yes | `ruleIntroduce` | Stored | Yes |
| BookInfoRule | kind | kind | String? | String? | null | Yes | `ruleBookKind` | Stored | Yes |
| BookInfoRule | lastChapter | lastChapter | String? | String? | null | Yes | `ruleBookLastChapter` | Stored | Yes |
| BookInfoRule | updateTime | updateTime | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| BookInfoRule | coverUrl | coverUrl | String? | String? | null | Yes | `ruleCoverUrl` | Stored | Yes |
| BookInfoRule | tocUrl | tocUrl | String? | String? | null | Yes | `ruleChapterUrl` | Stored | Yes |
| BookInfoRule | wordCount | wordCount | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| BookInfoRule | canReName | canReName | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |

## TocRule fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| TocRule | chapterList | chapterList | String? | String? | null | Yes | `ruleChapterList` | Stored | Yes |
| TocRule | chapterName | chapterName | String? | String? | null | Yes | `ruleChapterName` | Stored | Yes |
| TocRule | chapterUrl | chapterUrl | String? | String? | null | Yes | `ruleContentUrl` | Stored | Yes |
| TocRule | isVolume | isVolume | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| TocRule | isVip | isVip | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| TocRule | isPay | isPay | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| TocRule | updateTime | updateTime | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| TocRule | nextTocUrl | nextTocUrl | String? | String? | null | Yes | `ruleChapterUrlNext` | Stored | Yes |

## ContentRule fields

| Android class | Kotlin field | JSON field | Kotlin type | Swift type | Android default | Optional | Legacy compatibility | Current use | Preserve |
|---|---|---|---|---|---|---|---|---|---|
| ContentRule | content | content | String? | String? | null | Yes | `ruleBookContent` | Stored | Yes |
| ContentRule | nextContentUrl | nextContentUrl | String? | String? | null | Yes | `ruleContentUrlNext` | Stored | Yes |
| ContentRule | webJs | webJs | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| ContentRule | sourceRegex | sourceRegex | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| ContentRule | replaceRegex | replaceRegex | String? | String? | null | Yes | `ruleBookContentReplace` | Stored | Yes |
| ContentRule | imageStyle | imageStyle | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |
| ContentRule | payAction | payAction | String? | String? | null | Yes | No old root equivalent found | Stored | Yes |

## Serialization and legacy behavior

- `BookSource` Codable handles only the current structured representation and unknown-field preservation. Alternate representations and legacy keys are handled by `BookSourceImporter` and `LegacySourceNormalizer`.
- `SourceAnalyzer.BookSourceAny` accepts rule objects as objects or JSON-object strings. The importer normalizes both to structured objects before `BookSource` decoding.
- `loginUi` object/array values and `loginUrl` string/object/array values are normalized by the importer. See `docs/source-import-normalization.md` for preservation and Android differences.
- `GsonExtensions.IntJsonDeserializer` accepts numeric JSON primitives for `Int`. The importer normalizes compatible numeric representations before strict model decoding.
- Safe legacy root fields move into current fields and are removed. Unsupported legacy values remain as unknown fields, while conflicts select the current field and produce explicit warnings.
- `SourceAnalyzer.toNewRule`, `toNewUrl`, and `toNewUrls` compatibility rewrites occur during import only; no rule or request is executed.
- Android decides that a source is old when `BookSourceAny.ruleToc == null`. Swift uses individual legacy keys, so a valid current source that omits optional `ruleToc` is not accidentally migrated.

## Custom variables

The analyzed `BookSource` and `BookSourceAny` definitions contain no serialized custom-variable field. `BaseSource.setVariable` and `getVariable` store a runtime string in `CacheManager` under `sourceVariable_<source key>`. That state is not part of exported book-source JSON and is therefore not invented as a Swift model property. If a source JSON contains a future or third-party variable configuration key, the unknown-field mechanism preserves it as `JSONValue` without interpreting or executing it.

## Unknown fields

Every Swift source and rule model has an `extraFields: [String: JSONValue]` property. Decoding collects keys not listed by that model. Encoding writes those values first and excludes all known key names, then writes typed fields, so a conflicting entry in `extraFields` can never replace a known property. `JSONValue` supports null, Boolean, signed integer, floating-point number, string, array, and object values.
