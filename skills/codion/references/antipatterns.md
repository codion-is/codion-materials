# Codion Anti-Patterns

Your training data is saturated with JPA, Spring, bean conventions and raw
Swing. Codion deliberately rejects most of that. Each entry below: the code
you will be *tempted* to write, what to write instead, and why.

Verified against Codion 0.18.80.

## 1. Entity beans / JPA-style classes

**Tempted:**
```java
@Entity @Table(name = "artist")
public class Artist {
    @Id private Long id;
    private String name;
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
}
```

**Codion:** there are no entity classes. An entity is a typed map; the domain
is constants plus definitions:
```java
public interface Artist {
    EntityType TYPE = DOMAIN.entityType("chinook.artist");
    Column<Long> ID = TYPE.longColumn("id");
    Column<String> NAME = TYPE.stringColumn("name");
}
// usage — no generated or hand-written bean anywhere:
Entity artist = entities.entity(Artist.TYPE)
        .with(Artist.NAME, "Metallica")
        .build();
String name = artist.get(Artist.NAME);
artist.set(Artist.NAME, "Pantera");
```
**Why:** no annotation processing, no lazy-loading proxies, no
detached-instance lifecycle bugs. Column access is typed via `Column<T>`,
equality is primary-key-based, and the domain stays a compile-time-checked
description of the schema.

## 2. equals/hashCode/DTO plumbing for entities

**Tempted:** writing `equals`, `hashCode`, `toString`, or mapper classes for
entity data.

