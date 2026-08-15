# iEvelyn Agent Instructions

## Scope

These instructions apply to the entire `iEvelyn` directory tree. They are intended for ChatGPT/Codex and any other coding agent working on this project.

## Instruction priority

When instructions conflict, follow this order:

1. The user's latest explicit instruction.
2. This `AGENTS.md` file.
3. `IMPLEMENTATION_PLAN.md`.
4. `PROJECT_CONTEXT.md`.
5. Existing implementation conventions and comments.

Do not infer that an old conversation overrides the checked-in documents. Ask only when a material decision cannot be resolved from the repository or a reasonable, reversible implementation choice.

## Required start-of-work procedure

Before making any project change:

1. Read this file, `PROJECT_CONTEXT.md`, and `IMPLEMENTATION_PLAN.md` in full.
2. Inspect the actual filesystem and do not assume the Xcode project already exists.
3. Inspect Git status without discarding or overwriting user changes.
4. Inspect the installed Xcode/Swift toolchain when the requested step depends on it.
5. Identify the current progress-table milestone and the exact step authorized by the user.
6. State briefly what step you are working on and any important assumption.

If the full Xcode toolchain is missing, stop implementation and provide the Step 0 prerequisite checklist. Command Line Tools alone are not enough for this app.

## Sequential milestone rule

Implement exactly one user-authorized step from `IMPLEMENTATION_PLAN.md` at a time.

- Do not begin a later step because it appears easy or related.
- Do not add future dependencies early.
- Keep temporary seams explicit when a later step will replace them.
- Finish relevant automated checks for the active step.
- Hand the user an exact manual test checklist.
- Stop and wait for the user's confirmation.
- Mark a step `Accepted` only after that confirmation.

If the user explicitly authorizes a different scope, their latest instruction controls. Explain any resulting plan update.

## Project identity and boundaries

iEvelyn is a greenfield native macOS application. It is not a migration or native clone of the Evelyn.NET web application.

Do not port or mimic:

- ASP.NET Core controllers, views, or service structure.
- The legacy web UI or browser reader.
- User accounts, authentication, password hashes, cookies, or authorization rules.
- Runtime PostgreSQL access.
- The legacy database schema as the new domain model.
- Dual canonical Markdown/HTML chapter storage.

Consult Evelyn.NET only for explicitly authorized legacy-data research and the migration work in Steps 14–15.

## Architecture guardrails

- Target macOS 26 or later unless the user approves a different deployment target.
- Use the current Swift 6 language mode and strict concurrency checks supported by the chosen Xcode release.
- Build the application lifecycle and product UI in SwiftUI.
- Use AppKit only for a specific missing SwiftUI capability; isolate the bridge and document why it exists.
- Use WebKit's modern SwiftUI integration for the reader.
- Use GRDB over SQLite with explicit migrations, foreign keys, transactions, and test databases.
- Keep Markdown as canonical chapter content.
- Derive reader HTML and EPUB XHTML through controlled renderers built on `swift-markdown`.
- Treat rendered markup, thumbnails, and EPUB files as rebuildable output, not canonical data.
- Store asset metadata in SQLite and asset bytes as UUID-addressed files under sandboxed Application Support.
- Use ZIPFoundation for EPUB packaging when Step 12 begins unless a reviewed technical issue requires a change.
- Keep legacy export in the separate `EvelynMigration` utility; never add PostgreSQL drivers to the shipping macOS app.

## Suggested source organization

Preserve clear feature and infrastructure boundaries. The initial target structure is:

```text
App/                         App entry, commands, window scenes, dependency assembly
Domain/                      Value types and domain rules without UI or SQL
Persistence/                 GRDB records, migrations, repositories, observations
Features/Library/            Sidebar, grid/list, search, library state
Features/BookDetails/        Metadata, cover, chapter organization
Features/Editor/             Markdown source editing and preview
Features/Reader/             WebKit reading UI, progress, bookmarks
Services/Assets/             Import, validation, storage, cleanup, URL resolution
Services/Rendering/          Markdown parsing, HTML/XHTML renderers, cache
Services/EPUB/               EPUB model, validation, packaging, export
Services/Import/             Backup and migration bundle validation/import
Shared/                      Small reusable UI and utilities
Resources/                   CSS, templates, assets, localized strings
iEvelynTests/                Unit and integration tests
iEvelynUITests/              High-value UI smoke tests
```

Prefer feature-local types over a large generic utilities layer. Do not introduce a new architecture framework merely to enforce this layout.

## Swift and SwiftUI standards

- Prefer small value types and explicit dependencies.
- Use protocols at boundaries that genuinely need replacement in tests, such as database, filesystem, rendering, and exporter services; avoid protocol-for-every-type ceremony.
- Use structured concurrency. Avoid detached tasks and unstructured global state unless justified.
- Keep UI-owned observable state on `@MainActor`.
- Keep database, rendering, hashing, archive, and file I/O away from the main actor.
- Make cancellation meaningful for searches, rendering, import, export, and long operations.
- Avoid force unwraps, `try!`, silent `try?`, and fatal errors for recoverable conditions.
- Surface user-actionable errors in the UI and preserve technical context in privacy-safe diagnostics.
- Use standard macOS commands, menus, focus behavior, keyboard shortcuts, and accessibility semantics.
- Do not block the main thread with synchronous database or filesystem work.
- Keep views declarative; move persistence and multi-step domain operations out of view bodies.
- Preview data must never mutate the production library.

## Persistence and data-safety rules

