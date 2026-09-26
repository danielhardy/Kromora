# First-run onboarding

Kromora's first-run welcome offers three package-backed starting points: import files, import
from Photos, or copy the bundled CC0 sample photos into the open library. The sample photographs
and source/license records live in `Sources/KromoraKit/Resources/SamplePhotos`; the manifest
records the Wikimedia Commons page, creator, and CC0 1.0 license for each asset.

The short Library/Edit/Export tour and searchable shortcut reference are available from the
main-window toolbar. Guided Edit cards appear over the preview until dismissed. Each card applies
one `EditDocument` adjustment with `AppViewModel.updateDocument`, so the regular history,
persistence, and preview pipeline own the change and Undo reverses one card at a time.

Empty library and preview surfaces expose import actions, filtered Library results can clear their
filters, an unselected populated Library can open its first photo, and a completed export offers
Export another or return to Library. Light sliders show contextual help in place; other controls
continue to use their local labels, accessibility hints, and help text.
