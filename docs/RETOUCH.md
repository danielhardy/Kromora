# Retouch recipes

Retouch values are part of `EditDocument` and are persisted with each photo. A spot stores its
heal/clone mode, normalized source shape, source offset, radius, feather, opacity, and visibility.
Eye corrections store human/pet type, normalized center, pupil size, darkening, and visibility.
These values participate in rendering hashes, undo, and selective copy/paste under the Retouch
category.

`RetouchRenderer` builds Core Image graphs from those values inside the render boundary. The graph
maps source points through rotation, straighten, flips, and perspective; it then applies spots and
eye corrections before LUT, crop, vignette, and grain. Preview and export use the same render
engine path. Recipe data remains portable and contains no Core Image objects.

The Retouch inspector edits spot centers/offsets and eye parameters with normalized controls. The
Dust Finder shows a sharpened, high-contrast preview at pixel size, overlays visible spots, and
scrolls between spot centers. It does not perform automatic face/pupil detection; eye centers are
recipe values. The current heal mode uses a feathered source patch like clone, so content-aware
texture synthesis remains a refinement for a later iteration.