- Every schema change requires an ordered GRDB migration and a migration test.
- Enable and test foreign-key enforcement.
- Wrap multi-record changes in transactions.
- Views must not execute SQL directly.
- Never edit an already-shipped migration in a way that would change its meaning; add a new migration.
- Use SQLite backup/snapshot APIs or another consistency-safe method when copying a live database.
- Use temporary sibling files/directories plus atomic replacement for assets, imports, backups, and restores.
- Validate before replacing active data.
- A failed operation must not leave database references to missing assets or replace a valid library with a partial one.
- Soft-delete books before permanent removal.
- Release builds must not expose sample-data reset or destructive developer commands.
- Never run tests against the user's Application Support library.

## Content and WebKit safety

- Escape text and attributes by default in generated markup.
- Apply the documented raw-HTML policy consistently in preview, reader, and EPUB export.
- Load only known generated documents and registered book assets into the reading context.
- Do not grant arbitrary local-file access to book content.
- Route external links through a reviewed policy and open them outside the trusted book document when appropriate.
- Keep WebKit script-message interfaces minimal, typed at the boundary, and validated.
- Never interpolate untrusted source into executable JavaScript.

## Privacy and security

- The app is local-first and offline-capable.
- Do not add telemetry, analytics, cloud sync, accounts, advertising, or network services without explicit user approval.
- Request the minimum App Sandbox entitlements.
- Use user-selected file access for import/export instead of broad filesystem access.
- Do not log book/chapter content, credentials, tokens, database connection strings, or complete private paths.
- Do not copy secrets into source, fixtures, documentation, or migration reports.
- Migration access to the legacy PostgreSQL database must be read-only and configured outside source control.

## Dependency rules

- Use Swift Package Manager.
- Introduce GRDB only in Step 3, `swift-markdown` only in Step 8, and ZIPFoundation only in Step 12.
- Before adding or upgrading a dependency, consult its current primary documentation and compatibility with the installed Swift/Xcode toolchain.
- Prefer Apple frameworks and small, focused packages.
- Explain any new dependency's purpose, maintenance implications, and license.
- Do not add a dependency solely to avoid a small, well-tested piece of project-specific code.

## Testing and verification

- Use Swift Testing for unit and integration tests unless an API specifically requires XCTest.
- Use XCTest for UI automation.
- Keep database and filesystem tests isolated in temporary locations.
- Add fixtures for rendering, EPUB structure, backup/import, and migration reconciliation.
- Test success, invalid input, cancellation, rollback, and partial-failure paths.
- Run the narrowest relevant tests during iteration, then the full active-step suite before handoff.
- Do not claim a build or test passed unless it was run in the current environment.
- If verification cannot run because Xcode or another prerequisite is missing, report that plainly and do not substitute unsupported confidence.

The `iEvelyn` scheme uses Xcode 26.6 on Apple silicon. Step 3 added Swift Package Manager resolution, and Step 4 verified the current build and test commands. They keep build output and the GRDB checkout on the configured external volume:

```sh
xcodebuild -list -project iEvelyn.xcodeproj
xcodebuild -resolvePackageDependencies -project iEvelyn.xcodeproj -scheme iEvelyn -derivedDataPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3 -clonedSourcePackagesDirPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3-SourcePackages
xcodebuild -project iEvelyn.xcodeproj -scheme iEvelyn -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step4 -clonedSourcePackagesDirPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3-SourcePackages build
xcodebuild -project iEvelyn.xcodeproj -scheme iEvelyn -configuration Release -destination platform=macOS,arch=arm64 -derivedDataPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step4-Release -clonedSourcePackagesDirPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3-SourcePackages build
xcodebuild -project iEvelyn.xcodeproj -scheme iEvelyn -destination platform=macOS,arch=arm64 -derivedDataPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step4 -clonedSourcePackagesDirPath /Volumes/galfrey/Xcode/DerivedData/iEvelyn-Step3-SourcePackages -parallel-testing-enabled NO test
```

Discover schemes with `xcodebuild -list`; do not invent scheme names or destinations.

## Git and workspace safety

- Preserve all user-authored and unrelated changes.
- Inspect status before and after edits.
- Do not use destructive commands such as hard reset, forced checkout, or broad recursive deletion.
- Do not commit, amend, rebase, push, create branches/tags, publish releases, or open pull requests unless explicitly requested.
- If the folder is not a Git repository, do not initialize one unless the user authorizes that action.
- Do not modify the Evelyn.NET repository during native app work.
- Create the separate `EvelynMigration` folder only when Step 14 is authorized.

## Documentation and decision maintenance

- Keep the progress table in `IMPLEMENTATION_PLAN.md` current, but mark `Accepted` only after the user confirms manual testing.
- Update `PROJECT_CONTEXT.md` when the user approves a material product, schema, architecture, migration, privacy, or distribution decision.
- Record exact build/test commands in this file after they are verified.
- Document deviations rather than silently allowing the implementation and plan to diverge.
- Keep documentation concise enough to remain usable, but never remove constraints merely because a step is complete.

## Required handoff format after each implementation step

Lead with the outcome, then provide:

1. The completed step and its status (`Awaiting manual test`, not `Accepted`).
2. Important files added or changed.
3. Build and tests actually run, with results.
4. Known limitations or deviations.
5. A numbered manual test checklist with expected results.
6. A clear statement that no subsequent step was started.

Then stop and wait. Do not fill the pause by implementing future work.

## When blocked

- Gather enough evidence to explain the blocker precisely.
- Try safe, in-scope diagnostic actions.
- Do not bypass permissions, signing, sandboxing, or missing-toolchain requirements.
- Do not broaden the milestone to work around a product decision that belongs to the user.
- Report the exact blocker, what was verified, and the smallest user action needed to continue.
