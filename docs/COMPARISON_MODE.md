# Comparison mode decision

KRMA-358 selects the **always-both model** for the editor. Side-by-side is the primary comparison
presentation whenever a meaningful before/after exists, while single-photo viewing is the alternate
presentation. This keeps the comparison action and the two available surfaces consistent across
the editor.

## Interaction contract

| Surface or action | Behavior |
|---|---|
| Single-image view | Shows the edited photo. The top-bar control and `V` enter side-by-side. |
| Side-by-side view | Shows the comparison baseline on the left and the edited photo on the right. The top-bar control and `V` return to single-image view. |
| Top-bar comparison control | Is visible for every loaded photo with a meaningful comparison, and remains visible while a retained side-by-side preference is showing an identity photo. Its label names the destination: `Side by Side` or `Single View`. |
| `V` | Performs the same action as the top-bar control. It is consumed only when that action is available. |
| `Space` (hold) | In single-image view, temporarily replaces the edited surface with the comparison baseline. It is not consumed in side-by-side view because both versions are already visible. |

The comparison baseline is the non-destructive `EditDocument.comparisonBaseline`: it keeps the
develop frame and removes the visible Light, Color, Effects, Look, and local-mask stages according
to the existing document contract. Preview rendering, baseline caching, histogram admission, and
export continue to use their existing requests; presentation mode never changes the saved document
or exported result.

## Lifecycle rules

- The single/side-by-side preference is presentation state, stored in `UserDefaults`, and survives
  photo switching and relaunch.
- The transient Space state is cleared when switching photos and whenever the document returns to
  identity through reset, undo, redo, or another edit that removes the meaningful comparison.
- A retained side-by-side preference remains selected after reset and on an unedited photo. Both
  panes render the source image, and the control remains available so the user can return to single
  view; Space remains unavailable because there is no meaningful before/after.
- If the source is unloaded, comparison presentation controls disappear until a source is loaded.

Both preview surfaces are explicitly labeled for VoiceOver as Original and Edited (or the selected
Look name) photo previews. The labels describe presentation only and do not imply that the
comparison baseline is an export or a mutation to the edit document.
