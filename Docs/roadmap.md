# Runi — App Store Roadmap

## Context

The app is currently a mix of production features, diagnostics, and shader learning experiments, all within a TabView. The vision (Docs/runi.md) calls for a focused App Store product where the **Visualiser is the root experience**, with everything else accessed from there. This roadmap breaks that transformation into phases that can be tackled one at a time across multiple sessions.

## Decisions

- **IFS branch**: Parked. It's additive and doesn't affect existing code. Will resume after restructure.
- **Demo separation**: Xcode Workspace umbrella — production app + demo app as separate projects, sharing packages.
- **Platforms**: iOS + macOS for v1. visionOS deferred.
- **Roadmap location**: `Docs/roadmap.md` in the repo (version-controlled, visible in Xcode). Claude memory pointer for auto-loading.

## Workflow Recommendations

- **`Docs/roadmap.md` is the living document.** Updated after each session with progress and decisions.
- **One sub-task per conversation.** Start in plan mode to agree on approach, then execute. Keeps context focused.
- **Branch per phase** (e.g. `phase/0-workspace`). Merge to `main` when verified.
- **Key decisions saved to Claude memory** so future sessions have context without re-reading everything.
- **Verify before advancing.** Each phase has acceptance criteria that must pass before moving on.

---

## ✅ Phase 0: Separate Demo from Production
**Goal:** Move learning/demo content out of the main app into a separate target so it can never leak into the App Store build.

### Tasks
- [x] Create a new app target (or Xcode project under a Workspace) for the Learnings/Demo app
- [x] Move all demo views: `NoiseDemoView`, `FbmDemoView`, `WarpDemoView`, `ColorsDemoView`
- [x] The demo app depends on the `Visualiser` package (same shaders, same types) — just a different UI shell
- [x] Remove the "Learnings" tab group from `ContentView.swift`
- [x] Both apps build and run independently

### Key files
- `Runimation/ContentView.swift` — Learnings tab group removed ✓
- `Packages/Visualiser/` — renamed from Animations; `AnimationState` → `VisualiserState`, `VisualisationCanvas` → `VisualiserCanvas` ✓
- `RuniDemos/` — demo views live directly in the app target (no intermediate package) ✓

### Verification
- Production app builds without any demo views ✓
- Demo app builds and can display all learning shaders ✓
- No demo code in the production target ✓

### Approach: Xcode Workspace
`Runimation.xcworkspace` containing:
- `Runimation.xcodeproj` (production app)
- `RuniDemos.xcodeproj` (demo app, uses `PBXFileSystemSynchronizedRootGroup` pointing to `RuniDemos/`)
- Both reference the shared `Packages/` folder

---

## ✅ Phase 1: App Structure — Visualiser as Root
**Goal:** Replace the TabView with the Visualiser as the app's root view. Add navigation to Library, Customisation, and Export.

### Tasks
- [x] Replace `ContentView`'s TabView with a full-screen `VisualiserView` as root
- [x] Add toolbar buttons: Run Library (top leading), Customisation Panel (bottom), Share/Export placeholder (top trailing)
- [x] `PlaybackControls` floats in bottom bar via `.safeAreaInset` with Liquid Glass — `.compact` style on iPhone, `.regular` on iPad/Mac
- [x] Rename PlaybackControls styles: `toolbar` → `regular`, `regular` → `panel`
- [x] Update `.compact` style: run name + play toggle + progress background
- [x] Library opens as sheet (iOS/macOS) — auto-opens when no run loaded; macOS sheet has minimum frame
- [x] Customisation panel toggles inspector (sidebar macOS, sheet iOS)
- [x] `PlayToggle` icon swap no longer causes layout jump (ZStack + `contentTransition`)

### Terminology
- `PlaybackControls` is the playback UI. The style determines layout. No "PlaybackControlStrip".
- `.compact` — compact size class (iPhone portrait)
- `.regular` — regular size class (iPad, Mac) bottom bar
- `.panel` — full detail controls in the playback sheet

