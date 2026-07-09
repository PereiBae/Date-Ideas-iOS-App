# RendezQueue (Date Ideas App) — Working Guide

Read this fully before making any change. It is the handoff document for
continuing work on this project in any session, with any model. Deeper history
lives in `MILESTONES.md` (everything shipped so far, newest at top) and
`README.md` (product defaults + feature backlog).

## What this app is

Native SwiftUI iOS app (deployment target iOS 26, Xcode 26.6) for couples to
save date ideas: import TikTok/Instagram links (caption extraction runs
on-device with Apple Intelligence / FoundationModels), review and save places
into private shared "workbooks" synced via Firebase (Auth + Firestore), browse
them in a list, on a map, and track visits, reviews, and deals. It is live on
TestFlight for internal testing.

## Targets and file map

Two targets: app `DateIdeas` (product name RendezQueue.app) and share extension
`DateIdeasShareExtension`. The xcodebuild scheme is still `DateIdeas`.

- `DateIdeasApp/DateIdeasApp.swift` — app entry, `Theme` (accent color, AI
  gradient, serif nav titles), auth gate vs RootView switch
- `DateIdeasApp/Models/DateIdea.swift` — all model types (DateIdea, Deal,
  Visit, PlaceLocation, IdeaCategory + systemImage icons, CuisineTag, FoodTag,
  ReviewMetric)
- `DateIdeasApp/Models/ImportDraft.swift` — ImportDraft, ExtractionMethod,
  ImportStage
- `DateIdeasApp/Services/DateIdeaStore.swift` — DateIdeaStore (local +
  published filter/sort state: `IdeaFilter`, `IdeaSortOrder`), SaveConfirmation
  toast state, `UserLocationProvider`, and `CollaborationStore` (all Firebase:
  auth incl. Apple + Google, workbooks, sync, `copyIdea(_:to:)`)
- `DateIdeasApp/Services/PostExtractionService.swift` — link metadata fetch,
  Apple Intelligence caption extraction, parser fallback, stage callbacks
- `DateIdeasApp/Services/SharedImportQueue.swift` — app-group UserDefaults
  queue shared with the extension
- `DateIdeasApp/Views/RootView.swift` — tab bar, bottom accessories (save
  toast / clipboard / shared-link import), auth gate, Apple+Google sign-in
  buttons, `PlacesMapView` (map tab incl. search), account sheet
- `DateIdeasApp/Views/IdeaListView.swift` — Saved tab list, compact filter bar
  (`ActiveFilterChip`), `FilterChip`, `IdeaRowView`, `IdeaCoverImage`
- `DateIdeasApp/Views/FilterSheetView.swift` — Sort & Filter sheet
  (`IconFilterChip`, `CategoryTile`)
- `DateIdeasApp/Views/IdeaDetailView.swift` — detail page (hero, actions,
  deals, visits, sources), `EditIdeaView`, `TagPill`, `DealStatusLine`,
  `DealEditorRows`, `PlaceMapView`, `VisitRowView`
- `DateIdeasApp/Views/ImportReviewView.swift` — staged extraction sheet +
  import review, `FlowLayout`, `AIProvenanceMark`
- `DateIdeasShareExtension/ShareViewController.swift` — enqueues shared URLs

## Build and verify (run after EVERY change)

