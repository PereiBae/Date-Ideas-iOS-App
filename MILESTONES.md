# UI Redesign Milestones

## Share flow polish (2026-07-14) ✅
- Share extension now shows an "Imported! · Review it in RendezQueue" card
  (spring-in orange checkmark, success haptic, dim backdrop, auto-dismiss
  ~1.2s) instead of a blank sheet flashing away. Colors hardcoded in the
  extension (it doesn't bundle the app's Theme or fonts).
- Queued share links now import automatically, one after another: opening the
  app (or saving a review) auto-starts the next queued link's extraction —
  the user only reviews and saves. Cancelling a review pauses the chain
  (`DateIdeaStore.sharedAutoImportPaused`); returning to the app or tapping
  the "N links ready" pill resumes it. The review sheet's save bar shows
  "N more shared links will import after this one".

## "You" tab (2026-07-14) ✅
- Fifth tab per the mockup: Saved / Map / Deals / You / Search(role) —
  `AccountWorkbookView` promoted from a sheet to the You tab (Done toolbar and
  dismiss removed, title "You"). The profile button in Saved's top-left toolbar
  and its account sheet are gone; the workbook switcher menu remains.

## Visual identity pass — phase 3: Import / Workbooks / Visits (2026-07-14) ✅
- Workbooks: active shared card now carries the mock's INVITE CODE block
  (Space Mono letterspaced code + solid-orange Share button on a warm inset)
  and an inline MEMBERS card (avatar rows, hairline dividers, "You" chip)
  fed by `collaborationStore.activeWorkbookMembers`. The separate
  WorkbookMembersSheet was removed.
- Import progress: streamed fields became the "EXTRACTED SO FAR" card —
  Bricolage ExtraBold streamed name with a blinking orange cursor, shimmer
  bars for pending fields, centered green-lock "On-device · nothing leaves
  your iPhone" note.
- Import review: mono section headers ("Details"/"Address"/"Cuisine"/"Food
  items"/"Deal"/"Source"/"Save into"), selected tag chips gained the soft
  orange border, save CTA is the mock's 54pt orange-gradient button with glow.
- Visit detail: photo grid became the mock's mosaic (large tile + two stacked,
  "+N" overflow, tap to zoom); rating became the dark OVERALL stat card
  (orange star, Bricolage 800) beside a white SPENT card, with factor BARS
  (`FactorBarRow` replaced star-row `RatingDisplayRow`); notes under a mono
  header.

