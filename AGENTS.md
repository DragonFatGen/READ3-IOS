# AGENTS.md
# AGENTS.md

## 1. Project Overview

This repository implements an iOS reading application compatible with the core data formats and rule semantics of Android Legado / 阅读 3.0.

The Android source code under `Reference/READ3.0` is reference material only.

This project is a native Swift rewrite. It is not a line-by-line Kotlin-to-Swift translation.

Primary goals:

1. Import Legado book-source JSON files.
2. Preserve commonly used source-rule semantics.
3. Support book search, book information, table of contents, and chapter content retrieval.
4. Provide a native iOS reading interface.
5. Keep the reusable parsing and data-model layers testable on Windows.
6. Build and validate Apple-specific code through macOS CI.

---

## 2. Development Environment

### Primary local environment

* Operating system: Windows 10
* Shell: PowerShell 7
* Preferred executable: `pwsh`
* Source control: Git
* Primary coding agent: Codex
* Local Swift environment: Swift for Windows
* Local editor: VS Code or Codex for Windows

Always prefer PowerShell 7 commands.

Do not provide Bash-only commands for local Windows operations unless the command is explicitly intended for GitHub Actions or a remote macOS runner.

Example:

```powershell
pwsh -NoProfile -Command "swift test --package-path Packages/LegadoCore"
```

### Apple build environment

Apple-specific code is built on:

* GitHub Actions macOS runners;
* Codemagic macOS builders; or
* another remote macOS machine with Xcode.

Do not claim that an iOS target compiles successfully unless it has been verified by Xcode or a macOS CI workflow.

Windows Swift compilation does not prove that SwiftUI, UIKit, WebKit, JavaScriptCore, AVFoundation, or other Apple-framework code compiles.

---

## 3. Repository Structure

Expected repository structure:

```text
READ3-IOS/
├── AGENTS.md
├── README.md
├── project.yml
├── Reference/
│   └── READ3.0/
├── Packages/
│   └── LegadoCore/
│       ├── Package.swift
│       ├── Sources/
│       └── Tests/
├── Apple/
│   └── LegadoIOS/
│       ├── App/
│       ├── Features/
│       ├── Infrastructure/
│       └── Resources/
├── TestSources/
│   ├── css/
│   ├── jsonpath/
│   ├── xpath/
│   ├── javascript/
│   ├── encoding/
│   └── expected/
├── Scripts/
├── docs/
└── .github/
    └── workflows/
```

### Directory responsibilities

#### `Reference/READ3.0`

Contains the Android Legado source code.

Rules:

* Treat this directory as read-only reference material.
* Do not modify it unless explicitly requested.
* Do not mechanically port Android classes.
* Extract behavior, JSON fields, default values, and rule semantics.
* Do not include Android-generated files in the new implementation.

#### `Packages/LegadoCore`

Contains platform-neutral Swift code.

This package must compile and run tests on Windows and macOS.

It must not import Apple-only frameworks.

#### `Apple/LegadoIOS`

Contains Apple-platform implementations and application UI.

Examples:

* SwiftUI;
* UIKit;
* WebKit;
* JavaScriptCore;
* AVFoundation;
* CoreText;
* TextKit;
* Apple-specific URLSession behavior;
* iOS persistence adapters.

#### `TestSources`

Contains deterministic book-source JSON, HTML, JSON responses, scripts, expected results, and encoding samples used by automated tests.

Tests must not depend unnecessarily on live websites.

---

## 4. Architectural Principles

### 4.1 Separate core logic from Apple frameworks

All reusable parsing, models, rule syntax, request construction, and result transformation must live in `LegadoCore`.

The following imports are prohibited inside `Packages/LegadoCore`:

```swift
import SwiftUI
import UIKit
import AppKit
import WebKit
import JavaScriptCore
import AVFoundation
import CoreText
```

Use protocols to isolate platform-specific functionality.

Example:

```swift
public protocol SourceHTTPClient: Sendable {
    func execute(_ request: SourceRequest) async throws -> SourceResponse
}

public protocol SourceJavaScriptRuntime: Sendable {
    func evaluate(
        script: String,
        context: JavaScriptExecutionContext
    ) async throws -> JavaScriptValue
}

public protocol HTMLSelectorEngine: Sendable {
    func select(
        input: String,
        rule: SelectorRule
    ) throws -> [String]
}
```