### Key files
- `Runimation/ContentView.swift` — rewritten as root coordinator
- `Runimation/Views/Runs/VisualiserView.swift` — simplified (toolbar items moved to ContentView)
- `Packages/RunUI/.../CompactPlaybackControlsStyle.swift` — updated layout
- `Packages/RunUI/.../RegularPlaybackControlsStyle.swift` — renamed from ToolbarPlaybackControlsStyle
- `Packages/RunUI/.../PanelPlaybackControlsStyle.swift` — renamed from RegularPlaybackControlsStyle

### Verification
- App launches into full-screen visualisation
- Library auto-opens when no run loaded; selecting a run dismisses it
- Bottom bar shows playback controls + customisation button
- Customisation panel opens/closes on both platforms

---

## ✅ Phase 2: Playback UX Polish
**Goal:** Polish `PlaybackControls` layouts and add compact-to-panel navigation.

### Tasks
- [x] `.regular` style: Apple Music-like layout — transport buttons left, run info centre, hover reveals blurred info + time labels + scrub bar
- [x] `.compact` style: tapping opens Now Playing sheet with `RunInfoView` + `.panel` controls
- [x] `RunInfoView` extracted as reusable component with `RunInfoViewStyle` protocol (`RunInfoViewStyle`, `CompactRunInfoViewStyle`, `RegularRunInfoViewStyle`)
- [x] `ProgressSlider` refactored with `ProgressSliderStyle` protocol — `.system` (SwiftUI Slider) and `.minimal` (capsule bar with drag gesture) styles
- [x] Stats removed from inspector; playback controls removed from inspector sheet
- [x] `InspectorFocus` simplified to Visualisation + Pipeline only
- [x] Now Playing sheet uses dynamic height via `.onGeometryChange` + `.presentationDetents`

### Key files
- `Packages/RunUI/.../RegularPlaybackControlsStyle.swift` — Apple Music layout with hover progress
- `Packages/RunUI/.../RunInfo/` — `RunInfoView` + style protocol + two style implementations
- `Packages/RunUI/.../ProgressSlider/` — `ProgressSlider` + style protocol + system/minimal styles
- `Runimation/Views/Runs/NowPlayingSheet.swift` — iOS Now Playing sheet
- `Runimation/Views/Runs/Visualisation/Inspector/InspectorFocus.swift` — stats case removed

### Verification
- Mac: bottom bar shows transport + run info + thin progress line; hover blurs info, shows time labels and scrubbable bar ✓
- iPhone: tapping compact bar opens Now Playing sheet with run info + panel controls ✓
- Inspector shows only Visualisation + Pipeline tabs on both platforms ✓

---

## 🚧 Phase 3: Run Library
**Goal:** Unified run list with Strava + GPX support, proper empty state, and streamlined run selection.

### Tasks
- [x] Redesign `StravaRunsView` as a unified "Run Library" (`RunLibraryView` + `RunLibrary` model)
- [x] Run selection = load into player + dismiss library (primary action)
- [x] Run detail = secondary action (stats screen via three-dots menu)
- [x] Empty state: Strava connect CTA + file import button
- [x] File drag-and-drop support (macOS/iPadOS)
- [x] File picker (iOS) via `.fileImporter`
- [x] Auto-open only after bundled run fails to load
- [ ] Disconnect is not avaialble on macOS
- [ ] Move the Library into its own package or to RunKit & RunUI
- [ ] Extend the Library "Connect" feature with more integration like HealthKit

