# Project Setup Recipes

Verified against Codion 0.18.80. Canonical skeletons: `petclinic/` (single
module — copy this for small apps) and `world/` (multi-module: domain-api /
domain / client / client-local / client-remote / server — copy this when
splitting layers into modules). `chinook/` adds the kitchen sink on the same
structure (REST service, reports, load tests) — reference it per feature, not
as a starting skeleton.

## Gradle — the petclinic skeleton

`gradle/libs.versions.toml`:
```toml
[versions]
codion = "0.18.80"
h2 = "2.3.232"

[libraries]
codion-framework-bom = { module = "is.codion:codion-framework-bom", version.ref = "codion" }
codion-swing-framework-ui = { module = "is.codion:codion-swing-framework-ui" }
codion-framework-db-local = { module = "is.codion:codion-framework-db-local" }
codion-dbms-h2 = { module = "is.codion:codion-dbms-h2" }
codion-framework-domain-test = { module = "is.codion:codion-framework-domain-test" }
codion-plugin-logback-proxy = { module = "is.codion:codion-plugin-logback-proxy" }
codion-plugin-flatlaf-themes = { module = "is.codion:codion-plugin-flatlaf-themes" }
h2 = { module = "com.h2database:h2", version.ref = "h2" }
```

`build.gradle.kts` (essentials — see petclinic for the full file with
jlink/jpackage/spotless):
```kotlin
plugins {
    id("application")   // petclinic uses org.beryx.jlink, which applies it
}

dependencies {
    implementation(platform(libs.codion.framework.bom))   // versions via BOM
    implementation(libs.codion.swing.framework.ui)        // pulls model+domain+db-core
    implementation(libs.codion.plugin.flatlaf.themes)

    runtimeOnly(libs.codion.framework.db.local)   // local JDBC connection
    runtimeOnly(libs.codion.dbms.h2)              // H2 dialect
    runtimeOnly(libs.h2)                          // H2 driver
    runtimeOnly(libs.codion.plugin.logback.proxy)

    testImplementation(libs.codion.framework.domain.test)
    testImplementation(libs.codion.framework.db.local)
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(26))   // 17+ works
    }
}

testing {
    suites {
        val test by getting(JvmTestSuite::class) {
            useJUnitJupiter()
            targets.all {
                testTask.configure {
                    systemProperty("codion.db.url", "jdbc:h2:mem:h2db")
                    systemProperty("codion.db.initScripts", "classpath:create_schema.sql")
                    systemProperty("codion.test.user", "scott:tiger")
                }
            }
        }
    }
}

application {
    mainModule = "my.app"          // omit if not modular
    mainClass = "my.app.ui.MyAppPanel"
    applicationDefaultJvmArgs = listOf(
        "-Dcodion.client.connectionType=local",
        "-Dcodion.db.url=jdbc:h2:mem:h2db",
        "-Dcodion.db.initScripts=classpath:create_schema.sql"
    )
}
```

Note the layering in dependencies: `implementation` = compile-time API,
`runtimeOnly` = ServiceLoader-discovered implementations (connection type,
database dialect, driver, logging). Swapping local ↔ remote ↔ http is a
runtimeOnly + system-property change, zero code.

## H2 for development

`src/main/resources/create_schema.sql` — DDL plus seed data. The properties
`codion.db.url=jdbc:h2:mem:h2db` and
`codion.db.initScripts=classpath:create_schema.sql` give a fresh in-memory
database per run. The conventional dev/test user is `scott:tiger`, created at
the top of the init script:
```sql
create user if not exists scott password 'tiger';
alter user scott admin true;
```

## JPMS module-info (petclinic)

```java
module is.codion.demos.petclinic {
    requires is.codion.swing.framework.ui;
    requires is.codion.plugin.flatlaf;

    // the framework instantiates models/panels reflectively:
    exports is.codion.demos.petclinic.model
            to is.codion.swing.framework.model, is.codion.swing.framework.ui;
    exports is.codion.demos.petclinic.ui
            to is.codion.swing.framework.ui;

    // domain discovery:
    provides is.codion.framework.domain.Domain
            with is.codion.demos.petclinic.domain.Petclinic;
}
```

Non-modular (classpath) apps register the domain via
`META-INF/services/is.codion.framework.domain.Domain` (one line: the
implementation class name). **Forgetting registration is the classic "domain
model not found" failure.** For quick-and-dirty or local-only apps you can
skip ServiceLoader entirely and inject an instance:
`LocalEntityConnectionProvider.builder().domain(new MyDomain())...` — see the
registration section in `references/domain.md`.

## The domain generator — when a schema exists

The generator reads JDBC metadata and emits complete domain source (plus,
optionally, DTOs, i18n properties and a domain test). Honest cost/benefit:
generation gives you the mechanical layer (types, columns, FKs, PKs), but
much of a good domain is *refinement* the generator can't know — item lists
for CHECK constraints, fractionDigits/range mirroring DECIMAL(p,s),
readOnly audit columns, formatters, orderings, smallDataset hints. Up to
roughly 15 tables, hand-writing with refinement inline is a perfectly
rational choice; beyond that — or when you want the DTO/i18n/test
scaffolding — generate first, then refine. Either way the refinement
checklist above still applies to every column.

**CLI:** `codion/tools/generator/cli` in the materials clone.
Build it once — add your JDBC driver to its `build.gradle.kts` first (the
file contains commented-out lines for H2/PostgreSQL/Oracle/MariaDB — enable
the pair you need; editing and building inside the materials clone is the
intended use, not a mutation to avoid), then:

```bash
cd <materials>/codion
./gradlew :codion-tools-generator-cli:installDist
tools/generator/cli/build/install/codion-tools-generator-cli/bin/codion-tools-generator-cli \
    --url jdbc:h2:mem:h2db \
    --init-scripts path/to/create_schema.sql \
    --user scott:tiger \
    --schema PETCLINIC \
    --package my.app.domain
```

With no `--output-dir` the combined source prints to **stdout** (diagnostics
on stderr) — read it, refine it, place it in your project. For writing files:
`--output-dir src/main/java` plus optionally `--split-api-impl` (separate
api/impl files), `--dtos`, `--i18n --resource-dir ...`,
`--test --test-dir ...`, `--overwrite`. Run `--help` for the full list.
Exit codes: 0 success, 1 failure, 2 usage error.

**UI** (for humans; a Swing app — per-table selection, live preview): see
`chinook/chinook-domain-generator/build.gradle.kts` for the runnable-module
recipe (`codion-tools-generator-ui`, main class
`is.codion.tools.generator.ui.DomainGeneratorPanel`, configured via
`codion.db.url` / `codion.db.initScripts` /
`codion.tools.generator.domainPackage` / `codion.tools.generator.user`).

## i18n

Resource bundles keyed by class name, `_<locale>` suffixed variants:
`Chinook$Artist.properties` / `Chinook$Artist_is_IS.properties` for entity
captions, `MyTablePanel.properties` for panel strings (see chinook).
Precedence: resource-bundle caption **wins over** `.caption()` in code.
Single-locale apps just use `.caption()` (petclinic).

## Connection types (client side)

| `codion.client.connectionType` | runtimeOnly module | notes |
|---|---|---|
| `local` | `codion-framework-db-local` + dbms + driver | embedded JDBC |
| `remote` | `codion-framework-db-rmi` | needs a Codion server |
| `http` | `codion-framework-db-http` | needs a Codion server with HTTP |

Server setup, deployment and packaging: see chinook's `chinook-server` /
`chinook-client-*` modules and the manual's server and deployment chapters.