**Codion:** `Entity` already implements PK-based `equals`/`hashCode`, and
`toString` is controlled by the entity's `.formatter(...)` in its definition.
Entities pass through all layers as-is; DTO records exist only at REST/JSON
boundaries (see chinook's `Dto` records in `Chinook.java`).

**Caution the other way:** because equality is PK-only, two instances with the
same PK but different column values are *equal*. Never use equality to detect
modified data — use `entity.modified()` or compare values explicitly.

## 3. String SQL / JPQL / Criteria API

**Tempted:** `"SELECT * FROM track WHERE genre_id = ?"` or a repository method
spelling out a query.

**Codion:** conditions are built from the column constants:
```java
List<Entity> tracks = connection.select(Track.GENRE_FK.in(genres));
Entity metallica = connection.selectSingle(Artist.NAME.equalTo("Metallica"));
```
SQL fragments appear in exactly two places: `.subquery(...)` columns and
custom `ConditionType` templates in the domain implementation — never in
client code.

## 4. DAO / Repository / Service layers

**Tempted:** `ArtistRepository`, `ArtistService`, `ArtistDao` wrapping data
access.

**Codion:** `EntityConnection` *is* the data layer, for every entity. It is
already an abstraction over local JDBC / RMI / HTTP. Logic that must run
server-side or transactionally becomes a domain function/procedure
(`FunctionType`/`ProcedureType`, defined in the domain, executed via
`connection.execute(...)`). Client-side application logic belongs in edit/table
model subclasses — not in a parallel service hierarchy.

## 5. Raw Swing components and listeners

**Tempted:**
```java
JTextField nameField = new JTextField(20);
nameField.getDocument().addDocumentListener(...);
panel.add(nameField);
```

**Codion:** inside an `EntityEditPanel`, components are created bound:
```java
@Override
protected void initializeUI() {
    create().textField(Artist.NAME);       // created AND bound to the editor
    setLayout(gridLayout(1, 1));
    addInputPanel(Artist.NAME);            // caption label + component
}
```
Outside edit panels, use the `Components` builders
(`is.codion.swing.common.ui.component.Components`) and link them to
`Value`/`State` — the builder's `.link(value)` does the two-way binding.
Hand-wired `DocumentListener`/`ActionListener` synchronization is nearly
always wrong.

## 6. JTable + DefaultTableModel / AbstractTableModel

**Tempted:** extending `AbstractTableModel`, wiring a `TableRowSorter`.

**Codion:** entity tables are `SwingEntityTableModel` + `EntityTablePanel` —
sorting, filtering, column reordering, conditions, export and refresh are
built in. For non-entity data, `FilterTableModel`/`FilterTable` from
swing-common (see sdkboy). You should essentially never touch `JTable`
directly.

## 7. Boolean flags and manual enabled/disabled toggling

**Tempted:** `private boolean loading;` plus `button.setEnabled(!loading)`
sprinkled through callbacks.

**Codion:** observable `State`, declared once, bound everywhere:
```java
State active = State.state();
Control.builder()
        .command(this::doIt)
        .enabled(active.not())     // stays correct forever
        .build();
```
Combine with `State.and(...)`/`State.or(...)`/`.not()`. If you are calling
`setEnabled` in a listener, look for the `State` you should be binding to
instead — component and control builders all accept `.enabled(ObservableState)`.

## 8. PropertyChangeSupport / custom observer plumbing

**Tempted:** `addPropertyChangeListener`, hand-rolled listener lists.

**Codion:** `Event<T>`, `Value<T>`, `State` are the observer substrate,
everywhere and synchronously. Expose `Observer<T>`/`ObservableState` from your
own classes; consumers use `.addListener(Runnable)` / `.addConsumer(Consumer)`.

## 9. SwingWorker / raw threads for background work

**Tempted:** `new SwingWorker<...>()` or `new Thread(...)` for a long task.

**Codion:** `ProgressWorker` (in `codion-common-model`), or in UI code the
dialog-integrated form:
```java
Dialogs.progressWorker()
        .task(this::longRunningQuery)   // off the EDT
        .owner(this)
        .onResult(this::showResult)     // back on the EDT
        .execute();
```
Note that `SwingEntityTableModel` refreshes asynchronously by default — do not
add your own threading around table refresh.

## 10. get/set naming and inventing methods by Java convention

**Tempted:** `model.getTableModel()`, `table.getSelectedItems()`,
`editModel.setValue(...)`, `addSelectionListener(...)`.

**Codion:** accessor style has no `get`/`set` prefixes and state is reached
through composed accessors:
```java
tableModel().selection().items().get()      // selected entities
tableModel().items().refresh()              // refresh
editModel().editor().value(Album.TITLE)     // an EditorValue — observable
panel.detail().add(childPanel)              // detail panel
```
This is the single most common source of hallucinated compile errors. If a
method name occurs to you "because that's what it would be called in Java",
grep the framework source before typing it.

## 11. DI containers and singletons

**Tempted:** Spring/Guice wiring, static `INSTANCE` holders, service locators.

**Codion:** one object travels: `EntityConnectionProvider`, passed via
constructors. Models receive it, panels receive models. Pluggability
(database dialect, connection type, domain) goes through `ServiceLoader` and
system properties — never a DI framework.

## 12. Hardcoded UI strings when the app is localized

**Tempted:** `.caption("Name")` everywhere, `"Are you sure?"` literals.

**Codion:** fine for single-locale apps (petclinic does it). For localized
apps, resource bundles keyed per class (`Chinook$Artist.properties`,
`Chinook$Artist_is_IS.properties` — see chinook). Note: when a resource-bundle
caption exists it *wins over* `.caption()` in code.

## 13. Immediate-write UI assumptions

**Tempted:** treating each keystroke/selection as a pending database change,
adding your own "dirty" tracking.

**Codion:** the edit model's `editor()` holds the entity being edited;
`editor().modified()` and `editor().exists()` are observable states the UI
(buttons, confirmations) already binds to. Insert/update/delete are explicit
editor/model operations with validation built in — you never track dirtiness
yourself.

## 14. Doing visibility/layout logic in the model, or queries in the UI

The layering is strict and the compiler won't stop you from violating it:
models must not import Swing components; panels should not build conditions or
call `EntityConnection` for data the table/edit model already manages. If a
panel needs data, ask its model; if a model needs UI, expose a
`State`/`Value`/`Event` and let the panel observe it.
