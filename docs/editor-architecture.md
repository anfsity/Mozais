# Theme Builder and Scene Editor Architecture Proposal

Status: proposal for review. This covers editor ownership, theme and locale
loading, and canvas performance. It does not change runtime behavior.

## Goals

- Keep the theme project as the authoring source of truth and use the same
  theme runtime for previews and the greeter.
- Keep pointer-move state transient until an edit is committed.
- Make a drag update the selected visual region without rebuilding unrelated
  editor panes or repainting unchanged scene regions.
- Preserve Flutter input, focus, keyboard navigation, and accessibility.
- Base performance decisions on measured pointer interactions.
- Let users author, build, preview, package, and install themes without editing
  the Mozais application source.
- Keep theme scenes, component templates, styles, motion, locale resources, and
  assets inside one independently versioned theme project.
- Keep login behavior behind a small host capability API; themes describe
  presentation and bind to those capabilities through data.

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

The product direction is Hugo-like: theme authors own independent theme
projects, while Mozais owns the format, builder, editor, validator, and runtime.
The theme is builder input, not a branch in the Mozais source tree. Unlike a
static site generator, the output still drives an interactive login greeter,
so runtime behavior is exposed through the host capability API.

```text
ThemeProject (author source)
  manifest, scenes, component templates, tokens, motion, locales, assets
  |
  v
mozais_theme_builder -> validate -> compile declarative IR -> .moztheme package
                                                   |
                                                   v
ThemeLoader -> ThemeRuntime -> generic primitive renderer
                         ^
                         |
GreeterHost -> read-only state + allowlisted actions + secure input handles

ThemeStudio
  project session, file operations, build diagnostics, live preview
  +-- WorkspaceState: selection, panes, preview mode
  +-- ProjectSession: source paths, save, dirty state
  +-- SceneCanvas: compiled theme + transient interaction state
  +-- Inspector: selected scene/component/template projections
  +-- Status: file and build diagnostics
```

The theme project is the authoring and persistence boundary. Its scenes and
component templates are package-local; there is no global scene catalog that
silently pairs a scene id with a theme implementation. The builder is the
single path from source files to a validated runtime package. ThemeStudio and
the greeter preview the same compiled representation. During canvas gestures,
the canvas owns temporary projections; pointer-move does not write source,
mark the project dirty, or notify unrelated editor panes.

Do not split these owners into interfaces without a second implementation or a
real replacement need. The host capability API is a deliberate product
boundary, not a generic plugin service locator.

## Package Boundaries

Keep the theme source format and builder independent from Flutter widgets and
greeter behavior:

```text
mozais_scene_schema       scene/layout/condition data and codec
mozais_theme_schema       manifest/component-template/theme data and codec
mozais_theme_builder      source validation, asset resolution, IR/package output
mozais_theme_runtime      package loader and generic Flutter primitive renderer
mozais_greeter_ui         host state projection and allowlisted action adapter
mozais_scene_editor       theme project sessions, canvas tools, inspector, UI
```

Both schema packages remain platform-neutral. The builder reads a theme source
tree, validates it, resolves only package-local references, and emits a
versioned `.moztheme` artifact containing the compiled declarative IR and its
resources. The loader accepts that artifact in both the greeter and the
editor. Neither schema nor builder imports Flutter, greeter state, or editor
widgets. The editor edits the project source and previews the builder output;
the greeter never imports a theme's Dart source.

The runtime resolves a package entrypoint and a `GreeterHost` capability
snapshot, then interprets the package IR. No serialized theme field contains
Flutter `ThemeData`, callbacks, widget factories, arbitrary expressions, or
references to another installed theme.

## Scene and Theme Boundaries

Each theme is a self-contained project. It owns one or more scenes, all
component templates used by those scenes, style tokens, supported motion
parameters, locale resources, and assets. A scene is selected within its theme
package; it is not a global document that acquires appearance from a theme id.
Cross-theme imports and shared visual component catalogs are not part of the
initial contract. Commonality belongs in the host's stable data format and
generic renderer primitives, not in theme-specific branches in application
code.

**Scene data** describes references to component templates defined by the same
theme, placement, ordering, focus order, visibility conditions, and bindings to
host capabilities. **Component templates** describe their visual tree using
the runtime's generic primitives, typed parameters, style roles, and event
bindings. The template model needs composition, slots, repeated data, state
conditions, and supported transitions so a theme can lay out changing account,
session, and authentication state. Their ids are local to the package. A theme
author can define and reuse components without adding a case to a Mozais
`WidgetCatalog`.