### Key files
- `Runimation/Models/RunLibrary.swift` — `@Observable` model; `refresh()`, `loadNextPage()`, `importFile(from:)`, `loadTrack(for:)`, `delete(_:)`
- `Runimation/Models/LibraryEntry.swift` — metadata + `Source` enum (strava/gpx/bundled) + cached track
- `Runimation/Models/LibraryState.swift` — `@LibraryState` property wrapper
- `Runimation/Models/Actions/` — `RefreshLibraryAction`, `LoadNextPageAction`, `ImportFileAction`, `DeleteEntryAction`, `LoadLibraryEntryAction`
- `Runimation/Models/RunLibraryEnvironment.swift` — `@Entry` keys + `.library(_:player:)` modifier
- `Runimation/Views/Library/RunLibraryView.swift` — unified library UI
- `Runimation/Views/Library/RunStatsDestination.swift` — async stats loader
- `Packages/CoreKit/Sources/CoreKit/GPX.swift` — added `parse(contentsOf:)` + made `parse(data:)` public
- `Packages/RunUI/.../RunInfo/RunInfoView.swift` — decoupled from `@PlayerState`; stored props + `init(run:)`
- `Packages/RunUI/.../RunInfo/PlayerRunInfoView.swift` — player-coupled wrapper

### Verification
- Library shows all available runs (Strava + imported files)
- Tapping a run loads it and returns to visualiser
- Files can be imported via drag-and-drop and file picker
- Three-dots menu: Stats opens metrics, Delete removes entry, Favourite/Share disabled
- iOS: stats pushes within library sheet; macOS: stats pushes over visualiser
- Empty state prompts Strava connection

---

## ✅ Phase 4: Customisation Panel
**Goal:** Consolidated panel for tuning the visualisation and data processing pipeline.

### Tasks
- [x] Customisation Panel accessible from root toolbar button
- [x] Contains:
  - Visualisation picker (NavigationLink row → pushes selection list)
  - Visualisation Adjustment Form (via `FormAdjustable`)
  - Data Processing Pipeline settings (transformers + interpolator via NavigationLink push)
- [x] Platform adaptation:
  - iOS: bottom sheet with medium/large detents
  - macOS: auxiliary floating `Window` scene (`openWindow(id:)`)
- [x] Shared `VisualisationModel` (`@Observable`) — cross-window state for macOS
- [x] `VisualisationPicker` rewritten: NavigationLink row → `VisualisationList` (name + description + checkmark)
- [x] `TransformerListButton` rewritten: NavigationLink push (was Button + sheet)
- [x] `InterpolationPicker` rewritten: NavigationLink row → `InterpolationList` (was inline Picker)
- [x] `CustomisationPanel` unified type replaces `PlayerInspectorView` + `PlayerSheetView` + `InspectorFocus`
- [x] Segmented Picker (Visualisation / Pipeline) at top of panel on both platforms
- [x] Deleted `RunStatisticsContent` and its folder

### Key files
- `Runimation/Customisation/CustomisationPanel.swift` — unified panel + `Section` enum
- `Runimation/Visualiser/VisualisationModel.swift` — shared `@Observable` model
- `Runimation/runimationApp.swift` — `Window("Customisation", id:)` scene; `RunPlayer` + `VisualisationModel` at app level
- `Packages/Visualiser/.../VisualisationPicker.swift` — NavigationLink row + `VisualisationList`
- `Packages/RunUI/.../TransformerListButton.swift` — NavigationLink push
- `Packages/RunUI/.../InterpolationPicker.swift` — NavigationLink row + `InterpolationList`

### Verification
- macOS: customisation button opens auxiliary floating window ✓
- iOS: customisation button opens bottom sheet with medium/large detents ✓
- Segmented Picker switches Visualisation ↔ Pipeline on both platforms ✓
- Visualisation row shows current name; tapping pushes list; selecting pops back and updates visualiser ✓
- Adjustment Form and description render below the picker row ✓
- Pipeline section: transformer list and interpolation picker both push via NavigationLink ✓
- Changing visualisation in auxiliary window immediately reflects in main visualiser ✓

### Known limitations
- **Single shared Customisation window**: `WindowCoordinator` tracks only the last focused run window. Multiple player windows (main + runi-viewer) share the same Customisation panel — it always customises whichever window was focused last. A per-window Customisation window would require SwiftUI to support scene-scoped floating panels or a custom NSPanel-based solution.

### Known issues (TransformerList polish — future task)
- `DisclosureGroup` collapses after scroll (state not preserved across redraws)
- When a row is expanded, inner cells (form controls) are swipeable to delete — should only be the header row
- Delete (right-click context menu) does not work on macOS
- Padding inside expanded rows is off on macOS (dashed separators, wrong indentation)

