# Working in an Existing Codion Codebase

Verified against Codion 0.18.80. For maintenance work — adding columns,
tables, panels, charts or reports to an app you did not write — the recipes
in the other references apply unchanged; THIS file covers what is different:
orienting, changing in complete vertical slices, and schema evolution.

## Rule zero: local convention beats skill default

Existing apps have made their choices — captions in code vs resource
bundles, single vs multi module, combo boxes vs search fields, formatting
style, package layout. Detect and mirror them. A technically-correct change
in the wrong local dialect is a bad change. Where this file or other
references conflict with what the codebase consistently does, the codebase
wins.

## Orientation — 10 minutes before any edit

The domain is the hub; everything radiates from it.

1. Find the domain: grep `extends DomainModel` (impl) and `domainType(`
   (API). Single class or api/impl split? This tells you the app's scale
   posture.
2. Read ONE entity end-to-end before touching anything: its interface
   constants → its definition method → its edit panel → where its
   `EntityPanel` is wired (app panel: main tab, detail, or support panel) →
   its test. That's the app's dialect in one slice.
3. Check: i18n resource bundles next to classes? (then captions belong
   there, not in code) — custom edit/table models? (then app logic lives in
   the model layer, follow suit) — `ColumnTemplate`s at the top of the impl?
   (then reuse them).
4. Run `./gradlew build` BEFORE changing anything — know the baseline is
   green, know how long it takes.

## Vertical-slice checklists

A Codion change is a slice through fixed layers. Walk the whole slice —
half-slices compile but ship broken UX (a column no one can edit, an entity
no one can reach).

### Add a column to an existing entity

1. DDL — schema script (dev) or new migration (production; see below).
2. API: `Column<T>` constant on the entity interface.
3. Impl: definition line in `.attributes(...)` — mirror the schema onto it:
   `.nullable`, `.maximumLength`, `.fractionDigits(s)` + `.range(...)` for
   DECIMAL(p,s)/CHECK (see domain.md's DECIMAL trap), `.items(...)` for
   CHECK IN, `.readOnly(true)` for DB-populated columns. Caption per local
   convention (code or bundle).
4. UI: if user-editable, `create().<component>(COL)` + `addInputPanel(COL)`
   in the edit panel (adjust the grid layout dimensions!). Table shows it
   automatically.
5. i18n: add the key to the entity's `.properties` files if the app uses
   bundles (ALL locales).
6. Build — the entity's existing DomainTest round-trip covers the new
   column automatically.

### Add a table (new entity)

Everything in the greenfield references, PLUS wiring into the existing app:

1. DDL (+ seed data if the dev script carries any).
2. API interface + impl definition method + register in the constructor's
   `add(...)`.
3. Model: if it's a detail of an existing master, add the detail model where
   the app builds its model graph (app model or master's model class).
4. UI: edit panel class; `EntityPanel` wired as detail
   (`masterPanel.detail().add(...)`) or support panel builder — match how
   the app mounts comparable entities.
5. Test: one `test(NewEntity.TYPE)` method in the existing domain test.
6. i18n per convention.

### Add a foreign key between existing entities

DDL constraint → FK column constant (if new) + `ForeignKey` constant → BOTH
`.column()` and `.foreignKey()` entries in the definition → combo box /
search field in the edit panel → consider the reverse side: does the target
entity now deserve a detail panel of these?

### Add a detail panel to an existing master

Model side: `masterModel.detail().add(new SwingEntityModel(...))` (or
ForeignKeyModelLink config for persist/refresh behavior). UI side:
`masterPanel.detail().add(new EntityPanel(...))`. Both places — model link
without panel is invisible; panel without model link doesn't filter.

### Add a chart or report

Follow `references/charts.md` / `references/reports.md` for the pattern;
maintenance-specific: mount where the app mounts comparable things (a tab
beside existing tabs, a control beside existing controls — chinook puts
analytics in a tab, reports on the table panel's PRINT control), and reuse
the app's existing look-and-feel chart helper if one exists.

## Schema evolution: dev mode vs production

- **Dev/demo mode** (in-memory H2 + `codion.db.initScripts` pointing at a
  create script): just edit the script — the database is rebuilt every run.
  All the demos work this way.
- **Production mode** (persistent database): never edit the historical
  scripts — add a migration. Chinook demonstrates the pattern:
  `src/main/resources/db/migration/V1__Initial_schema.sql`, `V2__...`,
  `V3__...` applied via its migration classes
  (`is.codion.demos.chinook.migration`). Match whatever migration mechanism
  the app already uses (chinook's, Flyway, hand-rolled) — do not introduce
  a new one for a one-column change.

Either way the domain definition must end up mirroring the actual schema —
the definition IS the app's schema contract, and DomainTest round-trips
verify it against the real database.

## Renames and removals

Domain constants make renames compile-time-safe: rename the constant and
the compiler finds every usage (panels, conditions, tests). The STRING in
the constant (`TYPE.integerColumn("station_number")`) must keep matching
the database — renaming a Java constant does not rename a column. Removals:
delete the constant and follow the compiler errors; check i18n property
files by hand (no compiler there).

## Regression discipline

- Full `./gradlew build` after the slice — the existing DomainTests are the
  regression net, and they cover new columns/entities almost for free.
- Do not reformat, "clean up", or restructure code you were not asked to
  touch — maintenance diffs should read as exactly the requested change.
