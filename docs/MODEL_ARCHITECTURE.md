# Model and platform boundaries

Kromora uses a one-way dependency direction:

```text
domain/value types  <-  application stores/coordinators  <-  platform/presentation adapters
```

Domain/value types describe durable edits and library facts. They are `Codable`, `Sendable`, and
framework-light; they do not publish UI state or retain AppKit/SwiftUI objects. Application models
coordinate persistence, scheduling, and workflows. Platform/presentation adapters translate those
values to AppKit, SwiftUI, ImageIO, Photos, or window services.

## Current classification

| Boundary | Representative types | Responsibility |
| --- | --- | --- |
| Domain/value | `PhotoAsset`, `PhotoAssetID`, `EditDocument`, adjustment values, `LibrarySelectionModel`, `RenderRequest` | Durable identity, edits, selection, and render contracts |
| Application | `KromoraSettings`, `LUTLibrary`, edit stores, render coordinators | Persistence, folder/library workflows, scheduling, and orchestration |
| Platform/presentation | `ImageCollectionPresentationModel`, `PlatformThumbnailProvider`, `AppKitWindowAppearanceController`, `MaskInteractionPresentationBridge`, `PhotoAssetImageMetadataAdapter` | Observable UI state, `NSImage`, window appearance, SwiftUI colors, and ImageIO translation |

`Models/` is retained as the package's historical source grouping. The explicit type and adapter
names identify ownership even while the package is incrementally reorganized. Compatibility
typealiases (`ImageCollection`, `Thumbnails`, and `KromoraWindowAppearanceController`) preserve
existing callers and test seams during that transition.

New durable model files must not import `AppKit`, `SwiftUI`, or `Combine`. If a value needs a
platform representation, add a named adapter or presentation bridge at the platform boundary.
Core Image, Core Graphics, ImageIO, Photos, and Metal remain allowed where they are intentional
render/resource or media-decoding boundaries rather than UI publication.