```sh
xcodebuild -project DateIdeas.xcodeproj -scheme DateIdeas -destination generic/platform=iOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Treat any build error as blocking. Stale-file warnings mentioning
`~/Documents/Date Ideas App` are harmless leftovers from an old project path.

## Design language (do not deviate)

- Accent: rosé — `Theme.accent` (#C74069). Always use `Color.accentColor` or
  `Theme.accent`; never hardcode other accent colors.
- `Theme.aiGradient` (indigo→purple) is RESERVED for Apple Intelligence
  provenance UI only (sparkles, AI badges). Never use it for anything else.
- Place names and large titles use New York serif via `Font.placeTitle(_:)`.
- Liquid Glass is for the control layer only: use `.buttonStyle(.glass)` and
  `.buttonStyle(.glassProminent)` for floating/primary buttons.
- Status colors: green = visited (checkmark icon), red = want to go (heart).
- WCAG AA contrast, Dynamic Type everywhere, VoiceOver labels on icon-only
  controls, respect Reduce Motion and Reduce Transparency.
- The app is portrait-only (Info.plist).

## Reuse these components — do not reinvent

`FilterChip` (capsule toggle chip), `FlowLayout` (wrapping chip layout),
`IconFilterChip`, `CategoryTile`, `IdeaCoverImage`, `ContributorAvatar`,
`TagPill`, `DealStatusLine`, `DealEditorRows`, `PlaceMapView`,
`SaveToastAccessory`, `GoogleSignInButton`/`GoogleLogoMark`,
`AIProvenanceMark`. Locations in the file map above.

## CRITICAL gotchas — violating these crashes the app or breaks the build

1. NEVER let the Map's frame resize or animate. This churns MapKit's Metal
   drawable and crashes with a `MTLDebugDevice` assertion (and lags in
   release). Concretely: the map header bar stays fixed-height (44pt content);
   popups (type picker, search results) float OVER the map as `.overlay`s;
   `.ignoresSafeArea(.keyboard)` must remain on the map stack so the keyboard
   never resizes it. If you see that assertion, the reported texture height
   tells you which edge resized (full-screen height = top/header, shorter =
   keyboard).
2. Never wrap interactive Buttons in `.glassEffect(...)` — hit-testing breaks
   after the first tap. Use `.buttonStyle(.glass)` / `.glassProminent`
   instead. `glassEffect` is fine on non-interactive views (e.g. a count pill).
3. New Swift files require manual `project.pbxproj` wiring (objectVersion 56,
   classic groups): 4 insertions — PBXBuildFile, PBXFileReference, the Views/
   Services group children, and the Sources build phase. Follow the existing
   synthetic-ID pattern (`A...031`/`A...131` = FilterSheetView). Prefer adding
   code to an existing file when it reasonably belongs there.
4. `DateIdeasApp/GoogleService-Info.plist` is gitignored. NEVER commit it and
   never delete the local copy (the build needs it as a resource).
5. Pasteboard: `UIPasteboard.probablyHasURLs` does not exist. Use `hasURLs` +
   `detectedPatterns(for: [\.probableWebURL])` (metadata-only, no paste
   alert). Never read pasteboard contents directly — only via `PasteButton`
   (the tap is the consent).
6. Auth/session restore happens synchronously in `CollaborationStore.init`
   and `DateIdeaStore.init`. Do not move it to `onAppear`/`start()` — that
   reintroduces a one-frame flash of the sign-in gate and sample data.
7. Buttons overlaid on a NavigationLink need an explicit 44pt frame +
   `contentShape` or taps fall through to the link.
8. Versioning: both targets' Info.plists use `$(MARKETING_VERSION)` /
   `$(CURRENT_PROJECT_VERSION)`. Before an archive, bump the build number in
   BOTH targets' build settings; app and extension values must match.
9. Location permission: `store.requestLocationForSorting()` may prompt;
   `store.refreshUserLocationIfAuthorized()` must never prompt. The app shows
   ZERO permission dialogs at first launch — the only contextual prompt is
   opening the Map tab (tester feedback 2026-07-08), picking "Near me" sort,
   or tapping the map's location button. Keep it that way.
10. Every sheet root needs `.tint(Theme.accent)` — sheets and pushed picker
    lists do not reliably inherit the root tint and fall back to system blue.
    Exception: the Map view carries `.tint(.blue)` (before its overlays) so
    MapKit's user-location dot and controls stay system blue on purpose.
11. Rows whose leading view is not plain text (Label with icon, thumbnails)
    need `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }` or the List
    separator starts at the text and looks broken.

## Workflow rules

1. One feature at a time. After it builds, STOP and let the user test on a
   real device before starting the next thing.
2. For significant UI changes, the user prefers to approve a mockup/description
   of the design before implementation.
3. Update `MILESTONES.md` (add to the post-redesign section near the top) after
   each shipped chunk.
4. The user makes their own commits unless they ask otherwise.
5. TestFlight release loop: bump Build in both targets → user archives in
   Xcode (Any iOS Device → Product → Archive → Distribute App → App Store
   Connect) → internal testers receive it automatically. The five "Upload
   Symbols Failed" dSYM warnings for FirebaseFirestoreInternal/absl/grpc/
   grpcpp/openssl_grpc are expected and harmless — Google ships those binaries
   without dSYMs.

## Known limitations / open items (backlog)

- Visit photos and locally cached cover images (`imageName`) are device-local;
  workbook partners see remote-URL images or a placeholder. Backlog item:
  real photo persistence/sync.
- Google sign-in needs Firebase console setup to actually work: enable the
  Google provider, download the fresh `GoogleService-Info.plist` (then it
  contains CLIENT_ID/REVERSED_CLIENT_ID), and add the REVERSED_CLIENT_ID as a
  URL scheme in `DateIdeasApp/Info.plist`. Until then the button shows a
  friendly "not set up yet" error by design.
- Firestore rules are prototype-permissive (any signed-in user can read/write).
  Tighten before public release — but note the join-by-invite-code flow needs
  authenticated users to query workbooks they are NOT yet members of.
- An old Firebase API key exists in early git history; it should be rotated or
  restricted in Google Cloud console if not already done.
- From `README.md` next steps: real extraction backend, place enrichment
  (opening hours/photos), automated deal expiry detection.

## If a session gets cut off (rate limits)

All state lives in this repo — nothing is lost between sessions. When service
resumes (limits typically reset within a few hours):

1. Run `git status` and `git log --oneline -5` to see uncommitted and recent
   work.
2. Read the top of `MILESTONES.md` for the most recently shipped change.
3. Run the build command above to confirm a clean baseline.
4. Continue whatever task the user names, following the Workflow rules.
