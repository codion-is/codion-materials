# Codion Materials — write Codion applications with your LLM

[Codion](https://codion.is) is a full-stack Java rich-client framework:
define a domain model over a SQL database, get a complete Swing CRUD
application. This repository makes Codion **LLM-ready**: a skill that
teaches coding agents to write and maintain idiomatic Codion applications,
plus the grounding materials that make a correct API lookup cheaper than a
guess — the framework source at the current release and five demo
applications, one `grep` away.

Codion has near-zero presence in LLM training data, and what little exists
is stale. With these materials, cold agents build complete, first-try-green,
idiomatic Codion applications from nothing but a database schema — measured,
not hoped: the skill was developed adversarially, by benchmarking fresh
agents against real tasks and folding every failure back into the material.

## Install

```bash
git clone https://github.com/codion-is/codion-materials.git
cd codion-materials
./setup.sh
```

`setup.sh` shallow-clones the Codion framework source at the pinned release
tag and the five demo applications (~55 MB total), and verifies everything
tracks the same release. Re-run it after each Codion release (following a
`git pull` of this repo).

**Claude Code:** make the skill available to every session:
```bash
ln -s "$(pwd)/skills/codion" ~/.claude/skills/codion
```
**Other agent tooling:** point your agent at `skills/codion/SKILL.md` and
instruct it to read that file before writing any Codion code.

No bash? The setup is just git: clone `codion-is/codion` at the release tag
(`--depth 1 --branch v<version>`, see the pin in `setup.sh`) and
`codion-is/{petclinic,world,chinook,llemmy,sdkboy}` into this directory.

## What's here

| Path | What | Use it for |
|------|------|-----------|
| `skills/codion/` | The skill: orientation (SKILL.md) + 11 reference files (domain, connection, model, ui, common, project, reports, charts, mcp, maintenance, antipatterns) | The agent's entry point — everything else is indexed from here. |
| `manual.md` | The full Codion manual, single markdown file, all code examples compiled against the pinned release | The tour: concepts, layering, idiomatic usage. Read sections, don't ingest whole (~100K tokens). |
| `codion/` * | Framework source at the release tag | **Ground truth.** When unsure of any API — a builder method, a signature, a default — grep the source. Never guess. |
| `petclinic/` * | Demo: veterinary clinic (~1.2K LOC, one module) | **The minimal shape.** Basic entities, FKs, decimals, audit columns, edit panels, DomainTest. Start here. |
| `world/` * | Demo: countries/cities (~3.4K LOC) | **The step between petclinic and chinook**: full multi-module split (domain-api/domain/client/server) without the extra features — copy its structure for multi-module apps. Advanced modeling: custom value types, cross-entity validation, cyclic FKs, item lists, charts, client-side reports. |
| `chinook/` * | Demo: music store (full production shape) | The kitchen sink on world's structure: REST service, domain-registered reports, load tests, i18n, packaging (jlink/jpackage), custom components. Open per feature, not for overall shape. |
| `llemmy/` * | Demo: LLM chat (~1.2K LOC) | Full framework with ONE entity; soft delete via EntityPersistence; edit model as reactive app-logic host. |
| `sdkboy/` * | Demo: SDKMAN UI (~1.9K LOC) | The Swing component layer *without* the CRUD framework: Value/State, FilterTable, builders standing alone. |

\* created by `setup.sh`, not part of this repository.

## The demo ladder as an index

The demos form a ladder — sdkboy → llemmy → petclinic → world → chinook —
and double as an index: open the *smallest* demo that answers your question.

- "How do I define an entity / a foreign key?" → `petclinic` domain, then `world` for advanced cases
- "How do I structure edit/table panels?" → `petclinic` UI, then `chinook` for customization
- "How do Value/State/Event work?" → `sdkboy`
- "Where does application logic go?" → `llemmy` (edit model), `chinook` (InvoiceLineEditModel)
- "How do I split an app into modules?" → `world` (domain-api/domain/client/server without the extras)
- "How do I package/deploy/serve?" → `world` for the basic shape, `chinook` for REST/http-client
- "Charts? Reports?" → `world` (both, client-side), `chinook` (domain-registered reports, analytics)
- "Custom components, search conditions?" → `chinook` ui package

## The domain generator

Don't hand-write large domain definitions from an existing schema — generate,
then refine. The generator lives in `codion/tools/generator/`:

- **CLI** (`codion/tools/generator/cli`, Codion 0.18.81+): add your JDBC
  driver to its `build.gradle.kts` (commented-out lines provided per dbms),
  run `./gradlew :codion-tools-generator-cli:installDist`, then invoke the
  launcher in `tools/generator/cli/build/install/.../bin/` with
  `--url --user --schema --package` — combined source to stdout, or files via
  `--output-dir` (plus `--split-api-impl`, `--dtos`, `--i18n`, `--test`).
- **UI tool**: see `chinook/chinook-domain-generator/build.gradle.kts` for the
  complete recipe — an `application` module with `codion-tools-generator-ui` +
  a dbms driver on the runtime path, configured entirely via system properties
  (`codion.db.url`, `codion.db.initScripts`, `codion.tools.generator.domainPackage`,
  `codion.tools.generator.user`).
- **Programmatic**: `codion/tools/generator/domain/` (`DomainSource`) and
  `codion/tools/generator/model/` (`DomainGeneratorModel`) — the
  source-generation core both wrap.

## Versioning

This repository is tagged in lockstep with Codion releases; `setup.sh`
carries the pin, `manual.md` is generated from that release's documentation
build, and the demo repositories always track the latest release. Everything
you read here is one coherent snapshot — no version skew between skill,
manual, source and demos.

## Maintaining manual.md (repo maintainers)

`manual.md` is the codion documentation build's `llms-full.txt` artifact
(the `documentation:generateLlmsTxt` task — pandoc conversion, cleanup and
absolute links, also deployed as https://codion.is/llms-full.txt). On each
release:
```bash
# in the codion repo:
./gradlew documentation:generateLlmsTxt
cp documentation/build/llms/llms-full.txt <codion-materials>/manual.md
# then bump CODION_VERSION in setup.sh, run it, commit, tag
```