Apple-specific implementations belong under `Apple/LegadoIOS`.

### 4.2 Prefer explicit intermediate representations

Do not execute raw source rules directly throughout the codebase.

Parse rule text into explicit intermediate structures.

Example:

```swift
public enum RuleExpression: Sendable, Equatable {
    case css(String)
    case jsonPath(String)
    case xpath(String)
    case regex(RegexRule)
    case javaScript(String)
    case template(TemplateRule)
    case sequence([RuleExpression])
    case fallback([RuleExpression])
}
```

This makes rule execution testable and prevents parser behavior from being coupled to networking or UI code.

### 4.3 Use dependency injection

Core services must depend on protocols instead of concrete Apple implementations.

Avoid global mutable state and singleton-heavy designs.

Preferred:

```swift
public struct SourceEngine {
    private let httpClient: any SourceHTTPClient
    private let javaScriptRuntime: any SourceJavaScriptRuntime
    private let selectorEngine: any HTMLSelectorEngine
}
```

Avoid:

```swift
SourceManager.shared
NetworkManager.shared
GlobalCookieStore.shared
```

### 4.4 Preserve original source data

Book-source JSON import must preserve unknown or unsupported fields whenever practical.

Do not silently discard source fields merely because the current iOS implementation does not use them.

Where necessary, store unsupported values in an extension dictionary.

---

## 5. Initial Implementation Order

Implement features in this order unless a task explicitly overrides it.

### Phase 1: Source models

Implement Codable models compatible with the Android book-source JSON format:

1. `BookSource`
2. `SearchRule`
3. `ExploreRule`
4. `BookInfoRule`
5. `TocRule`
6. `ContentRule`
7. source login-related fields
8. source header and custom variable fields

Requirements:

* Preserve original JSON field names.
* Match Android defaults where they can be determined.
* Accept missing optional fields.
* Accept common legacy formats.
* Add round-trip import/export tests.
* Add fixtures based on real source JSON files.

### Phase 2: Rule parsing

Implement parsing for:

1. normal selector rules;
2. CSS rules;
3. JSONPath rules;
4. XPath rules;
5. JavaScript-prefixed rules;
6. regular-expression replacement;
7. `&&` sequential composition;
8. fallback or alternative rule syntax;
9. `{{variable}}` templates;
10. relative URL completion;
11. rule suffixes and modifiers used by common Legado sources.

Parsing and execution must remain separate.

### Phase 3: HTTP abstraction

Implement platform-neutral request models:

* URL;
* method;
* headers;
* body;
* character encoding;
* retry information;
* redirect behavior;
* cookie behavior;
* source context.

Do not use `URLSession` directly inside `LegadoCore`.

### Phase 4: Deterministic rule execution

Implement and test:

* string extraction;
* list extraction;
* attribute extraction;
* text extraction;
* regex replacement;
* URL resolution;
* JSON traversal;
* selector chaining;
* variables;
* result normalization.

### Phase 5: Apple implementations

Implement on the Apple side:

* `URLSessionSourceHTTPClient`;
* `JavaScriptCoreRuntime`;
* `WKWebViewLoginService`;
* cookie synchronization;
* iOS storage;
* SwiftUI application navigation.

### Phase 6: Reading interface

Implement only after the source engine is stable:

* bookshelf;
* search;
* book detail;
* chapter list;
* chapter loading;
* reading progress;
* font and theme settings;
* scrolling reader;
* paginated reader;
* TXT import;
* EPUB support;
* text-to-speech.

---

## 6. Compatibility Scope

The first objective is not complete parity with every Android source.

Prioritize commonly used sources and deterministic behavior.

Compatibility levels:

### Level 1

* plain HTTP GET;
* plain HTTP POST;
* UTF-8;
* basic headers;
* CSS selectors;
* basic JSONPath;
* basic XPath;
* regex replacement;
* relative URL resolution.

### Level 2

