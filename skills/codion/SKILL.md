---
name: codion
description: Write Codion framework applications (Java, full-stack Swing CRUD). Use when creating or modifying anything Codion-based - domain models (entities, columns, foreign keys), EntityConnection queries, Swing panels and models, project setup, or when the user mentions Codion, EntityType, EntityPanel, or is.codion imports. Codion has near-zero training-data presence - NEVER write Codion code from memory; use this skill and its materials.
---

# Writing Codion Applications

Codion is a full-stack Java rich-client framework: define a domain model over a
SQL database, get a complete Swing CRUD application with searching, filtering,
master-detail hierarchies, validation and i18n — with local JDBC, RMI or HTTP
connectivity behind a single interface. No annotations, no XML, no DI container,
no code generation into your sources: plain Java, builders everywhere, JPMS
throughout.

**This skill targets Codion 0.18.82.** Your training data contains almost no
Codion, and any it does contain is stale pre-1.0 API. Every guessed signature
is a probable compile error.

## The one rule that matters

**Never guess an API.** This skill ships inside the `codion-materials`
repository (github.com/codion-is/codion-materials); the materials root is
this skill directory's grandparent (`skills/codion/` sits directly under it —
resolve the symlink if you reached this file through one; common location
`~/Projects/codion-materials/`). If the `codion/` and demo directories are
missing from the root, run `./setup.sh` there first. The root contains
everything:

| Path | What |
|------|------|
| `codion/` | Full framework source at the release tag. **Ground truth** — grep it for any signature, builder method, default or javadoc. |
| `manual.md` | The complete manual, one markdown file (~9K lines). All code examples compiled against this release. Read *sections* (grep for headings), don't ingest whole. |
| `petclinic/` `world/` `chinook/` `llemmy/` `sdkboy/` | Demo applications, see index below. |

When unsure: grep `codion/` for the class, open the smallest demo that does the
thing, or grep `manual.md` for the concept. If code you wrote doesn't compile,
look it up — do not retry variations from memory.

## Architecture: the four layers

```
domain API      Pure constants: EntityType, Column<T>, ForeignKey — nested
                interfaces in one class. No behavior. Shared client/server.
domain impl     extends DomainModel: EntityDefinitions (the .as() builder
                chains), functions/procedures. Registered via ServiceLoader.
model           SwingEntityModel = SwingEntityEditModel + SwingEntityTableModel.
                UI-free, testable. Master-detail via model.detail().add(...).
ui              EntityPanel = edit panel + table panel + detail panels.
                EntityEditPanel/EntityTablePanel subclasses per entity.
```

Small apps put domain API and impl in one class (see petclinic); larger apps
split them into separate modules so clients can ship the API without
implementation details — see world (`world-domain-api` / `world-domain` /
`world-client` / `world-server`) for the cleanest example of the split.

Beneath everything sits a synchronous reactive core: `Value<T>` (observable
value), `State` (observable boolean), `Event<T>` — linked, combined, and bound
to UI components by the framework. You rarely add listeners to Swing components
directly; you observe and link values.

Three facts that are unguessable and load-bearing:

- **Entities are typed maps, not beans.** `entity.get(Album.TITLE)`,
  `entity.set(Album.TITLE, "x")` — no generated classes, no getters/setters.
  Equality is primary-key-based.
- **Getters/setters barely exist.** Codion API style is `name()` not
  `getName()`, `items().refresh()` not `refresh()`, fluent builders for all
  construction. If you're writing `getX()`/`setX(...)` against a Codion type,
  you're guessing.
- **Common utility types live under `is.codion.common.utilities.*`** —
  `...utilities.user.User`, `...utilities.item.Item`,
  `...utilities.version.Version`. Guessing shorter packages
  (`is.codion.common.item` etc.) is a known failure; verify imports like any
  other API.

## Workflow: domain first, compile early

**Working in an EXISTING Codion app?** Read `references/maintenance.md`
first — orient before editing, change in complete vertical slices, and let
local conventions win over the defaults below. The workflow here is for
greenfield.