---

## ✅ Phase 5: Persistence (SwiftData)
**Goal:** Persist runs and visualisation settings. Required before App Store release.

### Tasks
- [x] Define SwiftData model `RunRecord`: run metadata + config stored as JSON `Data?` blobs
  - Config types: `VisualisationConfig`, `TransformerConfig`, `InterpolatorConfig` (Codable enums)
  - Playback duration stored as plain `TimeInterval?` column (`playDuration`)
  - `@Attribute(.unique) entryID: UUID` for O(1) ModelContext lookup
- [x] `Codable` conformance for all config types; `nonisolated` Codable implementations to satisfy Swift 6
- [x] `RunRecord+Config.swift` — load helpers decode from `Data?` via `JSONDecoder`, degrade gracefully to `nil`
- [x] `RunLibrary` backed by `ModelContext`; Strava fetch / GPX import persist to SwiftData
- [x] `NowPlayingModel` (`@Observable`) tracks current `RunRecord`; `NowPlayingModifier` bridges `RunPlayer` observation to model outside render pass
- [x] `NowPlaying` property wrapper — config bindings write back to `RunRecord` and push to player
- [x] Per-run config carried forward to new runs when no saved config exists
- [x] `NowPlayingModifier` intercepts `setDuration` to persist `playDuration` to current record

### Key files
- `Runimation/Persistence/RunRecord.swift` — `@Model` with metadata + `Data?` config blobs + `playDuration: TimeInterval?`
- `Runimation/Persistence/RunRecord+Config.swift` — load helpers for all config types
- `Packages/VisualiserUI/.../VisualisationConfig.swift`, `Packages/RunKit/.../InterpolatorConfig.swift`, `Packages/RunKit/.../TransformerConfig.swift` — Codable config enums (moved to packages in Phase 7)
- `Runimation/NowPlaying/NowPlayingModel.swift` — `@Observable` model + `NowPlayingModifier`
- `Runimation/NowPlaying/NowPlaying.swift` — `@propertyWrapper` + config bindings

### Verification
- Config changes persist across app launches ✓
- Switching runs restores per-run config ✓
- New runs inherit previous run's config when no saved config exists ✓
- Strava-fetched and GPX-imported runs persist ✓
- Schema changes degrade gracefully (unknown config → nil → default) ✓

### Notes
- Config stored as raw JSON `Data?` rather than composite SwiftData attributes — SwiftData cannot decode Swift enums with associated values as composite attributes
- `RunPlayer.Duration` struct retired in favour of plain `TimeInterval` — eliminates `DurationConfig` entirely; `TimeInterval` = `Double` is natively stored by SwiftData
- `PlaybackDurationMapping` + `DurationSlider` + `DurationPicker` implement non-linear playback duration selection with `SliderTick` marks at 15s / 30s / 1m / Real


---

## Phase 6: Export & Share
**Goal:** Two export formats — lightweight `.runi` file and full `.mp4` video — both shared via SwiftUI `ShareLink`.

### Tasks
- [x] `.runi` file format: `RuniDocument` Codable + `Transferable`, custom UTType `me.tmbr.runimation.runi`
- [x] Info.plist: register exported UTType + document type for "Open In" support
- [x] `ExportRuniAction` — synchronous model wrapper; `ExportVideoAction` — async with progress callback
- [x] Export environment: `@Entry` keys + `.export(player:)` view modifier injecting actions
- [x] `ExportSheet` — two-option sheet: instant `.runi` share + async video render with progress indicator
- [x] `ExportButton` — toolbar control replacing the share placeholder; disabled when no run loaded
- [x] `export.metal` — standard (non-`[[stitchable]]`) vertex + fragment shaders for offline Metal pipeline; forward-declares shared math from `warp.metal` / `run.metal`
- [x] `VideoRenderer` — offline Metal → `AVAssetWriter` pipeline; renders full duration at viewport resolution as fast as GPU allows (not real-time); supports both Warp and RunPath visualisations
- [x] `.runi` import: `onOpenURL` handler in `ContentView`; `RunLibrary.importRuniDocument` inserts record + caches run for instant playback
- [x] `PaletteGradientRenderer.render` + `PathSimplifier.rdp` made `public` for use in main target

