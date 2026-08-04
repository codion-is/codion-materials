# Model Layer Recipes

Verified against Codion 0.18.82. Source of truth:
`codion/swing/framework-model/` (and `codion/framework/model/` for the
UI-agnostic base). Canonical examples: petclinic (wiring), llemmy and
chinook (application logic in models).

## The pieces

- `SwingEntityModel` — pairs an edit model and a table model for one entity,
  holds detail models
- `SwingEntityEditModel` — the entity being edited: values, validation,
  insert/update/delete
- `SwingEntityTableModel` — rows, selection, filtering, the query
- `SwingEntityApplicationModel` — the root: the connection + top-level
  models

Models are UI-free — fully testable without a display.

## Wiring a master-detail hierarchy

```java
public final class PetclinicAppModel extends SwingEntityApplicationModel {

    public static final Version VERSION =
            Version.parse(PetclinicAppModel.class, "/version.properties");

    public PetclinicAppModel(EntityConnection connection) {
        super(connection, List.of(createOwnersModel(connection)));
    }

    private static SwingEntityModel createOwnersModel(EntityConnection connection) {
        SwingEntityModel ownersModel = new SwingEntityModel(Owner.TYPE, connection);
        SwingEntityModel petsModel = new SwingEntityModel(Pet.TYPE, connection);
        // pre-populate FK combo box models used by the edit UI:
        petsModel.editor().comboBoxModels().initialize(Pet.OWNER_FK, Pet.PET_TYPE_FK);

        ownersModel.detail().add(petsModel);      // master-detail link (via FK)

        ownersModel.tableModel().items().refresh();

        return ownersModel;
    }
}
```

Selecting rows in the master filters the detail automatically. Reaching
models: `applicationModel.models().get(Owner.TYPE)`,
`ownersModel.detail().get(Pet.TYPE)`.

Master-detail WITHOUT a foreign key (e.g. linked by a plain column):
`ModelLink` — see the `world` demo.

## The edit model and its editor

`editModel().editor()` is the entity being edited:

```java
EditorValue<String> title = editor().value(Album.TITLE);  // observable + settable
title.set("Master of Puppets");
editor().entity().exists()      // ObservableState: is this a persisted entity?
editor().entity().modified()    // ObservableState: unsaved changes?
editor().entity().defaults()    // reset to default values
```

Per-attribute behavior on a fresh entity: `editor().value(attr).persist()`
(a `State` — keep the value across inserts, default true for FKs), defaults
from the domain's `.defaultValue(...)`.

Application logic lives in edit model subclasses (this one adds a
database-uniqueness validation — from petclinic):

```java
public final class VetSpecialtyEditModel extends SwingEntityEditModel {

    public VetSpecialtyEditModel(EntityConnection connection) {
        super(VetSpecialty.TYPE, connection);
        editor().validator().set(new VetSpecialtyValidator());
        editor().comboBoxModels().initialize(VetSpecialty.VET_FK, VetSpecialty.SPECIALTY_FK);
        editor().value(VetSpecialty.VET_FK).persist().set(false);
        editor().value(VetSpecialty.SPECIALTY_FK).persist().set(false);
    }

    private final class VetSpecialtyValidator implements EntityValidator {

        @Override
        public void validate(Entity entity) throws EntityValidationException {
            EntityValidator.super.validate(entity);   // standard validation first
            int rowCount = connection().count(where(and(
                    VetSpecialty.SPECIALTY.equalTo(entity.get(VetSpecialty.SPECIALTY)),
                    VetSpecialty.VET.equalTo(entity.get(VetSpecialty.VET)))));
            if (rowCount > 0) {
                throw new EntityValidationException("Vet/specialty combination already exists");
            }
        }
    }
}
```
Richer examples: chinook's `InvoiceLineEditModel` (updates invoice totals
around CUD via a domain procedure), llemmy's chat model (soft delete via
custom `EntityPersistence`).

Reacting to inserts/updates/deletes across models: editors publish to a
static per-entity-type event bus —
`PersistenceEvents.persistenceEvents(Artist.TYPE)` with `inserted()`,
`updated()`, `deleted()` and combined `persisted()` observers. Framework
models already keep each other in sync through it (new/changed/deleted
entities propagate to table models and combo box models); observe it for your
own logic, and `accept(...)` on it if you persist entities outside an editor
(see chinook's `ArtistTableModel`).

## The table model

```java
tableModel().items().refresh();                       // async in Swing land
tableModel().items().get();                           // visible items
tableModel().selection().items().get();               // selected entities
tableModel().selection().item().get();                // single selection
tableModel().selection().empty();                     // ObservableState
tableModel().selection().items().addConsumer(this::selectionChanged);
```

The query behind the table is `tableModel().query()` (an `EntityQueryModel`):
```java
query().limit().set(500);                                // max rows fetched
query().condition().get(Invoice.CUSTOMER_FK)             // a ForeignKeyConditionModel
        .operands().equal().set(customer);               // set its operand
query().conditionRequired().set(true);                   // refuse unfiltered refresh (automatically enabled for detail models)
```
(The condition-model API is deep — operands are `equal()`, `in()`,
`upper()`/`lower()` etc. Grep `EntityQueryModel`/`ForeignKeyConditionModel`
and see the manual's EntityQueryModel section before going beyond the basics;
chinook's `CustomerModel` and `TrackTableModel` are working examples.)

Editing directly through the table model is possible when enabled
(`tableModel().editable()`) — chinook's TrackTablePanel demonstrates.

## Combo box / search models

- `editor().comboBoxModels().initialize(FK...)` — eager-populate FK combos
  (models are created lazily otherwise)
- `EntitySearchModel` backs search fields for large tables — configured via
  the domain's `.searchable(true)` columns

## Testing

Models are UI-free: plain JUnit — instantiate with a local
`EntityConnection` in try-with-resources (close is terminal), drive and
assert (see `petclinic/src/test/.../VetSpecialtyEditModelTest.java`):

```java
try (EntityConnection connection = LocalEntityConnection.builder()
        .domain(new PetclinicImpl())
        .user(User.parse("scott:tiger"))
        .build()) {
    VetSpecialtyEditModel model = new VetSpecialtyEditModel(connection);
    // drive and assert
}
``` Required system
properties for tests (set in gradle): `codion.db.url`,
`codion.db.initScripts`, `codion.test.user`.

For domain model testing (`DomainTest`), see `references/domain.md`.