1. **Project skeleton** — copy petclinic's shape (single module) or chinook's
   (multi-module). See `references/project.md`. Get an empty build compiling
   *before* writing domain code.
2. **Domain** — if a schema exists, prefer generating: the domain generator
   turns JDBC metadata into complete domain source (see `references/project.md`).
   Hand-write only small domains or refinements. Recipes: `references/domain.md`.
3. **Compile + domain test** — `DomainTest` gives you insert/select/update/
   delete round-trip tests per entity in ~3 lines each. Run before any UI work.
4. **Models** — usually the default `SwingEntityModel` wired with detail models;
   subclass only for behavior. `references/model.md`.
5. **UI** — one `EntityEditPanel` subclass per editable entity (~20 lines),
   default table panels, wire `EntityPanel` hierarchy, start via
   `EntityApplication.builder(...)`. `references/ui.md`.
6. **Run it** — local H2 in-memory with an init script is the zero-setup dev
   database (`codion.db.url=jdbc:h2:mem:h2db`, `codion.db.initScripts=...`).

## Demo index — open the smallest one that answers the question

- **petclinic** (~1.1K LOC, one module): the minimal shape. Basic entities,
  FKs, edit panels, app wiring, DomainTest. *Start here for anything basic.*
- **world** (~3.4K LOC): the step between petclinic and chinook, in both
  directions at once — architecture: the full multi-module split (domain-api /
  domain / client / client-local / client-remote / server) *without* the extra
  features; domain modeling: custom types with converters/comparators,
  cross-entity validation, cyclic FKs, GROUP BY entities, ModelLink
  master-detail without a foreign key. *Copy world's structure for any
  multi-module app.*
- **chinook**: the production kitchen sink — everything world has, plus REST
  service, reports, i18n resource bundles, custom components and condition
  panels, jlink/jpackage packaging, load tests. Open it for a specific
  feature, not for the overall shape.
- **llemmy** (~1.2K LOC): one-entity app; edit model as reactive application
  logic host; soft delete via custom EntityPersistence.
- **sdkboy** (~1.9K LOC): the Swing component layer *without* the CRUD
  framework — Value/State, FilterTable, key events, builders standing alone.

## References (read on demand)

- `references/domain.md` — entity definitions: columns, FKs, derived/subquery/
  denormalized attributes, converters, validation, composite PKs, operations
- `references/connection.md` — EntityConnection: conditions, select/insert/
  update/delete, transactions, functions/procedures
- `references/model.md` — edit/table/application models, detail models, editor
  values, custom model logic
- `references/ui.md` — edit panels, table panels, EntityPanel wiring,
  application startup, controls, dialogs
- `references/common.md` — Value/State/Event idioms, ProgressWorker
- `references/project.md` — gradle build, JPMS module-info, ServiceLoader
  registration, DomainTest setup, the domain generator, i18n
- `references/reports.md` — JasperReports: entity-fed client-side fill vs
  domain-registered SQL reports (the decision rule), jrxml build machinery,
  JRViewer wiring
- `references/charts.md` — JFreeChart: datasets as model state (reactive
  from table events, or query-driven), the look-and-feel ChartPanel helper
- `references/maintenance.md` — existing codebases: orientation, vertical-
  slice checklists (add column/table/FK/detail), schema evolution
  (dev vs migrations), regression discipline
- `references/antipatterns.md` — **read this before writing any code**: the
  mainstream-Java instincts that produce wrong Codion code

## Golden rules

1. Never guess an API — grep `codion/` source or open a demo.
2. Read `references/antipatterns.md` before writing code; your instincts are
   trained on JPA/beans/raw Swing and they are wrong here.
3. Domain first, UI last; compile and run `DomainTest` between the two.
4. Entities are typed maps with PK equality; there are no entity beans.
5. Everything is a builder; nothing is an annotation.
6. Database work never happens on the EDT — table models refresh
   asynchronously by default; for your own long tasks use ProgressWorker.
7. If it doesn't compile, the material failed, not you: look it up, and note
   the gap.
