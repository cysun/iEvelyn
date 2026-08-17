# Step 16 release-readiness record

This record covers the version 1.0 build 1 direct-download candidate. It records
what the repository enforces and separates those checks from credentialed or
second-Mac work that must be completed by the release owner.

## Product identity and distribution

- Product: iEvelyn
- Bundle identifier: org.cysun.iEvelyn
- Minimum system: macOS 26
- Version/build: 1.0 (1)
- Copyright: Copyright © 2026 Chengyu Sun. All rights reserved.
- Application category: Reference (`public.app-category.reference`)
- Distribution: Developer ID signed, notarized direct-download ZIP
- App Sandbox: enabled
- Hardened Runtime: enabled for Debug and Release

The final icon uses an original cream open-book and amber bookmark mark on deep
indigo. All ten macOS PNG sizes are provided in the AppIcon asset set. The
1024-pixel master was generated with OpenAI ImageGen and visually checked at
1024 and 16 pixels before integration.

## Accessibility and keyboard audit

- Library destinations use a native selectable sidebar and labelled rows.
- Books are exposed as named buttons with an Open Book hint; duplicate visible
  title buttons are hidden from accessibility.
- More menus, sort, presentation, search scope, organization filters, empty
  states, destructive confirmations, progress indicators, and error states
  have labels or descriptive visible text.
- Reader contents, bookmarks, toolbar controls, chapter navigation, Find in
  Book, appearance controls, render warnings, and persistence errors expose
  labels and stable accessibility identifiers.
- Main shortcuts: Command-Shift-N Add Book, Command-Shift-L All Books,
  Command-1 Grid, Command-2 List, Command-F search/find, B bookmark,
  Left/Right chapter navigation, and C reader-sidebar visibility.
- Library destination, sort, and presentation restore per scene. Reader route
  restoration uses the typed Codable window value. New reader windows start
  with the sidebar collapsed and reader panel focused; expanding the sidebar
  focuses its chapter list, and collapsing it restores reader-panel focus.
  Reader location and appearance persist in the canonical database and
  UserDefaults respectively.
- SwiftUI's macOS 26 WebView does not expose reliable first-responder or bare-key
  command handling. One isolated AppKit bridge scopes reader key monitoring and
  focus requests to that reader window while excluding text-entry responders.

A computer-assisted accessibility-tree and visual audit covered the Library
grid/list, sidebar, menus, Add Book, and About window. It found and resolved a
missing Library Command-F focus path and an About container that hid its child
text nodes. The final manual checkpoint still requires a keyboard-only and
VoiceOver pass against the signed release candidate.

## Recovery audit

- Empty, loading, search-empty, Trash-empty, validation, render, persistence,
  and file-operation failures have explicit UI.
- Missing stored covers fall back to generated artwork and report an actionable
  replace/remove message.
- A library-open failure exposes Try Again and Restore from Backup.
- Recovery restore does not require the damaged database to open. It validates
  and stages the complete backup, atomically exchanges sibling directories,
  reopens the replacement, and swaps the previous directory back if activation
  fails.
- Check Library Integrity reports database, foreign-key, asset, and search-index
  status. It only removes orphaned files and rebuilds derived search data.

## Concurrency, I/O, privacy, and entitlement audit

- UI-owned observable state remains MainActor isolated.
- Database work uses GRDB's writer/read boundaries; asset, archive, hashing,
  rendering, EPUB, import, and restore services are actors or Sendable
  boundaries away from view bodies.
- Search, rendering, progress persistence, backup/restore, import, and export
  contain cancellation checks at their long-running boundaries.
- Production source contains one structured OSLog message for failed cleanup of
  an ephemeral test asset directory. It contains no content, UUID, credential,
  or path.
- The entitlements are App Sandbox, user-selected read/write files, and outgoing
  network client. The client entitlement remains necessary for the sandboxed
  WebKit content process; generated-content CSP and navigation policy prevent
  book content from initiating network loads.
- No telemetry, analytics, updater, cloud service, account, secret, or broad
  filesystem entitlement is present.

## Performance audit

Automated release-readiness tests exercise a 20,000-book local query and a
2,000-paragraph controlled Markdown render with conservative Debug-build
budgets. Existing storage uses lazy grids/lists, lazy cover loading, a bounded
thumbnail cache, indexed GRDB observation/search, debounced search/rendering,
and bounded rendered-document caching.

On the final full-suite run, the 20,000-book query completed in 0.037 seconds,
the representative indexed-search dataset completed in 0.395 seconds, and the
2,000-paragraph render completed in 0.162 seconds on the test Mac.

Backup, restore, and legacy import still materialize archives in memory. This is
documented as the principal version 1.0 large-library limitation and must be
included in the representative-large-library manual checkpoint.

## Automated verification

- Debug and Release arm64 builds passed with Xcode 26.6.
- Xcode static analysis passed.
- All 116 tests passed on macOS 26.6.1: 104 unit/integration tests and 12 UI
  smoke tests, with no failures or skips.
- The unsigned archive pipeline passed and packaged version 1.0 build 1, the
  Reference category, and the compiled icon assets without archive warnings.
- The ad-hoc Release product has Hardened Runtime, App Sandbox,
  user-selected-file, and network-client entitlements, and does not contain
  `com.apple.security.get-task-allow`.
- Xcode attached its generic `[Internal]` priority-inversion runtime warning to
  three passing UI tests. The result bundle provides no source location or
  call stack; static analysis is clean. Treat this as a manual Instruments
  profiling item rather than evidence of a located project-code defect.

## Signing status

The project and script are configured for Developer ID, Hardened Runtime, secure
timestamps, notarytool, stapling, signature and entitlement validation,
Gatekeeper assessment, and final checksum generation. The script rejects a
release carrying `com.apple.security.get-task-allow`. DIRECT_DISTRIBUTION.md
contains the credential setup and reproducible command.

A signed/notarized archive cannot be produced until a valid Developer ID
Application identity and notary Keychain profile are available on the release
Mac. Those credentials are deliberately external to source control.
