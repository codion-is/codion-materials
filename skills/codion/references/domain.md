# Domain Modeling Recipes

Verified against Codion 0.18.80. Canonical examples: `petclinic/` (minimal),
`world/` (advanced), `chinook/` (production, api/impl split). When a builder
method is in doubt, grep `codion/framework/domain/`.

## The shape

Domain API — nested interfaces holding constants (no behavior):

```java
public final class Petclinic extends DomainModel {

    public static final DomainType DOMAIN = domainType("Petclinic");

    public Petclinic() {
        super(DOMAIN);
        add(vet(), specialty(), owner(), pet(), visit());   // every entity
    }

    public interface Pet {
        EntityType TYPE = DOMAIN.entityType("petclinic.pet");   // schema.table

        Column<Integer> ID = TYPE.integerColumn("id");
        Column<String> NAME = TYPE.stringColumn("name");
        Column<LocalDate> BIRTH_DATE = TYPE.localDateColumn("birth_date");
        Column<Integer> OWNER_ID = TYPE.integerColumn("owner_id");

        ForeignKey OWNER_FK = TYPE.foreignKey("owner_fk", OWNER_ID, Owner.ID);
    }
    ...
}
```

Column factories: `integerColumn`, `longColumn`, `stringColumn`,
`booleanColumn`, `localDateColumn`, `localDateTimeColumn`, `bigDecimalColumn`,
`doubleColumn`, `byteArrayColumn`, `shortColumn`, `characterColumn`, and
generic `TYPE.column("name", SomeType.class)` for enums/custom types.

Larger apps split API (public interface, shipped to clients) from
implementation (an impl class extending `DomainModel` defining the
`EntityDefinition`s) — see chinook's `Chinook.java` / `ChinookImpl.java`.

## Entity definitions — the .as() chains

One private method per entity, called from the constructor's `add(...)`:

```java
private EntityDefinition pet() {
    return Pet.TYPE.as()
            .attributes(
                    Pet.ID.as()
                            .primaryKey()
                            .generator(identity()),        // auto-increment
                    Pet.NAME.as()
                            .column()
                            .caption("Name")
                            .searchable(true)              // used by search fields
                            .maximumLength(30)
                            .nullable(false),
                    Pet.BIRTH_DATE.as()
                            .column()
                            .caption("Birth date")
                            .nullable(false),
                    Pet.OWNER_ID.as()
                            .column()
                            .nullable(false),              // the FK column itself
                    Pet.OWNER_FK.as()
                            .foreignKey()
                            .caption("Owner"))
            .caption("Pets")
            .formatter(Pet.NAME)                           // entity toString
            .orderBy(ascending(Pet.NAME))
            .build();
}
```

Static imports used above:
`is.codion.framework.domain.entity.attribute.Column.Generator.identity`,
`is.codion.framework.domain.entity.OrderBy.ascending`.

Entity-level builder options (after `.attributes(...)`):

- `.caption("...")` — display name
- `.formatter(column)` or `.formatter(EntityFormatter.builder().value(A).text(", ").value(B).build())` — what `entity.toString()` / FK displays show
  - Getting a formatted value in NON-UI code: `entity.toString()` uses the
    formatter; `entity.formatted(attribute)` formats a single attribute
    value. There is NO `entity.string(...)` — a phantom method three
    independent agents have guessed; don't be the fourth.
- `.orderBy(ascending(...))` or `OrderBy.builder().ascending(X).descending(Y).build()`
- `.smallDataset(true)` — hint: combo boxes are fine for this entity
- `.readOnly(true)` — no insert/update/delete
- `.validator(...)` — entity-level validation (see below)
- `.table("actual_table")` / `.selectQuery(...)` — when the entity name isn't
  the table, or the entity is based on a custom query/join

## Primary keys

- Single auto-increment: `.primaryKey().generator(identity())`
- Other generators exist (sequence, queried) — grep `Column.Generator` in
  `codion/framework/domain/` for the factory methods
- Composite (e.g. a junction table):
  ```java
  VetSpecialty.VET.as().primaryKey(0).updatable(true),
  VetSpecialty.SPECIALTY.as().primaryKey(1).updatable(true),
  ```

## Foreign keys

API: `ForeignKey OWNER_FK = TYPE.foreignKey("owner_fk", OWNER_ID, Owner.ID);` —
define BOTH the underlying column (as `.column()`) and the FK (as
`.foreignKey()`) in the definition.