* cookies;
* GBK and GB2312 decoding;
* variables;
* request option objects;
* redirects;
* custom headers;
* source-specific state;
* common JavaScript expressions.

### Level 3

* `java.ajax`;
* `java.get`;
* `java.post`;
* cookie bridge;
* Base64 helpers;
* source object bridge;
* login flows;
* WebView-dependent sources;
* complex Rhino compatibility behavior.

Do not mark full Legado compatibility as complete unless compatibility tests demonstrate it.

---

## 7. Android Reference Analysis

When analyzing Android code, focus on observable behavior.

Relevant areas include:

* source JSON model classes;
* `AnalyzeRule`;
* rule splitting;
* variable replacement;
* regular-expression replacement;
* URL construction;
* HTTP request creation;
* cookie handling;
* character encoding;
* JavaScript bridge functions;
* search flow;
* book information flow;
* table-of-contents flow;
* content flow.

Do not copy Android architecture blindly.

Android-specific concepts to replace include:

* `Parcelable`;
* Room annotations;
* Android lifecycle classes;
* Android `Context`;
* LiveData;
* ViewModel implementations coupled to Android;
* Rhino internals;
* WebView APIs;
* Android file and permission APIs.

Document significant behavioral conclusions under `docs/`.

---

## 8. Swift Coding Standards

### 8.1 Language and concurrency

Use modern Swift.

Prefer:

* `async/await`;
* `Sendable`;
* actors for protected mutable state;
* immutable structs;
* explicit error types;
* protocol-based dependencies.

Avoid callback pyramids unless required by an external API.

### 8.2 Naming

Use clear domain terminology.

Preferred names:

```swift
BookSource
SourceRuleParser
SourceRequest
SourceResponse
RuleExecutionContext
ChapterContent
BookSearchResult
TableOfContents
```

Avoid vague names such as:

```swift
Manager
Helper
Util
DataObj
CommonService
```

unless a more precise name is genuinely impossible.

### 8.3 Error handling

Do not swallow errors.

Define domain-specific errors.

Example:

```swift
public enum SourceEngineError: Error, Equatable {
    case invalidSourceURL(String)
    case unsupportedRule(String)
    case invalidResponseEncoding(String)
    case selectorExecutionFailed(String)
    case javaScriptExecutionFailed(String)
    case responseParsingFailed(String)
}
```

Errors exposed to the UI should contain:

* a user-readable description;
* the affected source;
* the affected stage;
* an optional underlying technical message.

Never include passwords, authentication headers, cookies, or private tokens in user-visible errors or logs.

### 8.4 Logging

Use structured logging.

Log fields should include, where applicable:

* source name;
* source URL;
* operation;
* rule type;
* request method;
* response status;
* elapsed time;
* error category.

Redact:

* cookies;
* authorization headers;
* passwords;
* login form values;
* tokens;
* private source variables.

### 8.5 Comments

Comments should explain:

* why compatibility behavior exists;
* which Android behavior is being matched;
* known incompatibilities;
* non-obvious edge cases.

Do not add comments that merely restate the code.

---

## 9. Testing Requirements

### 9.1 Core tests

Every change to `LegadoCore` must add or update tests when behavior changes.

Run locally:

```powershell
swift test --package-path Packages/LegadoCore
```

For verbose output:

```powershell
swift test --package-path Packages/LegadoCore --verbose
```

### 9.2 Test categories

Maintain tests for:

1. source JSON decoding;
2. source JSON encoding;
3. missing-field defaults;
4. legacy source formats;
5. CSS parsing;
6. JSONPath parsing;
7. XPath parsing;
8. regular-expression replacement;
9. variable substitution;
10. URL completion;
11. request creation;
12. character decoding;
13. rule sequencing;
14. fallback behavior;
15. malformed rules;
16. malformed responses;
17. unsupported JavaScript behavior.

### 9.3 Fixture-based tests

Prefer deterministic local fixtures over live website access.

Each compatibility fixture should include:

```text
input source
input response
rule
expected result
```

Suggested naming:

```text
TestSources/css/source.json
TestSources/css/search-response.html
TestSources/css/expected-search.json
```