### Key files
- `Packages/RuniTransfer/.../RuniDocument.swift` — Codable container + Transferable conformance
- `Packages/RuniTransfer/.../RuniUTType.swift` — UTType declaration for `.runi`
- `Packages/RuniTransfer/.../VideoRenderer.swift` — offline Metal pipeline (WarpUniforms / PathUniforms; palette texture; path MTLBuffer)
- `Packages/RuniTransfer/.../VideoExportConfig.swift` — resolution, fps, codec
- `Packages/RuniTransfer/.../ExportSheet.swift` — two-option share sheet
- `Runimation/Export/UI/Controls/ExportButton.swift` — toolbar export button (app layer; uses `@NowPlaying`)
- `Packages/RuniTransfer/.../ExportRuniAction.swift` + `ExportVideoAction.swift` — thin action wrappers
- `Packages/RuniTransfer/.../TransferEnvironment.swift` — environment keys + `.transfer(library:)` modifier
- `Packages/VisualiserUI/Sources/VisualiserUI/Resources/Shaders/export.metal` — export-specific Metal shaders

### Key decisions
- `[[stitchable]]` shaders cannot be used in a standard `MTLRenderPipelineState`; export shaders are written separately in `export.metal` and forward-declare the shared math functions compiled into the same `.metallib`
- Video renders offline (not screen capture): frames indexed by `progress = i / (totalFrames-1)`, GPU produces each frame in milliseconds; full 2-minute run renders in ~30–60 s
- Path data passed to Metal as `MTLBuffer` (not SwiftUI `.data()` arguments); `PathSimplifier.rdp` applied before buffer creation to cap point count
- `.runi` source placeholder uses `.gpx(url: URL(fileURLWithPath: "/dev/null"))` — adequate for a received file with no original source

### Verification
- [x] Create `.runi` from current record → file contains valid JSON with points + all config
- [ ] Share `.runi` via AirDrop → receiving device opens it in Runimation → plays correctly
- [x] Export video (Warp) → `.mp4` renders all frames → visual output matches live preview
- [x] Export video (RunPath) → path overlay renders correctly with MTLBuffer path data
- [x] Share video to Photos → saves correctly
- [ ] Cancel video export mid-render → cleanup, no orphaned temp files
- [ ] Video resolution matches viewport size at time of export

---

## ✅ Phase 7: App Structure Cleanup
**Goal:** Rationalise root-level state ownership, dependency injection, and navigation so the app is maintainable and extensible before the final polish pass.

### Problem Areas

- **`RunimationApp.swift`** accumulates every top-level dependency (`RunPlayer`, `RunLibrary`, `StravaClient`, `ModelContainer`). As the app grows this will become a grab-bag with unclear ownership.
- **`ContentView.swift`** mixes too many concerns: root navigation structure, toolbar construction, sheet/popover wiring, `.runi` import logic, initial-load side effects. It is not really a "view" — it is a coordinator buried inside a view.
- **Root-level navigation has no model.** `navigationPath`, `showLibrary`, `showNowPlaying`, `showCustomisation` are scattered `@State` vars with no central owner. Adding a new destination means touching multiple files.
- **Dependency injection is ad-hoc.** Some dependencies arrive via environment modifiers (`.library()`, `.player()`, `.export()`), some via `@Environment`, some wired manually. There is no consistent pattern at the root level.
- **Multi-window state sharing is implicit.** `RuniViewerScene` receives `library` and `modelContainer` as init params, but the contract between windows is undocumented and brittle.

### Candidate Directions (to be explored)