- FK values in an entity are entities: `pet.get(Pet.OWNER_FK)` returns the
  owner `Entity` (populated to the configured reference depth, default 1).
- `.foreignKey().include(Owner.LAST_NAME, ...)` — restrict/eager-set the
  referenced columns fetched; `.referenceDepth(n)` for deeper graphs.
  Depth 1 is right almost always — FK fetches are batched, so there is no
  N+1 problem to work around.

## Beyond plain columns

```java
// computed by the database on select, via subquery:
Artist.NUMBER_OF_ALBUMS.as()
        .subquery("SELECT COUNT(*) FROM chinook.album WHERE album.artist_id = artist.id")

// computed client-side from other attributes (Attribute, not Column, in the API):
InvoiceLine.TOTAL.as()
        .derived()
        .from(InvoiceLine.QUANTITY, InvoiceLine.UNITPRICE)
        .with(new InvoiceLineTotal())          // a DerivedValue<BigDecimal>

// flattened from a referenced entity (kept in sync client-side):
Track.ALBUM_ARTIST.as()
        .denormalized()
        .from(Track.ALBUM_FK)
        .using(Album.ARTIST_FK)

// default value on new entities:
Invoice.DATE.as().column().defaultValue(LocalDate::now)

// audit columns populated by the DATABASE (DEFAULT CURRENT_TIMESTAMP /
// DEFAULT USER() in the DDL): mark readOnly so the client never writes
// them and the DB defaults apply:
Album.INSERT_TIME.as().column().readOnly(true),
Album.INSERT_USER.as().column().readOnly(true)
```
(Adapt names — these shapes are from chinook; see `Chinook.java`/`ChinookImpl.java`
for the exact working code.)

When the same column configuration recurs across many entities (audit
columns, standard name columns), chinook defines reusable `ColumnTemplate`s
(`REQUIRED_SEARCHABLE`, `INSERT_TIME`, `INSERT_USER` — `ChinookImpl.java`
top) applied via `.column(template)` — one definition, applied everywhere,
instead of pasting the chain per entity.

## Columns with a fixed set of valid values

Use these for SQL `CHECK (x IN (...))` constraints — declaring the valid set
on the definition gives combo boxes in the UI AND keeps `DomainTest`'s
random-value generation inside the constraint (it picks from the declared
items). Two patterns; pick by whether the values need display captions:

**Item list** — when the stored values are codes needing captions
(`1`/`2`/`3` → "One"/"Two"/"Three", `"s"`/`"l"` → "Small"/"Large"), or plain
strings you want offered as a pick-list. Declares the valid values, and edit
panels get `create().itemComboBox(column)`:

```java
// from the world demo — Item.item(value) or item(value, caption):
// import is.codion.common.utilities.item.Item;
// import static is.codion.common.utilities.item.Item.item;
private static final List<Item<String>> CONTINENT_ITEMS = List.of(
        item("Africa"), item("Antarctica"), item("Asia"),
        item("Europe"), item("North America"), item("Oceania"),
        item("South America"));

Country.CONTINENT.as()
        .column()
        .caption("Continent")
        .items(CONTINENT_ITEMS)
        .nullable(false)
```

**Enum + converter** — when you want a typed enum in code (see below). Both
are fine for enum-ish columns; enums can even be combined with items. There
is no hard rule — use items when captions differ from the stored values,
a plain enum when the enum name (or its `toString()`) suffices. When the
stored values are codes (`'M'`/`'F'`, `1`/`2`/`3`), give the items proper
captions — `item("M", "Male")` — bare `item("M")` shows the raw code in
every combo box and table cell.

## Custom types and converters

Column of a non-SQL type + a `Column.Converter<T, C>` (petclinic stores an
enum as a string):

```java
Column<PhoneType> PHONE_TYPE = TYPE.column("phone_type", PhoneType.class);

Owner.PHONE_TYPE.as()
        .column()
        .caption("Phone type")
        .converter(String.class, new PhoneTypeConverter())

private static final class PhoneTypeConverter implements Converter<PhoneType, String> {
    @Override
    public String toColumn(PhoneType value, Statement statement) {
        return value.name();
    }
    @Override
    public PhoneType fromColumn(String value) {
        return PhoneType.valueOf(value);
    }
}
```
For rich custom value types (own class, comparator, validation) see `world/`
(the `Location` type).

## Validation

