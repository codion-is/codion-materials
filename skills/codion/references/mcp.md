# Verifying a Running Application over MCP

Verified against Codion 0.18.86. The rest of this skill gets you to "it compiles
and the DomainTest is green". This file is how you get to "I started it, used it
and watched it work": the `codion-tools-swing-mcp` module exposes a running Swing
application over MCP, so you can type into fields, press keys and read the model
state behind the focused component yourself, instead of asking the user what
happened. Connecting before an application runs, and `focus_state`, need 0.18.86
or later.

Use it when the tools are in your tool list: `type_text`, `key`, `interactions`,
`clear_field`, `model_state`, `focus_state`, `app_screenshot`,
`active_window_screenshot`, `app_window_bounds`, `focus_window`. If there is no
`codion` MCP server, the machine setup below is the **user's** job — ask them to
do it once, do not try to work around it.

## Machine setup — once, by the user

1. Build the bridge from the framework source in the materials root:
   ```
   cd codion && ./gradlew :codion-tools-swing-mcp:installDist
   ```
   It lands in
   `codion/tools/swing/mcp/build/install/codion-tools-swing-mcp/bin/codion-tools-swing-mcp`.
2. Register it, giving the port as the argument:
   ```
   claude mcp add codion -- <that path> 8080
   ```
   Claude Desktop instead takes
   `{"mcpServers": {"codion": {"command": "<that path>", "args": ["8080"]}}}`.
3. Reconnect the client once (`/mcp` → codion → reconnect, or restart it).

That registration is permanent. The bridge holds no state and answers
`initialize` and `tools/list` itself while nothing is listening on the port, so
**no application needs to be running when the client connects**, and you may
stop, rebuild and restart the application as often as you like without
reconnecting. Only a *new tool added to the server itself* needs a reconnect.

## Enabling the server in an application

The server is opt-in per application, off by default, and belongs in
development builds only — it is an unauthenticated HTTP server on port 8080
that can drive the whole UI. Never leave it enabled in something you ship.

```kotlin
// build.gradle.kts, alongside the other Codion dependencies
implementation("is.codion:codion-tools-swing-mcp:0.18.86")
```
```java
// module-info.java
requires is.codion.tools.swing.mcp;
```
```java
// in the application panel
private final State mcpServer = SwingMcpServer.builder()
        .component(this)//any component, the server drives its window
        .start(true)//start right away; omit while a menu toggle is enough
        .build();
```

`build()` returns a `State` controlling the server, so bind it to a toggle
control and the user can switch it on when they want you to have a look:

```java
Control.builder()
        .toggle(mcpServer)
        .caption("MCP Server")
```

`ChinookAppPanel` does exactly this — copy it from there. Port:
`codion.tools.mcp.port` (8080 by default).

## Starting the application without a human

A login dialog blocks everything, so supply the credentials instead of typing
them. `codion.client.user` (`user:password`) skips the dialog entirely:

```kotlin
// in the run task - note that setting systemProperties REPLACES the map, so a
// -D on the gradle command line never reaches the forked JVM
systemProperties = mapOf(
        "codion.client.connectionType" to "local",
        //...
        "codion.client.user" to "scott:tiger"
)
```

Launching the main class yourself takes it on the command line
(`java -Dcodion.client.user=scott:tiger ...`), the `CODION_CLIENT_USER`
environment variable does the same, and `EntityApplication.user(User)` is the
in-code equivalent. Development only — credentials in system properties are
visible in process listings.

Start the application in the background, then poll
`http://localhost:8080/mcp/status` until it answers before sending input.

## The loop: act, read the verdict, assert the state

The point of these tools is that you do **not** screenshot after every
keystroke:

1. **Act.** For a known sequence use `interactions` — one call fills a whole
   form. Use `key`/`type_text` for single or adaptive steps.
2. **Read the verdict.** Every input returns where it landed:
   `CONSUMED` (a component handled it), `FELL_THROUGH` (observed, nothing
   consumed it — usually the wrong focus) or `MISSED` (it did not go through),
   plus the receiving `component` named by its attribute
   (`NumberField[employees.department.department_no]`) and the `action` it
   resolved to. That tells you focus is where you think it is without looking.
   For a focus-transfer key (ENTER, TAB) the component named is the one being
   *left*; the destination shows up in the next verdict.
3. **Assert with `model_state`,** not pixels: per-attribute
   `value/valid/modified/message` plus entity `exists/modified/valid` in an edit
   panel, `rowCount`/`selectionCount`/`selected` in a table, the operator and
   operands in a condition field. After an insert, the form resetting to empty
   *is* the success signal.
4. **Screenshot only** when a verdict or state surprises you, or when the check
   is genuinely visual (layout, icons, rendering). `active_window_screenshot`
   for dialogs.

Anything unexpected — a surprising component name, a `FELL_THROUGH`, a
`MISSED` — is the cue to look, and that is when a screenshot earns its cost.

## Asynchronous work needs `wait` steps

Input delivery is deterministic but the application's response is not: table
refreshes and master-detail selection run background queries, combo boxes
filter, calendar popups hand focus back asynchronously. A fast batch outruns
them. Put `{wait: ms}` steps after the async points — an insert (`alt A`), panel
navigation (`ctrl alt DOWN`/`UP`), a combo selection, a closing calendar. When a
batch fails, `failedAt` names the exact step that needed the settle.

## When keys go nowhere

Repeated `MISSED`, or TAB doing nothing, means the window has no focus owner.
`focus_state` says so without stealing the focus: the focus owner and focused
window, and per window the owner it remembers plus the component its focus
traversal policy would fall back to — a fallback that is not showing (a
component on a hidden tab) leaves the window with no focus owner at all.
`focusOwner` is null whenever another application is in front, so call
`focus_window` first for a live reading.

## Limits

Swing only, one application at a time, fixed port, no authentication, local
development only — useless in CI, and not something to leave switched on.

## Full details

`codion/tools/swing/mcp/CLAUDE.md` in the materials root documents every tool,
its exact response shape and the module's internals. Read it when this summary
is not enough.
