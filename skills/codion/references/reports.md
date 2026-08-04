# Reports (JasperReports)

Verified against Codion 0.18.82. Plugin module: `codion-plugin-jasperreports`
(`is.codion.plugin.jasperreports`). Canonical examples: world (client-side
entity-fed report) and chinook (domain-registered JDBC reports).

## The decision rule: who supplies the data?

There are two report patterns, and the choice is NOT a matter of taste — it
follows from where the report's data comes from:

1. **The client feeds it entities** (selected rows, loaded table data) →
   fill it **client-side** with a `JasperReportsDataSource` (world pattern).
   Deployment-agnostic by construction: the fill consumes entities the
   client already has, and any *extra* data the report needs is fetched
   through `EntityConnection` like any other query — so it works identically
   under local, RMI and HTTP connections.
2. **The report queries for itself** (a SQL `queryString` inside the jrxml,
   filled over JDBC) → the fill must run next to a JDBC connection.
   **Register it in the domain** and fill via
   `connection.report(ReportType, params)` (chinook pattern) — the fill then
   runs wherever the JDBC connection lives (in-process for a local
   connection, on the server for RMI/HTTP), so it too works in every
   deployment.

**The trap:** filling a JDBC/SQL-based report directly in client code works
in development (local connection) and silently breaks the day the app is
deployed against a server — client-side there is no JDBC. If the report
contains SQL, register it in the domain. If you feed it entities, you never
need to.

## Pattern 1 — entity-fed, filled client-side (world)

A `JasperReportsDataSource<Entity>` iterates entities; a
`BiFunction<Entity, JRField, Object>` maps report fields to attribute values:

```java
public final class CountryReportDataSource extends JasperReportsDataSource<Entity> {

    CountryReportDataSource(Iterator<Entity> countryIterator, EntityConnection connection, ...) {
        super(countryIterator, new CountryValueProvider(), ...);
        this.connection = connection;
    }

    private static final class CountryValueProvider implements BiFunction<Entity, JRField, Object> {
        @Override
        public Object apply(Entity country, JRField field) {
            return switch (field.getName()) {
                case "name" -> country.get(Country.NAME);
                case "continent" -> country.get(Country.CONTINENT);
                ...
            };
        }
    }
}

// filling, e.g. in a table model (world's CountryTableModel):
JasperPrint fillCountryReport(...) {
    CountryReportDataSource dataSource = new CountryReportDataSource(
            selection().items().get().iterator(), connection(), progressReporter);

    return fillReport(classPathReport(CountryTableModel.class, "country_report.jasper"),
            dataSource, reportParameters);
}
```

Statics from `is.codion.plugin.jasperreports.JasperReports`: `fillReport`,
`classPathReport`. Subreports can fetch additional data per row *through the
EntityConnection* (see `CountryReportDataSource.cityDataSource()`) — still
deployment-agnostic. No domain registration involved.

Two facts value providers depend on: FK values resolve one level deep by
default (reference depth 1), so `entity.get(SOME_FK).get(Other.NAME)` works
without extra fetching — deeper graphs need explicit depth or a query. And
for display strings use `entity.toString()` (the domain formatter) or
`entity.formatted(attribute)` — `entity.string(...)` does not exist.

## Pattern 2 — SQL-based, registered in the domain (chinook)

Domain API — a `ReportType<P, R>` constant (P = parameters, R = result):

```java
// import static is.codion.common.db.report.ReportType.reportType;
interface Customer {
    ReportType<Map<String, Object>, byte[]> REPORT = reportType("customer_report");
}
```

Domain impl — register the report, choosing the export format:

```java
// import static is.codion.plugin.jasperreports.JRExport.SERIALIZED;
// import static is.codion.plugin.jasperreports.JasperReports.{classPathReport, export};
add(Customer.REPORT, export(classPathReport(ChinookImpl.class, "customer_report.jasper"), SERIALIZED));
```

Export formats (`JRExport`): `SERIALIZED` — the filled `JasperPrint`,
serialized; for Swing clients that display in a `JRViewer`. `PDF` / `XML` —
rendered bytes; for non-Swing clients (web, Android) or file output.

Client side — fill via the connection, load, display:

```java
// chinook's CustomerTablePanel — a repurposed PRINT control:
private JasperPrint fillCustomerReport() {
    Map<String, Object> reportParameters = new HashMap<>();
    reportParameters.put("CUSTOMER_IDS",
            Entity.values(Customer.ID, tableModel().selection().items().get()));

    return JasperReports.loadPrint(tableModel().connection()
            .report(Customer.REPORT, reportParameters));
}
```

The jrxml's SQL uses the parameters (`$X{IN, customerid, CUSTOMER_IDS}`); the
fill runs server-side under RMI/HTTP.

## Viewing — the standard recipe

Fill off the EDT, show in a `JRViewer` (see `references/ui.md` for
`Dialogs.progressWorker()` and the `control(PRINT).set(...)` idiom):

```java
Dialogs.progressWorker()
        .task(this::fillCustomerReport)
        .owner(this)
        .title("Customer report")
        .onResult(this::viewReport)
        .execute();

private void viewReport(JasperPrint report) {
    Dialogs.builder()
            .component(new JRViewer(report))
            .owner(this)
            .modal(false)
            .size(new Dimension(800, 600))
            .show();
}
```

## Build machinery — jrxml → .jasper

Reports live as `.jrxml` sources under `src/main/reports/<package dirs>/` and
are compiled to `.jasper` at build time by the
`io.github.f-cramer.jasperreports` gradle plugin, with the output added to
resources so `classPathReport(SomeClass.class, "name.jasper")` finds them
next to the class. From chinook-domain/build.gradle.kts:

```kotlin
plugins {
    id("io.github.f-cramer.jasperreports") version "0.0.4"
}

dependencies {
    jasperreportsClasspath(libs.jasperreports.jdt) {
        exclude(group = "net.sf.jasperreports")
    }
}

jasperreports {
    classpath.from(project.sourceSets.main.get().compileClasspath)
}

sourceSets.main {
    resources.srcDir(tasks.compileAllReports)
}
```

Chinook and world both use this via convention plugins (`buildSrc`) — copy
the shape, not necessarily the indirection. Write jrxml by adapting the
demos' report sources (`chinook-domain/src/main/reports/`,
`world-client/src/main/reports/`) — do not author jrxml from memory.

## Deployment gotchas

- **RMI + `SERIALIZED`**: the serialized `JasperPrint` graph contains types
  the server's serialization filter must allow — see chinook's
  `serialization-filter-patterns.txt` (`java.awt.Color`,
  `is.codion.plugin.jasperreports.*`, `net.sf.jasperreports.**`).
- **HTTP/JSON clients**: the client's `EntityObjectMapper` must know the
  report's return type before requesting —
  `objectMapper.returnType(Customer.REPORT).set(new TypeReference<>() {})`
  in a custom `EntityObjectMapperFactory` (see chinook's
  `ChinookObjectMapperFactory`, and the manual's "HTTP & JSON clients"
  chapter).
- Dependencies: `codion-plugin-jasperreports` plus the JasperReports
  artifacts it pulls; the domain module needs them only when it registers
  reports (pattern 2), the client only when it fills or views. JPMS module
  names (the part that fails resolution if guessed — from world-client's
  module-info): `requires is.codion.plugin.jasperreports;` and
  `net.sf.jasperreports.core` / `.pdf` / `.fonts`.
