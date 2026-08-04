# UI Layer Recipes

Verified against Codion 0.18.82. Source of truth: `codion/swing/framework-ui/`
(entity panels) and `codion/swing/common-ui/` (component builders, controls,
dialogs). Canonical examples: petclinic (minimal), chinook (custom everything).

## EntityEditPanel — one small subclass per editable entity

```java
public final class PetEditPanel extends EntityEditPanel {

    public PetEditPanel(SwingEntityEditModel editModel) {
        super(editModel);
    }

    @Override
    protected void initializeUI() {
        focus().initial().set(Pet.NAME);           // focus here on activation

        create().comboBox(Pet.OWNER_FK);            // created AND bound
        create().textField(Pet.NAME);
        create().comboBoxPanel(Pet.PET_TYPE_FK, this::createPetTypeEditPanel)
                .includeAddButton(true);            // combo + add-new button
        create().temporalFieldPanel(Pet.BIRTH_DATE);

        setLayout(gridLayout(2, 2));                // Layouts.gridLayout

        addInputPanel(Pet.OWNER_FK);                // caption label + component
        addInputPanel(Pet.NAME);
        addInputPanel(Pet.PET_TYPE_FK);
        addInputPanel(Pet.BIRTH_DATE);
    }

    private PetTypeEditPanel createPetTypeEditPanel() {
        return new PetTypeEditPanel(new SwingEntityEditModel(PetType.TYPE,
                editModel().connection()));
    }
}
```

The `create()` factory covers the attribute types: `textField`, `textArea`,
`comboBox` (foreign keys), `itemComboBox` (item-list columns — see
`references/domain.md`), `comboBoxPanel`, `searchField`
(FK search for large tables), `checkBox`, `temporalField`/`temporalFieldPanel`,
`spinner` variants, and more — each returns a component builder for further
configuration. Components are automatically bound to the editor, with
validation indication and undo. Grep
`codion/swing/framework-ui/.../EntityEditComponentFactory` or existing edit
panels when unsure which method fits an attribute.

Custom (non-attribute) components: build with `Components` builders and link
to values — see `references/common.md` and chinook's `TrackEditPanel`/
`DurationPanel` for a fully custom multi-field component.

## EntityTablePanel — default is usually enough

The default `EntityTablePanel` provides sorting, column filters/reordering,
a condition panel, refresh, CRUD popup menu, Excel-style export. Subclass to
configure or add controls:

```java
public final class CustomerTablePanel extends EntityTablePanel {

    public CustomerTablePanel(SwingEntityTableModel tableModel) {
        super(tableModel, config -> config
                .refreshButtonVisible(RefreshButtonVisible.ALWAYS));
    }

    @Override
    protected void setupControls() {
        // repurpose the standard PRINT control (popup menu + toolbar):
        control(PRINT).set(Control.builder()
                .command(this::viewCustomerReport)
                .caption("Customer report")
                .icon(FrameworkIcons.instance().print())
                .enabled(tableModel().selection().empty().not())
                .build());
    }
    ...
}
```
`PRINT` is from `EntityTablePanel.ControlKeys` (static import). Config options
worth knowing: `.editable(attributes -> attributes.remove(...))` (popup-menu
editing), `.conditionView(SIMPLE)`, `.conditionPanel(factory)` (custom
condition panel — see chinook's `InvoiceConditionPanel`),
`.table(t -> ...)` for table tweaks. Grep `EntityTablePanel.Config` for all.

## EntityPanel — wiring the hierarchy

```java
// a panel per entity, detail panels nested:
EntityPanel ownersPanel = new EntityPanel(ownersModel,
        new OwnerEditPanel(ownersModel.editModel()));
EntityPanel petsPanel = new EntityPanel(petsModel,
        new PetEditPanel(petsModel.editModel()));
ownersPanel.detail().add(petsPanel);
```

The panel caption defaults to the entity's domain caption — do NOT set
`config.caption(...)` redundantly. Override it only when the context calls
for a different one, e.g. a junction detail panel captioned by its far side:

```java
// BookAuthor's domain caption is "Book authors"; under a Book master
// the panel reads better as "Authors":
new EntityPanel(bookAuthorModel,
        new BookAuthorEditPanel(bookAuthorModel.editModel()),
        config -> config.caption("Authors"));
```
The third argument to `EntityPanel` can also be a custom `EntityTablePanel`
subclass; models come from the application model
(`applicationModel.models().get(Owner.TYPE)`, `master.detail().get(Pet.TYPE)`).

Support/lookup panels (opened on demand from the View menu, not tabs):

```java
EntityPanel.Builder petTypePanelBuilder = EntityPanel.builder()
        .entityType(PetType.TYPE)
        .panel(MyAppPanel::createPetTypePanel);   // Function<EntityConnection, EntityPanel>
```

## Application panel and startup

```java
public final class PetclinicAppPanel extends EntityApplicationPanel<PetclinicAppModel> {

    public PetclinicAppPanel(PetclinicAppModel appModel) {
        super(appModel, createPanels(appModel), createSupportPanelBuilders());
    }

    public static void main(String[] args) {
        // FlatLaf validation indication on input components (invalid = tinted)
        ValidIndicator.INDICATOR_CLASS.set("is.codion.plugin.flatlaf.indicator.FlatLafValidIndicator");
        ReferentialIntegrityErrorHandling.REFERENTIAL_INTEGRITY_ERROR_HANDLING
                .set(ReferentialIntegrityErrorHandling.DISPLAY_DEPENDENCIES);
        EntityApplication.builder(PetclinicAppModel.class, PetclinicAppPanel.class)
                .domain(Petclinic.DOMAIN)
                .startupDialog(false)               // see note below
                .defaultLookAndFeel(LightOwl.class)
                .defaultUser(User.parse("scott:tiger"))
                .start();
    }
}
```

**Always set a FlatLaf look and feel.** Without `.defaultLookAndFeel(...)`
the application starts in Swing's default Metal — dull and dated. Include
both theme plugin dependencies, as all the demos do
(`codion-plugin-flatlaf-themes` + `codion-plugin-flatlaf-intellij-themes`,
see `references/project.md`) — users can then switch themes via the View
menu. `LightOwl` (`is.codion.plugin.flatlaf.intellij.themes.material.LightOwl`)
is a reasonable default; any theme class works. The FlatLaf
`ValidIndicator` line above is also worth its one line: invalid inputs get
visual indication for free (`ValidIndicator` is
`is.codion.swing.common.ui.component.indicator.ValidIndicator`).
User handling: `.defaultUser(user)` pre-fills the login dialog;
`.user(User.parse("scott:tiger"))` sets the user outright — no login dialog,
so the application starts with no interaction at all: what you want for dev
iteration and automated/scripted launches (e.g. driving the app for
testing).

The startup dialog is unrelated to login: it is just an indeterminate
progress bar shown while the application loads, requiring no interaction —
it never blocks anything (including programmatic control). For applications
that start quickly, `.startupDialog(false)` simply spares the user a dialog
that flickers and is gone.

The connection type is decided by system properties, not code:
`codion.client.connectionType=local|remote|http` plus the matching connection
module on the runtime path (see `references/project.md`).

## Controls, key events, dialogs

```java
Control control = Control.builder()
        .command(this::doIt)
        .caption("Do it")
        .enabled(someState)          // ObservableState — stays in sync
        .build();

KeyEvents.builder()                  // is.codion.swing.common.ui.key.KeyEvents
        .keyCode(KeyEvent.VK_INSERT)
        .action(control)
        .enable(somePanel);

// long task with progress dialog — result handled back on the EDT:
Dialogs.progressWorker()
        .task(this::fetchReport)
        .owner(this)
        .title("Working...")
        .onResult(this::showResult)
        .execute();

// other dialogs — grep Dialogs for the full set:
Dialogs.builder().component(comp).owner(this).title("...").show();
```

## Non-entity UI: component builders

Everything in `is.codion.swing.common.ui.component.Components` is a builder
that can `.link(value)` to a `Value`/`State`:

```java
JTextField field = Components.stringField()
        .link(someStringValue)
        .columns(20)
        .build();
```
sdkboy is the demo for this layer standing alone (FilterTable included).
