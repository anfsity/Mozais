# Scene Editor Architecture Proposal

Status: proposal for review. This covers editor ownership, theme and locale
loading, and canvas performance. It does not change runtime behavior.

## Goals

- Keep `SceneDocument` as the persisted source of truth and continue using the
  real scene runtime and widget catalog for previews.
- Keep pointer-move state transient until an edit is committed.
- Make a drag update the selected visual region without rebuilding unrelated
  editor panes or repainting unchanged scene regions.
- Preserve Flutter input, focus, keyboard navigation, and accessibility.
- Base performance decisions on measured pointer interactions.
- Let users install and switch scene themes and translation resources without
  editing Dart source.
- Keep executable widget renderers and interaction behavior in reviewed,
  compiled code.

## Current State

The workspace already scopes some updates: the node list, preview, status bar,
and inspector have separate listenables. The scene runtime also places
repaint boundaries around the background and each node.

The current theme and locale paths are still code-owned. The greeter selects
`MOZAIS_THEME` during startup from a static registry, and its theme factories
combine generated scene data with compiled renderer and motion registries. The
editor's own color palettes are constants indexed by `EditorThemeId`; the
setting switches among those built-in values. `EditorStrings` is an
abstraction, but `editorLocales` contains only English, and several greeter
tooltips are inline English strings.

Scene and theme are coupled in the runtime model too. `ThemeRegistry.resolveDocument`
uses `SceneDocument.id` to select `default`, `fallback`, or `nocturne`; each
`ThemeBundle` then owns both that document and theme tokens/registries. The
Nocturne scene is generated into Dart and imported by its theme factory; its
JSON also carries a `nocturne-depth` glass-panel variant. The greeter widget
catalog separately branches on `theme.id == 'nocturne'` to change glass-panel
rendering. A scene's identity therefore changes its appearance and renderer
behavior even when its layout data is unchanged.

`SceneNodeKind` also mixes semantic greeter components such as `accountPicker`
with a visual primitive such as `glassPanel`, while `properties` is an
untyped string map. That makes scene files depend on implementation details
and allows theme-specific variants to leak into component rendering.

The workspace composition, document/file operations, selection and preview
mode currently meet in `EditorScreen`, `SceneEditorController`, and
`ScenePreview`. `EditorScreen` owns pane state, file dialogs, close handling,
and preview mode. `SceneEditorController` owns document mutation, JSON file
operations, and asset copying. `ScenePreview` owns runtime construction,
theme caching, async background-seed lookup, preview-mode rendering, and
selection overlay composition. Separate listenables reduce some rebuilds, but
these classes still combine unrelated reasons to change.

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

## Target Ownership

```text
EditorApp
  settings, active locale, editor chrome theme
  |
  +-- LocalizationCatalog -> locale resource bundle
  +-- EditorThemeCatalog  -> editor palette data
  +-- SceneRepository     -> validated SceneDocument
  +-- ThemeRepository     -> validated ThemeDefinition
  +-- ComponentRegistry   -> compiled component implementations
  +-- MotionRegistry      -> compiled motion algorithms
  +-- EditorWorkspace
        +-- WorkspaceState: selection, predicates, panes, preview mode
        +-- DocumentSession: scene, path, load/save, dirty state
        +-- SceneProfile: selected scene id + theme id
        +-- NodeList: node identity/order projection
        +-- SceneCanvas: scene + theme + transient interaction state
        +-- Inspector: selected scene/theme projections
        +-- Status: file-operation projection

GreeterRuntime
  SceneProfile -> SceneRepository + ThemeRepository
              -> ComponentRegistry + MotionRegistry -> SceneRuntime
```

The app composition root wires concrete services. `DocumentSession` owns
persisted document edits and file operations. `WorkspaceState` owns selection,
active predicates, pane layout, and preview mode. The canvas owns pointer
sessions and temporary projections. Views subscribe to the smallest data
projection they display; no drag event updates persisted document state, dirty
state, node list, or inspector. The scene and theme are selected independently;
the profile is the explicit place that combines them.

Do not split these owners into interfaces without a second implementation or a
real replacement need. The target is explicit ownership and narrow data flow,
not a service locator or a generic editor framework.

## Package Boundaries

Keep serialized data independent from Flutter and greeter behavior:

```text
mozais_scene_schema     scene ids, component refs, layout, conditions, codec
mozais_theme_schema     theme ids, tokens, style data, codec
shared repositories     read, validate, and resolve installed scene/theme data
mozais_scene            Flutter layout, transform, visibility, motion runtime
mozais_greeter_ui       feature adapter and compiled greeter component catalog
mozais_scene_editor     document sessions, canvas tools, inspector, file UI
```

`mozais_scene_schema` already provides a Flutter-free scene model and codec.
The target adds a similarly platform-neutral theme schema. Repositories own
filesystem and package-root asset resolution; neither schema package imports
Flutter, the greeter feature, or editor widgets. The greeter app and editor use
the same repositories, while the editor remains independent of the app shell.

The runtime may build an ephemeral resolved render context from a scene, a
theme, and the compiled catalogs. That object is an adapter for rendering, not
the persisted source of either document. A serialized `ThemeDefinition`
contains data and registered ids, never Flutter `ThemeData`, renderer
instances, callbacks, or widget factories.