- Column-level basics are declarative: `.nullable(false)`, `.maximumLength(n)`,
  `.range(min, max)` (also `.minimum(n)` / `.maximum(n)`), `.fractionDigits(n)`
  for BigDecimal scale.
- Entity-level: implement/extend `EntityValidator` and attach with
  `.validator(...)` — see chinook's `EmailValidator` (regex per column) and
  world's cross-entity validation (a city must lie within its country).

## Custom conditions

For WHERE fragments that can't be expressed with column conditions:

```java
// API:
ConditionType NOT_IN_PLAYLIST = TYPE.conditionType("not_in_playlist");

// impl, on the definition builder:
.condition(Track.NOT_IN_PLAYLIST, (columns, values) ->
        "trackid NOT IN (SELECT trackid FROM chinook.playlisttrack WHERE playlistid IN (" +
                values.stream().map(v -> "?").collect(joining(",")) + "))")

// client:
connection.select(Track.NOT_IN_PLAYLIST.get(Playlist.ID, playlistIds));
```
See chinook's `ChinookImpl` for the working version.

## Functions and procedures (server-side operations)

```java
// API:
FunctionType<EntityConnection, BigDecimal, Collection<Entity>> RAISE_PRICE =
        functionType("chinook.raise_price");

// impl, registered in the DomainModel constructor:
add(Track.RAISE_PRICE, new RaisePriceFunction());

// client:
Collection<Entity> updated = connection.execute(Track.RAISE_PRICE, amount);
```
The implementation receives an `EntityConnection` and runs where that
connection lives (server side for remote/http clients). **There is no
implicit transaction** around function/procedure execution — single
connection calls are atomic as always, but multi-step operations are not
wrapped automatically. An operation *can* manage its own transaction, but the
recommended pattern is that the **caller** is responsible:

```java
// caller-side, from chinook's InvoiceLineEditModel — insert plus a
// totals-updating procedure, atomic together:
transaction(connection, () ->
        updateTotals(connection.insertSelect(invoiceLines), connection));
```

See `ChinookImpl` for implementations: `RaisePrice`, `UpdateTotals`,
`CreateRandomPlaylist`.

## Testing

Extend `DomainTest`, one `test(Entity.TYPE)` call per entity — each runs
insert/select/update/delete round-trips against the test database, inside a
rolled-back transaction, with generated values for all attributes. This is
the cheapest verification that definitions match the schema — run it before
any model or UI work.

```java
public final class PetclinicTest extends DomainTest {
    public PetclinicTest() {
        super(new Petclinic());
    }
    @Test
    void pet() {
        test(Pet.TYPE);
    }
}
```

Required system properties (set in the gradle test task): `codion.db.url`,
`codion.db.initScripts`, `codion.test.user` — see `references/project.md`.
For entities `DomainTest` can't round-trip automatically (unusual defaults,
DB-generated data), pass a custom `EntityFactory` — see chinook's
`ChinookTest`.

**The DECIMAL(p,s) / CHECK-constraint trap — the likeliest silent test
failure on schema-driven work.** `DomainTest`'s default factory generates
random numbers in ±10,000 and scales BigDecimals to the column's
`fractionDigits` (default 10). A `DECIMAL(5,2)` or `DECIMAL(9,6)` column, or
a `CHECK (x BETWEEN 1 AND 5)`, will overflow/violate on random values unless
the definition constrains them. Always mirror the schema onto the definition:
`.fractionDigits(s)` on every DECIMAL(p,s), `.range(min, max)` (or
`.minimum`/`.maximum`) matching CHECK constraints and tight precisions —
e.g. latitude `DECIMAL(9,6)` → `.fractionDigits(6).range(-90, 90)`. For
CHECK IN (...) string columns, `.items(...)` makes the factory pick from the
valid set (see "Columns with a fixed set of valid values" above).

## Registration

The domain implementation is discovered via `ServiceLoader`:

- JPMS: `provides is.codion.framework.domain.Domain with my.app.domain.MyDomain;`
- Classpath: `META-INF/services/is.codion.framework.domain.Domain` containing
  the implementation class name

Without this, connection providers and the server cannot find the domain by
its `DomainType`. See `references/project.md`.

ServiceLoader is not the only way in: for quick-and-dirty or local-JDBC-only
apps you can instantiate the domain and inject it directly:

```java
LocalEntityConnectionProvider connectionProvider =
        LocalEntityConnectionProvider.builder()
                .domain(new Petclinic())
                .user(User.parse("scott:tiger"))
                .build();
```
