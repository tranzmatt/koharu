# Koharu V2 Scene Graph Proposal

This document proposes a breaking redesign of Koharu's editing model so the application can evolve more like Figma and Photoshop instead of continuing to grow around the current `Document + TextBlock + mutable layer blobs` structure.

The goal is not to copy either product feature-for-feature. The goal is to adopt the parts that fit Koharu best for long-term development:

- a project as the saved unit
- a real node tree as the authored source of truth
- revision-based history
- non-destructive derived outputs
- stable IDs and shared transport contracts

This proposal intentionally drops backward compatibility with old document types and old storage.

## What Koharu V2 should optimize for

Koharu is not a general design tool. It is a manga translation editor with a pipeline.

That means the best V2 design is one that makes these cases reliable:

- multiple saved projects
- multiple pages per project
- rich text editing on top of imported images
- grouping, reordering, visibility, lock, opacity, and blend-mode editing
- heterogeneous multi-selection
- non-destructive manual cleanup and masking
- repeatable pipeline reruns without clobbering authored edits
- portable project files
- shared HTTP and MCP contracts

The design should not optimize for features Koharu does not need yet:

- vector drawing
- component systems
- auto layout
- collaborative multiplayer
- branching history UI

## Core decision summary

These are the recommended V2 decisions.

### Canonical model

Use:

```text
Project
  -> Page
    -> Authored node tree
      -> Revisions
```

### Canonical history

Use revision-based linear history.

- every user gesture creates one transaction
- transactions store typed operations and inverse operations
- undo and redo append new revisions
- system publications do not consume user undo slots

### Canonical transform

Use `AffineTransform2D` as the canonical stored transform.

- inspector fields such as `x`, `y`, `width`, `height`, and `rotation` are derived helpers
- operations may patch derived transform helpers, but they compile into affine updates

This is a better long-term fit than using decomposed fields as the source of truth.

### Canonical layering

The authored node tree defines authored compositing order.

- layer tree order must match canvas order
- reorder operations must affect real render order
- PSD export must project from the same authored tree

Generated outputs are saved with the project, but they are not regular authored layers in the canonical z-order.

### Storage

Use:

- `.khrproj/` as the working project format
- `.khr` as the packed interchange and sharing format

The working format should be a portable bundle, not a single mutable file.

### Shared API

HTTP and MCP should call the same application services and use the same DTOs.

## Canonical domain model

### Project

A project owns:

- `project_id`
- `name`
- `schema_version`
- `created_at`
- `updated_at`
- `page_order`
- `current_page_id`
- `head_revision`
- revision metadata such as `can_undo` and `can_redo`

### Page

A page owns:

- `page_id`
- `name`
- `width`
- `height`
- `root_node_id`
- authored nodes
- annotations
- publication records

### Authored node kinds

V2 should keep the authored node set intentionally small:

- `PageRoot`
- `Group`
- `Raster`
- `Text`

This is enough for Koharu's real editing needs and keeps the model aligned with industry-standard layer trees without building a speculative framework.

#### Why not `Frame` in V2

Frames are useful, but they are not necessary for Koharu's first serious editor cut.

For V2:

- groups with optional clipping cover current needs
- adding `Frame` later is straightforward if artboard-like workflows become real user demand

#### Why not `Generated` as a normal node kind

Generated outputs are real project data, but they are not authored layers.

If generated outputs live in the authored z-order, the model becomes harder to reason about:

- tree order no longer clearly means authored compositing order
- reruns mutate visible layer structure
- users can mistake cached pipeline outputs for authored content

Koharu should instead persist generated outputs as publications and expose them in a read-only outputs surface in the UI.

## Node structure

Every authored node shares:

- `id`
- `parent_id`
- `order_key`
- `name`
- `visible`
- `locked`
- `opacity`
- `blend_mode`
- `transform`
- `kind`
- `role`
- `source_revision`

### `PageRoot`

`PageRoot` is:

- non-deletable
- non-reparentable
- non-transformable
- the top-level ordering container for a page

### `Group`

`Group` is:

- an organizational container
- bounds derived from children
- optionally clipping via `clip_children: bool`

For V2, groups should use isolated compositing.

That means:

- group opacity applies to the flattened group
- group blend mode applies to the flattened group
- no pass-through blending in V2

This is simpler, predictable, and sufficient for Koharu.

### `Raster`

`Raster` is used for:

- imported source images
- manual cleanup rasters
- future paint-like authored content

### `Text`

`Text` is the main editable translation layer.

It stores:

- `layout_mode`: `point` or `area`
- `transform`
- `size`
- `runs: Vec<StyledRun>`
- `source_text`
- `machine_translation_text`
- `edit_mode`: `machine_mirror` or `manual`
- `annotation_id`

`StyledRun` stores:

- `text`
- `style`

`TextStyle` stores:

- font families
- font size
- color
- alignment
- italic and bold state
- stroke
- optional shadow

### Rich text scope

Storage should support styled runs from day one.

The V2 UI should still be intentionally narrow:

- one text run per node in normal editing
- no per-run editing UI yet

This gives Koharu a future-proof storage and history shape without forcing a complex text editor into the first V2 implementation.

## Masks

Masks should be attached properties, not independent tree nodes.

Each maskable node may carry:

- `user_mask`
- `system_mask`

Rules:

- `user_mask` is authored and undoable
- `system_mask` is pipeline-owned and non-undoable
- if both exist, effective masking is their intersection

This is the best fit for Koharu.

It keeps manual and pipeline masking separate without inventing a general-purpose mask stack that the UI cannot expose clearly in V2.

## Annotations and pipeline metadata

Authored content and pipeline analysis must stay separate.

`AnnotationSet` should hold:

- OCR regions
- bubble regions
- reading order
- font predictions
- layout hints

Text nodes reference annotations by stable ID, but annotations do not own the text node.

This separation is required for correct reruns:

- OCR can improve
- font prediction can improve
- layout hints can change
- manual text edits and manual layout must still survive

## Publications and generated outputs

Generated outputs should be persisted as `PublicationRecord`s, not authored nodes.

Each publication record should include:

- `page_id`
- `source_revision`
- `pipeline_signature`
- `inpainted_asset_id`
- `rendered_asset_id`
- text sprite asset refs keyed by text node id
- publication timestamp

These outputs are:

- portable project data
- replaceable by reruns
- visible in the UI
- excluded from the user undo chain

### UI treatment of generated outputs

Generated outputs should appear in a dedicated read-only outputs surface, not in the authored layer tree.

That UI can show:

- latest inpainted output
- latest rendered output
- per-text rendered sprites
- the source revision and pipeline signature they came from

This gives users visibility without corrupting the authored layer model.

## Selection and editing model

Koharu V2 should follow the interaction model users already expect from Figma and Photoshop:

- selection is an ordered same-page set of `node_id`s
- the last selected node is the primary selection
- click selects
- shift-click adds
- cmd/ctrl-click toggles
- marquee selects by bounds

The inspector should show:

- directly editable common properties
- mixed values when selected nodes disagree

V2 multi-selection must support:

- move
- rotate
- scale
- group
- ungroup
- reorder
- reparent
- visibility toggle
- lock toggle
- opacity updates
- blend mode updates
- shared text style updates for selected text nodes

## User-facing changes

This section defines the expected user-visible behavior of V2.

### Projects

Users work with saved projects instead of one implicit document set.

Visible changes:

- Koharu opens and saves named projects
- a project can contain multiple pages
- users can switch between saved projects
- importing images adds pages to the current project instead of replacing an unnamed global document set
- `.khrproj` is the working format
- `.khr` is the portable export and import format

Expected UI surfaces:

- project picker or project list
- current project title in the main chrome
- page list inside the active project
- explicit import and export project actions

### Pages

Each imported image becomes a page inside the current project.

Visible changes:

- users navigate pages inside a project, not separate standalone documents
- page switching preserves selection and view state per page where practical
- page thumbnails are shown in the page navigator

### Layer tree

The editor gets a real authored layer tree.

Visible changes:

- users see groups, rasters, and text layers in a hierarchical panel
- drag reorder changes actual authored paint order
- visibility, lock, opacity, and blend mode edits happen in the layer UI
- grouping and ungrouping act on the current selection

V2 should not show generated outputs as normal authored layers.

Instead:

- the layer tree shows only authored content
- generated outputs live in a separate outputs panel or outputs drawer

### Selection

Selection should behave like a modern layered editor.

Visible changes:

- click selects one node
- shift-click adds to the selection
- cmd/ctrl-click toggles selection membership
- marquee selects multiple nodes
- the last selected node is the primary selection
- the inspector shows mixed values when the selection differs

When multiple nodes are selected:

- move, rotate, and scale act on shared bounds
- relative spacing between selected nodes is preserved
- group and reorder actions apply to the whole selection when valid

### Text editing

Text is edited as text layers rather than text blocks.

Visible changes:

- each text layer can be selected from the canvas or layer tree
- users edit text in place or through the inspector
- point text and area text are supported
- text style controls apply to the selected text node or text selection set