- An `AppModel` / `AppNavigator` `@Observable` class that owns `showLibrary`, `navigationPath`, deep-link routing, and `.runi` import handling — injected via `@Environment` from the app root.
- Splitting `ContentView` into a thin `RootView` (pure layout) and a coordinator/router that owns all side-effect logic.
- Centralising all environment injection into a single root modifier chain rather than scattering `.library()`, `.player()`, `.export()` calls across multiple scene bodies.
- Revisiting whether `StravaClient` should live at the `RunLibrary` level (it already does internally) and be removed from the top-level app state.

### Tasks
- [x] Extract `RunLibrary` into RunKit; introduce `ActivityTracker` + `RunStorage` protocols
- [x] Move library actions (`Refresh`, `LoadNextPage`, `LoadEntry`, `Delete`) to RunUI package
- [x] Introduce `ConnectToggle` in RunUI — per-tracker, shows name + connection status
- [x] Move `LibraryState` property wrapper to RunUI
- [x] Split `RunLibraryEnvironment` — base `.library(_:)` in RunUI, app-specific additions in app
- [x] `StravaTracker: ActivityTracker` + `SwiftDataRunStorage: RunStorage` as app-layer concrete implementations
- [x] Audit all `@State` and `@Environment` usage in `RuniApp.swift` and `RuniView.swift`
- [x] Define ownership boundaries: what belongs to the app, what belongs to a window, what belongs to a feature
- [x] Design and implement a navigation/routing model
- [x] Refactor `RuniView` into a clean root coordinator + layout view
- [x] Consolidate dependency injection at the root level
- [x] Verify multi-window (viewer window) contract is explicit and documented

### Ownership boundaries
- **App level** (`RuniApp`): `RunLibrary`, `ModelContainer`, `StravaClient`, `WindowCoordinator` — shared across all windows
- **Window level** (`RuniWindow` → `NavigationModel`): `RunPlayer`, `NowPlayingModel`, all navigation state — one instance per player window
- **Feature level**: actions injected via environment modifiers (`.library()`, `.player()`, `.export()`, `.importActions()`) — no direct model access in leaf views

### Verification
- `RuniApp.body` is concise and readable — no business logic ✓
- `RuniView` has a single clear responsibility (layout + routing) ✓
- Adding a new modal destination requires touching only `NavigationModel` ✓
- No scattered `@State` navigation flags in root views — all owned by `NavigationModel` ✓
- No direct `@Environment(RunLibrary.self)` in leaf views — `@Library` and actions only ✓

---

## Phase 8: Polish & App Store Submission
**Goal:** Final polish pass and submission.

### Tasks
- [ ] App icon (already have `Icon.icon/`)
- [ ] Launch screen
- [ ] App Store metadata: screenshots, description, keywords, category
- [ ] Accessibility audit (VoiceOver, Dynamic Type where applicable)
- [ ] Performance profiling on target devices
- [ ] Error handling: network failures, invalid GPX, Strava auth edge cases
- [ ] Edge cases: no network, empty runs, very short/long runs
- [ ] Privacy: App Tracking Transparency if needed, privacy policy
- [ ] TestFlight beta
- [ ] Logging
- [ ] App Store submission

### Verification
- Runs smoothly on oldest supported devices
- No crashes in normal usage flows
- Accessible
- App Store review guidelines met

---

## Future (Post-v1)

These are documented in `Docs/runi.md` but not in scope for the initial release:

- **Generic `RunLibraryView`** — parameterise the library view over a `LibraryRecord` protocol so it can move from the app target into RunUI. Currently blocked: `@Query` requires a concrete SwiftData `@Model` type, so the view must stay in the app until either SwiftData adds protocol-constrained `@Query` support, or we introduce an app-level adapter that bridges `RunRecord` → a protocol type for the view layer.
- **More tracker integrations** — e.g. HealthKit, Garmin, Wahoo. `ActivityTracker` protocol is already tracker-agnostic; adding a new source is a new concrete type in the app layer.
- **Run-to-Visualisation wiring UI** — let users customise which metric drives which shader parameter
- **Concatenate/Merge runs** — multi-run visualisations, playlists
- **Composable visualisations** — swap shader pipeline components (noise type, distortion, etc.)
- **ImageWarp base layer selection** — currently the domain warp shader always distorts a user-selected photo. A natural generalisation is to let users choose the *base layer*: a procedural noise field (like the existing `Warp` visualisation) or a photo. `VisualiserPhotoHolder` is already the seed of this architecture (photo lives outside the JSON config, cleanly separated from the animation parameters, and shared by `ImageWarp` and `Voronoi`). The next step would be promoting "base layer" to a first-class concept at the visualisation level rather than a hidden implementation detail inside one option.
- **Collaboration** — CloudKit sharing of runs between users
- **Favourites & Playlists** — enabled by persistence