### 9.4 Network tests

Live network tests must:

* be placed in a separate test suite;
* be disabled by default;
* have explicit timeouts;
* avoid depending on unstable third-party websites;
* never be required for every pull request.

---

## 10. Windows Command Rules

Use PowerShell 7 syntax for local commands.

### Correct

```powershell
New-Item -ItemType Directory -Force .\Packages\LegadoCore
Copy-Item .\source.json .\TestSources\css\source.json
Remove-Item -Recurse -Force .\.build
Get-ChildItem -Recurse
```

### Avoid for Windows instructions

```bash
mkdir -p
rm -rf
cp
grep
sed
awk
export
```

PowerShell pipelines and cmdlets are preferred.

When invoking native tools, check `$LASTEXITCODE`.

Example:

```powershell
swift test --package-path Packages/LegadoCore

if ($LASTEXITCODE -ne 0) {
    throw "Swift tests failed with exit code $LASTEXITCODE"
}
```

---

## 11. Git and Proxy Rules

Git proxy configuration must be repository-local unless explicitly requested otherwise.

Do not set a global Git proxy.

Configure the current repository:

```powershell
git config --local http.proxy http://127.0.0.1:3067
git config --local https.proxy http://127.0.0.1:3067
```

Inspect the source of proxy settings:

```powershell
git config --show-origin --get-regexp "http\..*proxy|https\..*proxy"
```

Remove the current repository proxy:

```powershell
git config --local --unset-all http.proxy
git config --local --unset-all https.proxy
```

For cloning a new repository before local configuration exists, use a temporary per-command proxy:

```powershell
git `
  -c http.proxy=http://127.0.0.1:3067 `
  -c https.proxy=http://127.0.0.1:3067 `
  clone https://github.com/FTH12/READ3.0.git .\Reference\READ3.0
```

Do not commit proxy addresses, credentials, API keys, signing certificates, or provisioning profiles.

---

## 12. Git Workflow

Before modifying code:

```powershell
git status
git branch --show-current
```

Do not overwrite unrelated user changes.

Keep commits focused.

Suggested commit prefixes:

```text
feat:
fix:
refactor:
test:
docs:
build:
ci:
chore:
```

Examples:

```text
feat: add Legado book source Codable models
test: add source JSON round-trip fixtures
fix: preserve unknown source fields during import
ci: add macOS simulator build workflow
```

Do not commit:

* `.build`;
* DerivedData;
* generated archives;
* `.ipa`;
* signing files;
* local environment files;
* access tokens;
* private book sources;
* downloaded copyrighted book content.

---

## 13. Xcode Project Generation

The project may use XcodeGen so that Windows contributors can maintain the Xcode project definition.

Primary file:

```text
project.yml
```

The generated `.xcodeproj` may be created on macOS CI.

Typical macOS commands:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LegadoIOS.xcodeproj -scheme LegadoIOS build
```

Do not run or suggest `xcodebuild` as a Windows command.

If generated Xcode project files are committed, keep `project.yml` as the source of truth.

Do not manually edit generated project files unless the repository explicitly chooses generated-file maintenance.

---

## 14. CI Requirements

The repository should have separate CI jobs.

### Core Swift tests

Run on Windows and macOS where practical.

Example responsibility:

```text
swift test --package-path Packages/LegadoCore
```

### iOS simulator build

Run on a macOS GitHub Actions runner.

Requirements:

* generate the Xcode project;
* run `xcodebuild`;
* disable code signing for simulator builds;
* upload logs when the build fails;
* upload the simulator `.app` only when useful.

### Signed device builds

Signed `.ipa` builds must be isolated from normal pull-request builds.

Secrets must be stored in:

* GitHub Actions secrets;
* Codemagic secure variables;
* App Store Connect integrations; or
* another approved secret store.

Never place signing material directly in the repository.

---

## 15. Security Requirements

Treat book-source definitions as untrusted input.

Potentially dangerous inputs include:

* JavaScript;
* URLs;
* HTTP headers;
* POST bodies;
* regular expressions;
* file paths;
* WebView login pages;
* custom variables.

Requirements:

