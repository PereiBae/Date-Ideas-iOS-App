# UI Redesign Milestones

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
