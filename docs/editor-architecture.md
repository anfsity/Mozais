# Scene Editor Architecture Proposal

Status: proposal for review. This describes a direction for the editor canvas;
it does not change the greeter runtime or commit to a particular rendering API.

## Goals

- Keep `SceneDocument` as the persisted source of truth and continue using the
  real scene runtime and widget catalog for previews.
- Keep pointer-move state transient until an edit is committed.
- Make a drag update the selected visual region without rebuilding unrelated
  editor panes or repainting unchanged scene regions.
- Preserve Flutter input, focus, keyboard navigation, and accessibility.
- Base performance decisions on measured pointer interactions.

## Current State

The workspace already scopes some updates: the node list, preview, status bar,
and inspector have separate listenables. The scene runtime also places
repaint boundaries around the background and each node.

During a canvas drag, `_SelectionOverlayState` stores a temporary rect or
transform and calls `setState`. The overlay's `CustomPaint` fills the complete
preview. The scene continues to use the persisted document, so the selected
node itself does not follow the pointer. On pointer-up, the final value is
written through `SceneEditorController.updateSelected` once. The current editor
performance integration test measures document edits, selection, node edits,
and predicate changes, but does not exercise pointer dragging.

These facts do not establish whether reported frame drops come from widget
build/layout, paint/raster, or a combination. The next implementation should
start with a real gesture trace in both Outline and Real modes.

## Ownership

```text
EditorWorkspace
  pane sizes, collapse state, preview mode, routes
  |
  +-- NodeList      listens to node identity/order and selection
  +-- SceneCanvas   listens to document presentation and selection
  |     +-- Scene content: background and scene nodes
  |     +-- Live edit projection: selected node during a gesture
  |     +-- Input surface: hit testing and pointer lifecycle
  |     +-- Selection tools: outline, handles, cursor affordances
  +-- Inspector     listens to the selected document projection
  +-- Status        listens to file operations and dirty state

SceneEditorController
  persisted document, selection, predicates, file operations, dirty state
```

The workspace owns layout changes, not canvas pointer motion. The document
controller owns persisted edits and file state. The canvas owns the active
pointer session and its temporary edit projection. No drag event should update
the dirty flag, serialized document, node list, or inspector.

## Canvas Interaction

Treat a gesture as one edit transaction:

1. Pointer-down records the selected node's starting geometry, transform,
   pointer position, and hit region.
2. Pointer-move derives a temporary node projection from that starting
   snapshot. Updates are consumed at display-frame cadence; they do not create
   a new `SceneDocument`.
3. The selected node and its selection tools render from the same temporary
   projection, so the visual node follows the pointer.
4. Pointer-up emits one document edit and marks the document dirty once.
   Pointer-cancel discards the projection and leaves the document unchanged.

Move, resize, and rotation use this same lifecycle. Inspector edits remain
direct document edits because they are discrete value changes, not a pointer
stream.

## Rendering Boundaries

The canvas has four distinct responsibilities:

- **Scene content:** render through the existing theme/runtime path. Unchanged
  nodes and the background retain their current repaint boundaries.
- **Live edit projection:** update only the selected node while a gesture is
  active. It must use the same node renderer and semantic inputs as the normal
  scene; an editor-only visual clone would drift from the greeter.
- **Input surface:** cover the viewport for hit testing and pointer capture.
  Its size does not dictate the size of the painted selection tools.
- **Selection tools:** paint the transformed bounds and handles of the selected
  node. The visual paint region should be limited to the tools' bounds, while
  the input surface can remain full-size.

Build isolation and paint isolation solve different costs. Narrow listenables
prevent unrelated widget builds; repaint boundaries prevent unchanged visual
regions from being rasterized again. A full-preview selection painter can still
have a large invalidation area even when it draws only a few lines and circles.

The current scene runtime accepts a complete document. If profiling shows that
the selected node cannot be projected independently through that path, add the
smallest editor-facing per-node update seam needed to preserve the renderer.
Keep that seam specific to the measured editor use case rather than introducing
a general editor framework.

## UI Details

- Canvas reference width and height must keep their full labels and usable
  numeric entry at the inspector's minimum width. Prefer labels outside the
  fields and switch from two columns to one when space is insufficient.
- Dropdown hover, keyboard focus, and selected states must be visually
  intentional. Clearing a mouse highlight must not remove keyboard focus or
  keyboard navigation.
- Keep native Flutter controls for text input, menus, focus, and accessibility.

## Measurement and Acceptance

Before refactoring, capture actual move, resize, and rotation gestures in both
preview modes with the existing stress scene (24 nodes and a blurred image
background). Use a Linux/Wayland profile run and record matched p50/p95 build,
raster, and total frame spans for each gesture phase. Use a widget build/paint
trace to identify which regions update. The existing direct-controller cases
remain useful but do not replace gesture measurements.

The implementation is ready when:

- The selected visual follows the pointer throughout the gesture.
- Pointer-move events do not notify the persisted document, dirty state, node
  list, or inspector.
- Pointer-up commits one edit; pointer-cancel commits none.
- Unchanged scene nodes and the background remain cached during the gesture.
- Build and raster p95 meet the target refresh budget on the supported test
  display, with the same measurement gates used before and after the change.
- The measurement identifies whether the remaining limit is UI-thread work or
  raster work; do not accept a build-only metric as proof of smooth dragging.

## Work Sequence

1. Add real pointer gestures to the editor performance scenario and record a
   baseline before changing canvas ownership.
2. Introduce transient canvas edit state and the single-commit gesture
   lifecycle.
3. Render the selected node from the live projection and separate the full-size
   hit surface from bounded selection painting.
4. Narrow pane subscriptions only where the trace shows unrelated work.
5. Fix the reference-size field layout and dropdown focus styling, then verify
   them at the inspector's minimum width and with keyboard navigation.

Login-manager installation and SDDM migration are separate deployment work.
They should be designed for an explicitly supported distribution and validated
with a recovery path, not bundled into the editor canvas refactor.