Theme-local data describes design tokens, style roles, typography, surface
shapes, background treatment/assets, motion parameters, and localized copy.
These values resolve within the package. Background effects and surface depth
are authored by the theme; the runtime has no `if (theme.id == ...)` rendering
logic.

An authoring project has a package-local entrypoint, for example:

```text
nocturne/
  mozais.yaml
  scenes/login.yaml
  components/glass-panel.yaml
  components/credential-form.yaml
  tokens.yaml
  motion.yaml
  locales/en.json
  locales/zh-CN.json
  assets/...
```

`mozais.yaml` declares package id, package version, supported Mozais host API
range, and entrypoints. The runtime selects a package and an entrypoint from
host settings. Nocturne becomes an ordinary project that can be built and
installed like any other theme; its id is metadata, never a code path.

The host exposes a narrow, versioned **capability API**. It provides semantic
state projections such as account/session summaries and authentication status,
secure input handles for credential prompts, and allowlisted actions such as
select account, submit/cancel authentication, select session, or request a
power operation. Themes can bind visual templates to these values and events;
they do not receive Rust services, D-Bus objects, arbitrary backend state, or
the ability to invoke unlisted operations. Secret input remains owned by the
host control path rather than being exposed as ordinary theme-readable text.

`mozais_theme_builder` provides `validate`, `build`, and `package` operations.
Validation checks schema and host API compatibility, local component and style
references, locale keys, asset paths, and resource limits. Build converts the
editable source into a deterministic, versioned declarative IR. Package emits
an installable `.moztheme` artifact with a manifest, IR, and package-local
resources. Builder diagnostics point to source paths and fields so the editor
can show them beside the relevant control. The embedded recovery theme is
built from the same format and loaded through the same runtime path.

This supports authoring and installing declarative themes without rebuilding
the greeter. A theme can define new compositions and components from the
generic primitive vocabulary. It cannot ship arbitrary Flutter/Dart widget
code: Flutter AOT does not load new Dart libraries into an installed host
process. If future themes need behavior outside the declarative capability
model, that is a separate extension project requiring either a host rebuild or
a deliberately designed isolated plugin process; it must not be implied by the
theme package format.

`MOZAIS_THEME` can remain a startup selection during migration, but it resolves
an installed package through the loader rather than a static Dart registry.
Switching packages preserves the greeter feature state while replacing the
theme presentation. Default, fallback, and Nocturne should all be ordinary
theme projects; only the minimal recovery artifact needs to ship with the host.

The current generated `*.scene.g.dart` files are not a suitable runtime source
for user-installed themes. `mozais_scene_codegen` generates Dart and is not the
user-facing theme builder. The theme builder replaces that runtime path:
built-in and user-authored projects pass through the same validator and produce
the same IR format. Build-time code generation may remain an implementation
detail only if it produces this same package and does not create a second
runtime path.

## Locale Resources

Theme-visible copy, including component labels and prompts, lives in that
theme's locale resources. Builder diagnostics and editor chrome have separate
locale resources owned by the tooling. All use message keys and parameterized
messages; theme text falls back to that theme's default locale for missing
keys and notifies only the affected widget subtree. User theme translations
never require editing Dart source.

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
2. Define the theme project format, generic component primitive vocabulary,
   host capability API, package compatibility rules, and builder output.
3. Build the validator/compiler/packager and load the same `.moztheme` output
   in editor preview and greeter runtime.
4. Move theme-visible strings, tokens, motion, and assets into package-local
   resources; keep editor chrome localization separate.
5. Replace the scene-only editor workspace with a theme project session while
   keeping source edits and canvas gesture state independently owned.
6. Implement the transient canvas edit lifecycle and selected-node rendering.
7. Fix the reference-size field layout and dropdown focus styling, then verify
   them at the inspector's minimum width and with keyboard navigation.

Architecture comments should explain invariants and ownership decisions that
are not clear from types and names. They are not a substitute for keeping file
and state responsibilities narrow.

Login-manager installation and SDDM migration are separate deployment work.
They should be designed for an explicitly supported distribution and validated
with a recovery path, not bundled into the editor canvas refactor.