---

## Progress Log

_Updated after each session. Format: `[date] Phase X.Y — what was done`_

[2026-03-23] Roadmap created. Decisions: IFS branch parked, workspace approach for demo separation, iOS+macOS v1.
[2026-03-24] Phase 0 complete — Runimation.xcworkspace + RuniDemos.xcodeproj created. AnimationsDemos package eliminated; demo views live directly in the RuniDemos app target. Animations package renamed to Visualiser (AnimationState → VisualiserState, VisualisationCanvas → VisualiserCanvas). Learnings tab removed from production ContentView. Swift 6 concurrency warnings fixed in all demo views (TimelineView pattern, @State extracted to locals before .visualEffect). Branch: phase/0-workspace.
[2026-03-24] Phase 1 complete — TabView removed; VisualiserView is now full-screen root. ContentView rewritten as thin coordinator (library sheet, inspector toggle, share placeholder, bundled-run loading). PlaybackControls styles renamed: toolbar→regular, regular→panel. Compact style updated: run name + play toggle + PlayerProgressBar background. Bottom bar uses .safeAreaInset with individual Liquid Glass elements (capsule for controls, circle for customise). PlayToggle icon swap stabilised with ZStack + contentTransition. macOS library sheet gets minimum frame. Branch: phase/1-visualiser-root.
[2026-03-25] Phase 2 complete
[2026-03-25] Phase 3 complete — RunLibrary @Observable model with refresh()/loadNextPage()/importFile(from:)/loadTrack(for:). @LibraryState property wrapper + 5 action types following RunPlayer pattern. RunLibraryView replaces StravaRunsView. RunInfoView decoupled from @PlayerState (stored props + init(run:)); PlayerRunInfoView wraps player-coupled usage. iOS: library sheet with stats push. macOS: library popover with stats pushed over visualiser. GPX.parse(contentsOf:) added to CoreKit. — RegularPlaybackControlsStyle rewritten: Apple Music layout, hover blurs run info and reveals elapsed/remaining time labels + scrubbable progress bar (overlay approach, width scoped to info). RunInfoView extracted with RunInfoViewStyle protocol (compact + regular styles). ProgressSlider refactored with ProgressSliderStyle protocol (system + minimal styles). Now Playing sheet added for iOS compact tap. Inspector simplified to Visualisation + Pipeline only. CLAUDE.md updated with concrete SwiftUI component architecture rules. Branch: ifs.
[2026-03-25] Phase 3 polish — Auth abstracted behind RunLibrary: isConnected, connect(from:), disconnect(). ConnectAction + DisconnectAction callable structs injected via .library modifier. ConnectButton + DisconnectButton + LibraryEmptyView added; RunLibraryView no longer imports StravaKit or AuthenticationServices. LibraryEntry.Source made Hashable/Equatable (hashes on activity.id for .strava). SourceKey enum removed; cache keyed on LibraryEntry.Source directly.
[2026-03-26] Phase 4 complete — CustomisationPanel unified type (replaces PlayerInspectorView + PlayerSheetView + InspectorFocus). macOS: Window("Customisation") auxiliary scene opened via openWindow(id:). iOS: bottom sheet with medium/large detents. VisualisationModel @Observable shared across windows. RunPlayer moved to app level. VisualisationPicker + TransformerListButton + InterpolationPicker all rewritten as NavigationLink push rows. RunStatisticsContent deleted. backgroundExtensionEffect() moved to NavigationStack level in ContentView to eliminate bottom-edge seam above PlaybackControls. Branch: ifs.
[2026-03-29] Phase 5 complete — RunRecord @Model with config stored as JSON Data? blobs (VisualisationConfig, TransformerConfig, InterpolatorConfig Codable enums; nonisolated Codable for Swift 6). playDuration: TimeInterval? column replaces DurationConfig entirely (RunPlayer.Duration struct retired). NowPlayingModel @Observable + NowPlayingModifier bridges RunPlayer observation to RunRecord outside render pass; fixes record.entryID-always-zero bug. NowPlayingModifier intercepts setDuration to persist playDuration. Per-run config carried forward on new run selection. PlaybackDurationMapping + DurationSlider (SliderTickContentForEach with labeled ticks at 15s/30s/1m/Real) + DurationPicker (compact popover trigger) replace DurationMenu/DurationPicker. Several bug fixes: player always empty (duration.didSet racing Task), SwiftData crash (composite attribute decoding), Swift 6 nonisolated Codable conformances. Branch: ifs.
[2026-04-06] Phase 7 in progress — RunLibrary extracted to RunKit with ActivityTracker + RunStorage protocols. Library actions (Refresh, LoadNextPage, LoadEntry, Delete), LibraryState, ConnectToggle, DeleteRunButton, and base LibraryEnvironment moved to RunUI. StravaTracker + SwiftDataRunStorage added as app-layer concrete implementations. ConnectToggle replaces hardcoded ConnectButton/DisconnectButton — takes a specific tracker, shows displayName + connection status, handles keepRuns confirmation. App's RunLibraryEnvironment.swift now only adds import-specific actions on top of RunUI's .library().
[2026-04-10] Phase 7 complete — NavigationModel owns all per-window state (player, nowPlaying, navigation flags); NavigationState property wrapper gives clean @-syntax access. RuniView is a thin layout coordinator. WindowCoordinator solves cross-scene Customisation window tracking. FocusedNavigationModel.swift deleted (superseded). RuniView migrated from @Environment(RunLibrary.self) to @LibraryState(\.lastPlayedItem). Ownership boundaries documented in roadmap. Branch: phase7-navigation.
[2026-03-29] Phase 6 complete — Two export formats: `.runi` (lightweight Codable+Transferable JSON; instant ShareLink) and video (.mp4 via offline Metal pipeline). export.metal adds standard vertex+fragment shaders that forward-declare shared math from warp.metal/run.metal; VideoRenderer renders full duration at viewport resolution as fast as GPU allows using AVAssetWriter. ExportSheet presents both options; ExportButton replaces share placeholder in toolbar. RunLibrary.importRuniDocument handles .runi import; ContentView.onOpenURL handles "Open In" from AirDrop/Messages. PaletteGradientRenderer.render + PathSimplifier.rdp made public. UTType registered in Info.plist. Branch: ifs.
[2026-04-12] Phase 7 extended — Visualiser package renamed to VisualiserUI (naming convention: functional UI packages use [Domain]UI suffix). PackageArchitecture.md + NavigationPattern.md written to .claude/docs. Scoped NavigationModel fully implemented: PlayerNavigation + LibraryNavigation moved to RunUI; ExportNavigation + ImportNavigation live in new RuniTransfer package. RuniTransfer feature package created (CoreUI + RunKit + RunUI + VisualiserUI deps): owns RuniDocument, RuniUTType, VideoRenderer, VideoExportConfig, all export/import actions, ExportSheet, ImportDialogueAlert, TransferEnvironment (.transfer(library:) replaces .export + .importActions). VisualisationConfig moved to VisualiserUI; TransformerConfig + InterpolatorConfig moved to RunKit. Additional library views (RunSummaryGrid, RunMetricsView, RunStatsDestination, LibraryEmptyView, RunStatsButton, LibraryToggle) moved from app layer to RunUI. @PlayerState → @Player, @LibraryState → @Library (consistent with @Navigation naming). Branch: phase7-navigation.
