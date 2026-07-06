# Date Ideas

A native SwiftUI iOS app for saving TikTok and Instagram date ideas into a private shared couple space.

## Current Scaffold

- SwiftUI iOS app target.
- iOS Share Extension target for capturing TikTok, Instagram, or plain URL shares.
- Import review screen before saving extracted data.
- Editable date idea fields: name, category, tags, location, opening hours, summary, and deals.
- List view with category, tag, and visited filters.
- Detail view with location map, current deals, deal history, source links, and visit history.
- Visit tracking with notes, amount spent, photo selection count, and star ratings.
- Overall score calculated from food, ambience, value, service, and revisit potential.
- Duplicate-aware saving that merges new deals/source posts into an existing place.

## Product Defaults

- Sync direction: private couple space using Apple-native sharing/CloudKit as the preferred long-term direction.
- Maps direction: MapKit first for native maps and directions. Google Places can be added behind the service layer later if richer place photos, ratings, and opening hours are worth the API key and billing.
- Deal expiry: expired deals are hidden from the current deal section but kept in history.
- Import strategy: captions, titles, URLs, and visible metadata first; screenshots/manual text as fallback; video/audio analysis as a later integration.

## Build

```sh
xcodebuild -project DateIdeas.xcodeproj -scheme DateIdeas -destination generic/platform=iOS -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Next Implementation Steps

1. Replace `MockPostExtractionService` with a real extraction backend that can process captions, pasted text, screenshots, and video/audio when available.
2. Add CloudKit sharing or a small backend for invite-code based couple spaces.
3. Add real photo persistence for visits instead of storing selected photo placeholders.
4. Add a place enrichment service for opening hours, photos, directions, and duplicate resolution.
5. Add automated expiry detection for deals when end dates are extracted.