1. Apply request timeouts.
2. Limit redirect counts.
3. Limit response body size.
4. Prevent arbitrary local file access.
5. Prevent source scripts from reading unrelated application data.
6. Separate cookies by source where possible.
7. Redact sensitive fields from logs.
8. Do not execute system commands from source scripts.
9. Do not expose arbitrary native APIs to JavaScript.
10. Add execution limits for expensive scripts and regular expressions.

The JavaScript bridge must use an explicit allowlist.

Do not attempt to reproduce arbitrary Android or JVM access from Rhino.

---

## 16. Legal and Distribution Constraints

The Android reference repository uses GPL-3.0 licensing.

Before distributing this project:

* preserve required copyright notices;
* review derivative-work obligations;
* include the applicable source-code offer;
* document third-party dependencies and licenses;
* avoid copying incompatible third-party code;
* review App Store distribution implications.

Do not remove existing attribution.

Do not add copyrighted books, private source collections, credentials, or unauthorized content to the repository.

The application should be positioned as a reader and source-rule engine, not as a bundled copyrighted-content distributor.

---

## 17. Definition of Done

A task is complete only when all applicable conditions are met.

### Core task

* implementation is present;
* relevant tests are present;
* Windows `swift test` passes;
* public API behavior is documented;
* no Apple-only imports exist in `LegadoCore`;
* no unrelated files are modified.

### Apple-specific task

* implementation is present;
* the Xcode project or XcodeGen definition is updated;
* macOS CI compiles the affected target;
* simulator tests pass where applicable;
* unsupported Windows verification is stated clearly.

### Compatibility task

* Android behavior was analyzed;
* expected behavior is documented;
* at least one deterministic fixture exists;
* differences from Android are documented;
* compatibility is not overstated.

---

## 18. Required Agent Behavior

When working in this repository, the agent must:

1. Inspect relevant files before editing.
2. Explain significant architectural choices in code or documentation.
3. Prefer small, testable changes.
4. Run available tests after edits.
5. Report the exact commands executed.
6. Report test and build failures honestly.
7. Distinguish Windows verification from macOS/Xcode verification.
8. Preserve unrelated user changes.
9. Avoid modifying `Reference/READ3.0`.
10. Avoid claiming full source compatibility prematurely.
11. Avoid one-file implementations for complex subsystems.
12. Avoid creating UI before the core source engine is sufficiently tested.
13. Never expose secrets in output, logs, commits, or test fixtures.

---

## 19. First Milestone

The first milestone is complete when the project can:

1. decode representative Legado book-source JSON;
2. encode it without losing supported fields;
3. preserve unknown fields where practical;
4. parse common source-rule syntax into an intermediate representation;
5. perform regular-expression replacement;
6. resolve relative URLs;
7. run all relevant tests on Windows;
8. build a minimal SwiftUI shell through macOS CI.

The first milestone does not require:

* complete JavaScript compatibility;
* WKWebView login;
* EPUB rendering;
* pagination;
* text-to-speech;
* App Store publication;
* compatibility with every Android source.

---

## 20. Standard Verification Commands

Run from the repository root.

### Check repository state

```powershell
git status
git diff --stat
```

### Run core tests

```powershell
swift test --package-path Packages/LegadoCore
```

### Clean Swift build output

```powershell
Remove-Item -Recurse -Force .\Packages\LegadoCore\.build -ErrorAction SilentlyContinue
```

### Check formatting or linting

Run only when the corresponding tools and configuration files exist.

Do not introduce a formatter or linter without documenting it and updating CI.

### Inspect changed files

```powershell
git diff --name-only
git diff
```

Before finishing a task, summarize:

* changed files;
* implemented behavior;
* tests executed;
* test results;
* remaining macOS verification;
* known limitations.


### PowerShell  使用规范
在 Windows 环境中执行命令、编写脚本或调用终端时：

- 优先使用 PowerShell 7，即 `pwsh`。
- 不要优先使用旧版 Windows PowerShell，即 `powershell.exe`。
- 调用 PowerShell 脚本时，优先使用：

  ```powershell
  pwsh -NoProfile -File .\script.ps1
  ```