## Visual identity pass — phase 2 rollout (2026-07-14) ✅
Saved-screen sign-off approved (with stronger card shadows: cardShadow 0.18,
radius 16, y 8). Rolled the treatment app-wide:
- Hanken Grotesk applied to ~100 explicit text styles across every view via
  `Font.ui`; deal/status colors moved to `Theme.endingSoon`/`Theme.visited`
  (want-to-go stays red per user choice — the palette's warm red).
- Workbook cards: white floating cards with warm shadow + hairline; invite
  code in Space Mono; workbooks screen on the paper gradient.
- Sign-in rebuilt as the mockup's dark warm hero: burnt-orange gradient
  (#C25A2A→#7A3418), white RendezQueue wordmark in Bricolage ExtraBold,
  "Your next date, already saved." tagline, translucent white input fields,
  solid white 54pt CTA, palette-recolored brand cards, forced dark scheme.
- Map preview card gained the floating shadow.
Deferred by design: mockup's custom floating tab bar (native Liquid Glass bar
kept — required for tabViewBottomAccessory toasts) and the fifth "You" tab.

## Visual identity pass — phase 1 (2026-07-14) ✅ (approved)
Per Downloads/CLAUDE_CODE_PROMPT.md: Theme layer + Home · Saved restyled first
for approval before rolling out to remaining screens.
- Real brand fonts bundled as static TTFs (Google Fonts css2 API →
  DateIdeasApp/Fonts, folder reference A...035/134, UIAppFonts): Bricolage
  Grotesque 600/700/800, Hanken Grotesk 400–700, Space Mono 400/700. Font
  helpers: `placeTitle`/`displayHeavy` (Bricolage), `ui(_:weight:)` (Hanken,
  also app-wide default), `mono` (Space Mono). Nav bar titles use Bricolage
  via UIAppearance.
- Theme additions: `paperGradient` page background (themedScreenBackground now
  uses it), warm text ramp, `cardShadow`, status colors `visited`/`endingSoon`.
- Home · Saved restyled: plain list with floating white card rows (radius 16,
  warm shadow), Hanken/Bricolage type in rows and chips, orange star + dark
  score, import moved from toolbar to a gradient FAB (bottom-trailing).
Remaining screens restyle after user sign-off.

## Visual redesign v2 — warm/orange (2026-07-09) ✅
Ported the approved Claude Design mockup (Downloads/RendezQueue.html):
- New token layer in `Theme` (all light/dark dynamic): cream `background`,
  white `cardBackground`, `hairline`, orange `accent` #F26B1D + CTA
  `accentGradient`, tag tint pairs, pink `avatarGradient`. Asset-catalog
  AccentColor updated to match.
- Typography: serif dropped — place titles/large titles are bold system sans;
  `SectionLabel` adds uppercase mono section headers (filter sheet, visits).
- Tag chips became tinted rounded rects (`TagPill` prominent/neutral,
  `EditableTagChips`, list-row tags incl. category); stars orange; avatars
  pink gradient with white initials.
- Cream page backgrounds app-wide via `.themedScreenBackground()`; detail page
  action row rebuilt as icon-over-label cards with gradient "Log visit".
- Mockup fonts (Bricolage Grotesque/Hanken Grotesque/Space Mono) approximated
  with system fonts for now.

## Quality of life fixes (2026-07-09) ✅
- Blue-flash root cause: custom fills used `Color.accentColor`, which resolves
  from the environment at render time and comes up system blue on the first
  frame of List rows (e.g. the Filters pill at launch). Every custom accent
  fill/foreground now uses the literal `Theme.accent`; `Color.accentColor` is
  banned for painting (CLAUDE.md design rule updated).
- Tint stability: `.tint(Theme.accent)` re-asserted at the end of the map
  screen's modifier chain — the mid-chain `.tint(.blue)` (for MapKit elements)
  could leak into overlays/pushed screens depending on environment resolution,
  causing the blue/rosé flip-flopping.
- Editing a place's address now clears the stale pin and re-resolves
  coordinates via `AppleMapsPlaceResolver` (made internal); the detail-page
  map is identity-keyed on the coordinates so it recreates when the pin moves
  (`Map(initialPosition:)` only applies once).
- Import can save to any workbook: "Save to" navigation-link picker on the
  review sheet (shown when >1 workbook, defaults to active); non-active
  targets go through `CollaborationStore.copyIdea` +
  `completeDraftSavedElsewhere`, and the save toast names the actual
  destination (`SaveConfirmation.workbookName`).

## Workbook members + visit detail (2026-07-08) ✅
- Workbook members: the active shared workbook card's member row opens
  `WorkbookMembersSheet` — avatars, display name (email fallback), email
  subtitle, and a rosé "You" badge. Profiles load per-member from the `users`
  collection via `CollaborationStore.fetchMembers(of:)` (+ `getDocument`
  continuation helper); current user sorts first. Personal workbooks show no
  members UI.
- Visit detail: tapping a visit now opens read-only `VisitDetailView`
  (AddVisitView.swift) — title/date, "Visited by" line, overall score,
  per-metric star rows (`RatingDisplayRow`), spent, notes, photo grid with
  tap-to-enlarge `fullScreenCover` (`VisitPhotoFullScreenView`); partner-device
  photos noted gracefully. Toolbar Edit opens the existing AddVisitView edit
  flow; the underlying data refreshes live after saving. Visit rows on the
  place page gained a chevron affordance. Contributor stamping centralized as
  `CollaborationStore.stampedVisit(_:)`.

## Flexible tag system (2026-07-08) ✅
- Cuisine/food tags are now free-form strings (`DateIdea.cuisineTagNames` /
  `foodTagNames`); establishment type stays the controlled IdeaCategory enum.
- `PlaceTagNormalizer` (DateIdea.swift): trims, strips #/@, rejects junk words
  and >28-char tags, applies aliases (ramyeon/korean ramen → Ramyun),
  title-cases lowercase tags, dedupes case-insensitively.
- Backward compatible Codable: decode merges legacy enum keys (their raw values
  are display strings) into the new arrays; encode writes the new keys plus
  enum-compatible values under the old keys so pre-update builds still decode.
  CuisineTag/FoodTag enums remain only as this bridge + parser keyword output.
- Apple Intelligence guides are open-ended (concise title-case tags, no
  hashtags/handles/malls/addresses/generic words), so e.g. "Ramyun" and
  "Cocktails" can be suggested; fallback parser maps its keyword hits to
  strings through the normalizer.
- New `EditableTagChips` (ImportReviewView.swift): removable chips + add field,
  used in both Review Import and Edit Place (replaces allCases chip grids).
- `IdeaFilter.cuisineTag/foodTag` are strings matched case-insensitively;
  filter sheet lists tags derived from the workbook's saved places.

## Tester feedback round 5 (2026-07-08) ✅
- `ContributorAvatar` gained a real `size` parameter — outer `.frame` overrides
  made the image overflow its slot ("Added by" and visit rows looked
  misaligned). Detail 18pt, list rows 26pt, visit rows 16pt.
- Streaming extraction: `FoundationModelCaptionExtractor` now uses
  `session.streamResponse` and reports name/address/summary partials through
  `onPartial` → `store.streamingPreview` → the import progress sheet fills in
  fields live as tokens arrive (skeleton shimmer only for missing fields).
- Model prewarming: `CaptionExtractorPrewarmer.prewarm()` creates and prewarms
  a session when an import is likely (shared-queue items, clipboard link
  detected, Import Link sheet opened); extract() consumes the prewarmed session.
- Place details: "Opening hours & info" row in the detail Location section runs
  an MKLocalSearch for the place and presents `mapItemDetailSheet` (Apple's
  place card: hours, photos, phone).
- Account sheet no longer surfaces Firebase internals ("Firebase ready" etc.);
  only a generic "sign-in unavailable" note when Firebase is missing.
- Join discoverability: "Join with invite code" now lives in the workbook
  switcher menu on Saved (opens JoinWorkbookSheet directly).

## Tester feedback round 4 (2026-07-08) ✅
- Full-width separators on the icon Type picker rows in import review + edit
  (`alignmentGuide(.listRowSeparatorLeading)`, same fix as the saved list).
- Rosé everywhere: `.tint(Theme.accent)` stamped on every sheet root (import
  session, edit place, add visit, filter sheet, detail sheet, account,
  workbooks, create/join, import link) — sheets and pushed picker lists don't
  reliably inherit the root tint and were falling back to system blue.
- Map: `.tint(.blue)` scoped to the Map view only, so the user-location dot and
  MapKit's own controls are system blue while the app overlays stay rosé.

## Tester feedback round 3 (2026-07-08) ✅
- Type pickers unified: import review's picker was still plain text while edit
  had icons. Both now use `Label` rows with `IdeaCategory.systemImage` and
  `.pickerStyle(.navigationLink)` — a pushed Settings-style list where every
  row shows its icon and the selection tick sits on the trailing (right) edge.
  (A menu-style picker's leading checkmark is system-drawn and cannot be moved.)

## Tester feedback round 2 (2026-07-08) ✅
- Deal editor: title field is now bold (`.headline`), toggle rows spaced out
  (VStack spacing 14 + vertical padding) so the switches no longer touch.
- Saved list rows: separators run full width
  (`alignmentGuide(.listRowSeparatorLeading)`), and the star score + visited
  tick moved into one trailing column so they align consistently.
- Visits now record who logged them (`Visit.addedBy*` optionals, stamped in
  IdeaDetailView from the signed-in user); shared-workbook visit rows show a
  "Visited by <name>" avatar line. Personal workbooks hide it.

## Tester feedback round 1 (2026-07-08) ✅
- Visits can now have an optional title ("Anniversary dinner"); shown as the
  row headline with the date beneath. `Visit.title` is optional so old data
  still decodes.
- Visit photos are now actually saved: AddVisitView previously generated random
  UUID names without writing image data. Save now loads each picked photo and
  writes it via `DateIdeaImageStore`; thumbnails (`VisitPhotoStrip`) appear in
  the add/edit sheet (removable) and on visit rows. On a partner's device the
  files don't exist, so rows fall back to "N photos on your partner's device".
- Keyboard dismissal: new `View.keyboardDismissal()` (DateIdeasApp.swift) adds
  interactive scroll-to-dismiss + a keyboard Done button; applied to the import
  review, edit place, and add visit forms. The bottom save bars on import
  review / edit place hide while the keyboard is visible
  (`observesKeyboardVisibility`) instead of floating up into the Done button.
- Map: `UserAnnotation()` added so the blue current-location dot renders, and
  opening the Map tab now requests location permission contextually (first
  launch still shows zero dialogs — Saved is the initial tab).

Design direction: iOS 26 native, Liquid Glass for the control layer only, indigo accent,
purple reserved for Apple Intelligence provenance, New York serif for place names and
large titles, WCAG AA contrast throughout, Dynamic Type everywhere.

## M1 — Foundation & tab navigation ✅
- `Theme` (indigo accent, AI gradient, serif large-title appearance) in `DateIdeasApp.swift`.
- `Font.placeTitle(_:)` serif style applied to place names.
- `RootView` restructured into tabs: Saved / Map / Deals (badged) / Search (search role).
- Map and Deals promoted from sheets to tabs; Search screen added.
- `FilterChip` restyled (AA contrast, selection haptic, VoiceOver selected trait).

## M2 — Workbooks ✅
- `WorkbooksView.swift` (new file, wired into pbxproj): card per workbook with member
  avatars, idea count on active card, 2px accent border + Active check, invite code
  ShareLink on active shareable card, glass create/join buttons.
- `ToolbarTitleMenu` on Saved: title shows active workbook name, quick switch,
  "Manage workbooks" opens the page as a sheet.
- Account sheet: workbook form sections replaced with a NavigationLink to WorkbooksView;
  create/join are now focused sheets with inline errors.

## M3 — Sign-in redesign ✅
- `AuthenticationGateView` rebuilt: brand card trio + serif wordmark + tagline,
  Sign in with Apple primary, email path with explicit sign-in/create modes toggled
  by a link (animated name field), glass prominent submit with syncing spinner.
- Firebase status demoted to a failure-only banner; errors inline under submit;
  privacy footnote; keyboard dismisses interactively.

## M4 — Import capture ✅
- Clipboard detection on scene activation via `hasURLs` + `detectPatterns(.probableWebURL)`
  (metadata-only, no paste banner); changeCount tracking prevents re-offering
  handled/dismissed links.
- `tabViewBottomAccessory`: "Link copied" pill with `PasteButton` (String payload —
  tap is consent, no permission alert) and a dismiss X.
- Share-extension queue surfaces as "N shared links ready · Import" in the same
  accessory instead of importing silently; queue gained `pendingCount`/`dequeueFirst`
  (old `dequeueAll` dropped all but the first shared link).

## M5 — Extraction & review ✅
- Staged extraction sheet (`ImportSessionSheet` + `ExtractionProgressView`): presents
  as soon as an import starts, checklist of stages (fetch caption → extract → match on
  Maps) with `.redacted` shimmer field skeletons, AI-gradient sparkles + on-device
  privacy note when Apple Intelligence runs, parser-fallback note otherwise;
  transitions into the review form when the draft is ready.
- Extraction pipeline reports stages via `ImportStage` + `onStage` callback on
  `PostExtractionServicing`; store publishes `importStage` with a generation counter
  so cancelling the sheet mid-extraction drops the stale result.
- `ImportReviewView` rebuilt: hero image with confidence + extraction-method badges,
  per-field sparkle provenance (`AIProvenanceMark`, clears on edit via `onChange`),
  cuisine/food tag chips (`FilterChip` in a new `FlowLayout`) replace the 43 toggle
  rows, prominent glass "Save to <workbook>" action pinned to the bottom.

## Post-redesign: Filter revamp ✅
- The 3–4 stacked horizontal chip rows on Saved are replaced by a single compact bar:
  an accent "Filters" pill with an active-count badge plus removable chips for each
  active filter and non-default sort; empty filtered results get a
  ContentUnavailableView with "Clear filters".
- `FilterSheetView` (new file, wired into pbxproj as A...031/A...131): Sort by chips
  (Date added / A to Z / Near me with location icon), "Type of place" icon grid
  (`IdeaCategory.systemImage`), cuisine/food chips limited to tags present in saved
  ideas, Visited card with rating metric + minimum stepper, Clear + "Show N places"
  glass action bar. Sheet edits a draft `IdeaFilter`; Apply commits to the store.
- Store: filter state consolidated into `IdeaFilter` (Equatable, `matches(_:)`,
  `activeCount`) + `IdeaSortOrder`; Near me uses `UserLocationProvider`
  (CLLocationManager, when-in-use; plist string already existed for the map) with
  ideas lacking coordinates sorted last and a denied-permission footnote in the sheet.

## Post-redesign: Map revamp ✅
- Full-bleed map: nav bar hidden, the opaque material filter strip removed.
- Floating Liquid Glass controls (`glassEffect`): segmented All / Want to go / Visited
  capsule top-left; round type-filter button top-right that fans out per-category icon
  rows (only types with mappable places), dimming the map behind; active-type dot badge.
- Tapping a pin now shows a `MapPreviewCard` (photo, serif name, category · address ·
  distance via `refreshUserLocationIfAuthorized` — never prompts, only uses an existing
  grant), status + active-deal line, tap to push detail, X or re-tap pin to dismiss.
- Count pill ("N places shown") bottom-left when filters are active; selection is
  dropped automatically if a filter change hides the selected pin.
- Pins: green = visited, red = not visited (user choice); selected pin grows.
- Device-test fixes: segmented control + fan button rebuilt on `.glass` /
  `.glassProminent` button styles (custom buttons inside `glassEffect` broke
  hit-testing); preview-card dismiss got a 44pt hit target; app locked to portrait
  in Info.plist.
- Second pass (user choice "B + Rosé"): app accent changed indigo → rosé #C74069
  (`Theme.accent`; AA-safe with white, AI gradient stays indigo/purple); map controls
  moved into a frosted `safeAreaInset` header (`.ultraThinMaterial` + hairline);
  default `.mapControls` restored since the built-in compass/location no longer
  collide with anything. The type rows float over the map as a dimmed overlay popup —
  expanding the header resized the Map every animation frame, churning MapKit's Metal
  drawable (MTLDebugDevice crash + lag), so the header stays fixed-height.

## Post-redesign: Detail page revamp + map search + copy to workbook ✅
- `IdeaDetailView` rebuilt to match the design language: hero image (tappable when
  source posts exist — opens the original TikTok/Instagram post, with a "View post"
  affordance) with visited/want-to-go + category badges; serif title block with
  address and "Added by" contributor row; action row (rosé glass "Log visit",
  Directions via MKMapItem.openInMaps, website); rosé-tinted `TagPill` chips in a
  `FlowLayout` (TagWrap deleted); active deals surfaced above the map; visits with
  an Add header action; source pills; deal history in a `DisclosureGroup`;
  Edit / Copy to workbook / Delete consolidated into a toolbar ⋯ menu.
- Copy to workbook: `CollaborationStore.copyIdea(_:to:)` writes an independent copy
  (fresh UUID) into the chosen workbook's ideas collection; confirmation capsule +
  success haptic in the detail view.
- Map search: magnifier button in the frosted header swaps the row to a search field
  (header height fixed at 44 so the map never resizes); results float over the map,
  searching all mappable places regardless of active filters; picking a result clears
  conflicting filters, centers the camera, and opens the preview card.
  `.ignoresSafeArea(.keyboard)` on the map stack — the search keyboard resizing the
  map caused the same Metal-drawable crash as the old expanding header.
- `EditIdeaView` restyled to mirror the import review: hero image + URL row, serif
  name field, type picker with category icons, cuisine/food `FilterChip` chips in a
  `FlowLayout` (toggle rows removed), place-name field dropped (falls back to title
  on save as before), prominent glass "Save changes" bar.

## M6 — Polish ✅
- Save toast: after an import saves, the tab accessory shows "Saved to <workbook>"
  (`SaveToastAccessory`) with a View action that opens the idea detail in a sheet,
  a dismiss X, auto-dismiss after 6s, success haptic (`sensoryFeedback(.success)`),
  and a VoiceOver announcement. `saveIdea` now returns the saved (possibly merged)
  idea so the toast targets the right record; `SaveConfirmation` published on the store.
- Accessibility: reduce-transparency swaps glassy review badges for solid backgrounds;
  reduce-motion stills the extraction skeleton shimmer; workbook member avatar stacks
  read as one combined VoiceOver element ("Members: you and N others"); list-row
  contributor avatars announce "Added by <name>"; avatar initials scale down at AX
  Dynamic Type sizes instead of clipping. AI-filled field sparkles were already
  labelled in M5.