## Scene and Theme Boundaries

Separate scene composition, theme presentation, and executable behavior.

**Scene data** describes registered component identity, typed component data,
normalized placement, ordering, focus order, visibility conditions, and
semantic actions. It has its own id and version. A component id describes a
stable role such as a credential field or visual surface; it does not name a
theme-specific implementation. Scene data does not select colors, typography,
a theme package, or a theme-specific renderer implementation. Replace the
open-ended string `properties` map with component data validated by its
registered schema.

**Theme data** describes design tokens, semantic style definitions, surface
shapes, typography, background treatment/assets, and named motion parameters.
Scene components refer to semantic style roles; the theme resolves those roles
to visual values. Background colors, blur/scrim treatment, and surface-depth
styles live here rather than in a scene-specific theme branch. A scene can be
paired with different themes without editing the scene file. Theme data is
platform-neutral; a compiled adapter converts it to Flutter objects.

The intended pairing is explicit:

```text
scenes/greeter-default/scene.json       id: greeter-default
themes/nocturne/theme.json              id: nocturne
profiles/nocturne-login.json            scene: greeter-default
                                        theme: nocturne
```

`SceneRuntime` receives the selected scene and resolved theme separately. If
an implementation needs a combined render context, it is created at runtime
from those inputs and is never serialized as the owner of either one.

**Component and motion registries** remain compiled code. Scene data names a
supported component, and theme data supplies its presentation values and
supported visual parameters. Registries implement behavior and rendering;
they do not contain a switch on a theme name. A new executable component still
needs a reviewed implementation, but a new composition, palette, or supported
surface treatment does not.

- A versioned scene package contains a `SceneDocument` and any scene-owned
  content assets. A separate versioned theme package contains its manifest,
  `ThemeDefinition`, palette/style data, and theme-owned assets. The editor can
  open either independently; the greeter can enumerate trusted installed
  packages.
- `SceneRepository` loads scene packages. `ThemeRepository` loads theme
  packages. Each validates its own versioned data and reports errors at that
  boundary.
- The composition profile pairs scene and theme identifiers. The runtime
  resolves both, validates references between them, then constructs a
  render-only context from the two data models and the compiled registries.
- Assets resolve relative to the package that owns them. A scene may refer to
  an explicit content asset, but it cannot infer a theme from its id or reach
  into another package by path. Background appearance belongs to the theme;
  scene-specific media must be an explicit profile or scene-package reference.
- Keep a minimal embedded scene and theme available for recovery if loading
  fails.

This supports installing and switching declarative themes without rebuilding
the application, and pairing one scene with multiple themes. A theme that
introduces a new executable component or renderer still requires a compiled
registry implementation. Arbitrary Dart plugins are outside this design.

`MOZAIS_THEME` and a new scene selection can remain startup defaults during
migration, but both should resolve data through their repositories. A profile
may pair the existing login composition with the Nocturne theme; the scene id
must not be `nocturne` just to select that appearance. Nocturne's color, shape,
background, and depth treatment move to data-driven style values. The special
`theme.id == 'nocturne'` rendering branch is removed. Switching the theme
should preserve the existing greeter feature state while rebuilding the scene
presentation.

The current generated `*.scene.g.dart` documents cannot be the runtime source
of truth for dynamically installed scenes. Built-in and user-installed scene
files should use the same validated decoder. Code generation may remain as a
development-time validation aid only if it does not create a second runtime
loading path.

## Locale Resources

Replace per-language Dart string implementations with locale resource bundles.
All editor and greeter copy, including tooltips and operation errors, uses
message keys and parameterized messages. The app loads the selected locale
bundle, falls back to the default locale for missing keys, and notifies the
relevant widget subtree when the locale changes. The persisted locale setting
stores a locale tag, not an implementation enum.

Choose a resource format that supports parameters and plural rules before
implementation. Bundled locales should work offline; an optional user locale
directory can add or override text without loading executable code. Missing or
invalid bundles must fall back with a visible diagnostic rather than leave
literal keys in the UI.

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

1. Trace the current application flows and capture actual editor pointer
   gestures as a baseline before changing canvas ownership.
2. Define independent scene, theme, profile, and locale resource contracts,
   including whether user-installed packs must work without rebuilding.
3. Introduce separate validated scene/theme repositories and an explicit
   profile resolver shared by editor preview and greeter runtime.
4. Move locale-specific text to resource bundles and complete the switch across
   editor and greeter controls.
5. Separate document/file ownership, workspace state, and canvas interaction
   based on those explicit responsibilities.
6. Implement the transient canvas edit lifecycle and selected-node rendering.
7. Fix the reference-size field layout and dropdown focus styling, then verify
   them at the inspector's minimum width and with keyboard navigation.

Architecture comments should explain invariants and ownership decisions that
are not clear from types and names. They are not a substitute for keeping file
and state responsibilities narrow.

Login-manager installation and SDDM migration are separate deployment work.
They should be designed for an explicitly supported distribution and validated
with a recovery path, not bundled into the editor canvas refactor.
