# EntityConnection Recipes

Source of truth:
`codion/framework/db-core/src/main/java/is/codion/framework/db/EntityConnection.java`.
The same interface serves local JDBC, RMI and HTTP connections.

Getting a connection: models hand it to you (`tableModel().connection()`,
`editModel().connection()`) — one self-managing instance shared by the whole
application, safe to hold on to and use for its lifetime: it validates the
underlying connection before each operation and re-establishes it when it
has gone bad. Standalone (tests, scripts, headless):

```java
EntityConnection connection = EntityConnection.builder()  // type via codion.client.connectionType
        .domain(Petclinic.DOMAIN)
        .user(User.parse("scott:tiger"))
        .build();                                         // connects eagerly - fails fast
```

or a transport-specific builder: `LocalEntityConnection.builder()` (takes
`.domain(new PetclinicImpl())` directly, no ServiceLoader needed),
`RemoteEntityConnection.builder()`, `HttpEntityConnection.builder()`.
`close()` is terminal — subsequent operations throw. It is a connection
*going bad* that heals, not one you closed.

## Conditions

Conditions are built from the domain's column/FK constants:

```java
Artist.NAME.equalTo("Metallica")
Artist.NAME.like("Black%")               // also likeIgnoreCase, notLike...
Track.RATING.between(8, 10)              // greaterThan, lessThanOrEqualTo...
Track.GENRE_FK.in(genres)                // FK conditions take entities
Album.COVER.isNotNull()
and(Track.RATING.greaterThanOrEqualTo(8),
    Track.GENRE_FK.equalTo(metal))       // and(...)/or(...) combine
all(Genre.TYPE)                          // no WHERE — all rows
```
`and`/`or`/`all` are static methods on
`is.codion.framework.domain.entity.condition.Condition`.

## Selecting

```java
List<Entity> artists = connection.select(Artist.NAME.like("A%"));
Entity artist = connection.selectSingle(Artist.ID.equalTo(42L));

// full Select builder — static import EntityConnection.Select.where/all:
List<Entity> tracks = connection.select(
        where(Track.GENRE_FK.in(genres))
                .orderBy(descending(Track.RATING))
                .limit(10)
                .build());
```
Select builder options: `.orderBy(...)`, `.limit(n)`, `.offset(n)`,
`.forUpdate()`, `.attributes(...)` (fetch only these columns),
`.include(...)`/`.exclude(...)`, `.referenceDepth(n)` (also per-FK),
`.having(condition)`, `.timeout(seconds)`.

Values from result sets:
```java
List<Long> ids = Entity.values(Invoice.ID, invoices);      // one column
Entity.primaryKeys(entities)                                // keys
```
Single-column selects: `connection.select(Artist.NAME.equalTo("x"))` returns
entities; for just values use `Entity.values(...)` on the result.

## Inserting

```java
Entity artist = connection.entities().entity(Artist.TYPE)
        .with(Artist.NAME, "New Artist")
        .build();

Entity.Key key = connection.insert(artist);          // just the key
Entity inserted = connection.insertSelect(artist);   // re-selected entity
// collections: insert(Collection), insertSelect(Collection)
```

## Updating

```java
// modify an instance, then:
album.set(Album.TITLE, "New Title");
connection.update(album);                    // or updateSelect(album)

// bulk update via builder — static import EntityConnection.Update.where/all:
connection.update(
        where(Track.GENRE_FK.equalTo(metal))
                .set(Track.RATING, 10)
                .build());
```
Updating an unmodified entity is an error; updates verify against the
original values (optimistic locking) by default.

## Deleting

```java
connection.delete(album.primaryKey());
connection.delete(Entity.primaryKeys(albums));
connection.delete(Track.GENRE_FK.equalTo(genre));    // by condition
```

## Counting

```java
int count = connection.count(Count.where(Track.RATING.equalTo(10)));
```

## Transactions

Connections are NOT in auto-transaction mode; single calls are atomic, for
multi-step atomicity wrap explicitly:

```java
EntityConnection.transaction(connection, () -> {
    connection.insert(album);
    connection.insert(tracks);
});
// or with a result:
Entity result = EntityConnection.transaction(connection, () ->
        connection.insertSelect(entity));
```

## Functions, procedures, reports

```java
Collection<Entity> updated = connection.execute(Track.RAISE_PRICE, amount);   // function
connection.execute(Invoice.UPDATE_TOTALS, invoiceIds);                        // procedure
byte[] pdf = connection.report(Invoice.REPORT, reportParameters);             // report
```

## Iterating large result sets

`LocalEntityConnection` supports result iteration without materializing the
full list — grep `iterator` in
`codion/framework/db-local/.../LocalEntityConnection.java`. For batch loads,
`EntityConnection.batchInsert(...)` / `batchCopy(...)`.