Important behavior:

- machine translation updates do not overwrite manually edited text
- rerunning translation refreshes the machine suggestion while preserving user edits

### Masks and cleanup editing

Masking and cleanup remain user-facing but should be simpler than the current ad hoc layer model.

Visible changes:

- mask editing is entered from the selected node
- the UI clearly indicates whether a node has a user mask, a system mask, or both
- users can edit their own cleanup or masking without losing pipeline-owned masking data

Required UI affordances:

- a visible mask badge or mask indicator in the layer tree
- a clear “edit mask” action for the selected node
- a clear distinction between user-authored mask data and system-generated mask data

### Generated outputs and preview modes

Generated outputs remain visible to the user, but they are presented as previews and publications rather than authored layers.

V2 should expose at least these preview modes:

- `Authored`
  - shows the authored layer tree over the page source
- `Inpainted Preview`
  - shows the latest published inpainted output for the current page
- `Rendered Preview`
  - shows the latest published final rendered output for the current page

Expected behavior:

- users can switch preview mode without changing authored content
- the UI clearly indicates when a preview is stale relative to the current revision
- users can inspect text sprite publications for individual text nodes
- users can compare current authored state against the latest generated preview

### Undo and redo

Undo and redo should feel editor-native.

Visible changes:

- one gesture equals one undo step
- dragging does not create hundreds of undo entries
- grouping, text commit, reorder, and mask edits are undoable
- pipeline reruns do not pollute the user undo chain

Expected UI behavior:

- undo and redo buttons reflect availability
- history actions apply to authored edits only
- preview outputs may refresh after undo or redo, but they are not themselves undo steps

### Pipeline reruns

Pipeline reruns must feel non-destructive.

Visible changes:

- users can rerun relevant pipeline stages without losing manual text edits
- OCR and annotation improvements update source-linked metadata
- translation reruns refresh machine suggestions
- render and inpaint reruns publish new previews for the current revision

The UI should clearly communicate:

- which outputs belong to which revision
- whether outputs are current or stale
- when a rerun is required to refresh previews

### Export behavior

Export should remain straightforward even as the internal model becomes richer.

Visible changes:

- users can export project bundles for sharing
- users can export rendered outputs and inpainted outputs
- PSD export is derived from the authored node tree

Important user expectation:

- what users see in the authored layer tree must match the authored structure in PSD export
- preview outputs are outputs, not extra authored PSD layers unless explicitly exported as such

## Transform model

`AffineTransform2D` should remain canonical.

Why:

- it composes correctly through nested groups
- it avoids ambiguous geometry rules
- it matches long-term editor needs better than `x/y/width/height/rotation` as source of truth

The UI can still expose friendly transform controls:

- x
- y
- width
- height
- rotation

But those are derived editing helpers, not the only stored representation.

## History model

Koharu V2 uses revision-based linear history.

Every user gesture commits one immutable transaction.

Examples:

- one drag
- one resize
- one rotate
- one brush stroke
- one mask stroke
- one text commit
- one group or reorder action

Each transaction stores:

- `tx_id`
- `base_revision`
- `new_revision`
- `origin`
- `history_effect`
- `operations`
- `inverse_operations`
- `affected_entities`
- `timestamp`

### History rules

- only user transactions participate in undo
- system publications do not consume undo slots
- redo is session-scoped
- saved revisions and snapshots are durable

### Transaction coalescing

Interactive operations should coalesce at gesture boundaries.

Examples:

- dragging for 2 seconds creates one move transaction
- typing a text edit creates one commit transaction, not one transaction per keystroke

## Storage model

The best fit for Koharu is a portable bundle-based working format.

### Working format

Use `.khrproj/` as the working project format.

Recommended layout:

```text
project.khrproj/
  manifest.json
  refs/head
  snapshots/<rev>.postcard
  transactions/<shard>/<rev>.postcard
  publications/<page_id>/<rev>.postcard
  blobs/<hash-prefix>/<hash-rest>
  lock
```

### Why this is the right fit

This fits Koharu better than a single mutable DB file because:

- project blobs are naturally file-oriented
- generated images can be large
- append-only transactions map well to filesystem storage
- portability stays simple
- failure recovery can be built around immutable files plus atomic head updates

### `.khr` interchange

Use `.khr` as a packed interchange format.

- export packs a `.khrproj/` bundle into one `.khr`
- import unpacks a `.khr` into a working `.khrproj/`

This keeps working storage optimized for editing while still giving users a single-file format for sharing and backup.

### Optional metadata index

If startup or history lookup later proves too slow, Koharu may add a small metadata index for:

- project summaries
- revision lookup
- thumbnail lookup

That is an optimization, not the foundation of V2.

## API model

HTTP and MCP should converge on one shared domain contract.

V2 public types should revolve around:

- `ProjectState`
- `PageState`
- `NodeRecord`
- `AffineTransform2D`
- `StyledRun`
- `TextStyle`
- `AnnotationSet`
- `TransactionRecord`
- `PublicationRecord`

The main mutation contract is:

```text
ApplyOperationsRequest { projectId, baseRevision, commitMessage, operations[] }
```

Operation families:

- `createNodes`
- `deleteNodes`
- `moveNodes`
- `reparentNodes`
- `reorderNodes`
- `patchNodeProps`
- `patchTransforms`
- `patchTextRuns`
- `patchMasks`
- `groupSelection`
- `ungroupNode`
- `publishGeneratedOutputs`

Stable IDs replace index-based addressing everywhere.

## Pipeline model

The pipeline becomes a page-scoped graph of non-destructive stages:

- detect
- segment
- ocr
- translate
- inpaint
- layout_text
- render_composite
- export_psd

Pipeline reruns should:

- update annotations
- update publications
- never directly overwrite authored text content
- never directly overwrite authored masks

## Implementation direction

This is the recommended implementation sequence for the current repository.

### Phase 1: Core types in `koharu-core`

Add and stabilize:

- project/page/node DTOs
- affine transform types
- styled text run types
- annotation types
- publication types
- transaction and operation types
- shared HTTP/MCP request and response DTOs

Remove old `Document` and `TextBlock` from the new V2 path instead of trying to bridge them indefinitely.

### Phase 2: Project state and storage in `koharu-app`

Implement:

- pure V2 project state helpers
- `.khrproj/` persistence
- revision replay
- snapshots
- publications
- undo and redo

Keep this logic in reusable application services, not in HTTP or MCP handlers.

### Phase 3: Shared service surface in `koharu-app`

Add application-level service functions for:

- create project
- open project
- import pages
- get project
- get page
- get history
- apply operations
- undo
- redo
- run pipeline
- rerun pipeline stages

These services should be the single backend contract used by every transport.

### Phase 4: HTTP V2 in `koharu-rpc`

Expose a clean `/api/v2` surface that maps directly onto the shared application services.

Recommended reads:

- `GET /projects`
- `GET /projects/{projectId}`
- `GET /projects/{projectId}/pages/{pageId}`
- `GET /projects/{projectId}/history`
- `GET /projects/{projectId}/publications`

Recommended writes:

- `POST /projects`
- `POST /projects/open`
- `POST /projects/import`
- `POST /projects/{projectId}/operations`
- `POST /projects/{projectId}/undo`
- `POST /projects/{projectId}/redo`
- `POST /projects/{projectId}/pipeline/run`

### Phase 5: MCP alignment in `koharu-rpc`

MCP tools should call the same V2 application services.

Rules:

- no index-based document selection
- no MCP-only domain model
- use `project_id`, `page_id`, `node_id`, and `revision`

### Phase 6: Generated API client in `ui`

Regenerate the frontend API client from the V2 OpenAPI schema.

Do not hand-edit generated client files.

Replace the old document-centric UI state with:

- `currentProjectId`
- `currentPageId`
- `selectedNodeIds`
- `primarySelectedNodeId`
- `selectionBounds`
- `historyCursor`

### Phase 7: Editor UI

Rebuild the editor around:

- a real authored layer tree
- multi-selection
- transform handles
- text editing on text nodes
- a read-only outputs panel for publications

The outputs panel should show generated previews without pretending they are authored layers.

### Phase 8: Pipeline publication

Move pipeline outputs away from direct mutation of page content.

Instead:

- detection and OCR update annotations
- translation updates machine translation fields
- render and inpaint stages publish outputs
- publications attach to the page by revision and pipeline signature

## Non-goals for V2

Out of scope:

- components and instances
- auto layout
- vector drawing and boolean ops
- arbitrary plugins
- multiplayer collaboration
- branching history UI
- pass-through group compositing
- frame nodes
- per-run rich text editing UI
- a generalized multi-mask stack

## Expected outcome

If Koharu adopts this design, it stops being a pipeline tool with a thin text-block editor and becomes a real layered editor with durable project structure.

That is the important shift:

- authored state becomes explicit
- generated state becomes non-destructive
- project storage becomes portable
- history becomes reliable
- HTTP and MCP stop diverging
- the UI gains a real layer and selection model

That foundation is the right long-term base for Koharu.
