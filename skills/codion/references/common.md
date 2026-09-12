# Value / State / Event — the Reactive Core

Examples lifted from the compiled manual. Source: `codion/common/reactive/`.
This substrate is everywhere — models expose it, UI builders bind to it. It is
synchronous: listeners run on the thread that mutates; anything linked to a
Swing component must be mutated on the EDT.

## Event

```java
Event<String> event = Event.event();

Observer<String> observer = event.observer();   // can listen, cannot trigger

observer.addListener(() -> System.out.println("occurred"));   // Runnable
observer.addConsumer(data -> System.out.println(data));       // Consumer<T>

event.run();            // trigger without data
event.accept("info");   // trigger with data (both kinds of listeners fire)
```
Expose `Observer<T>` from your classes, keep the `Event` private.

## Value

```java
Value<Integer> value = Value.nullable(2);       // nullable, initial 2
Value<Integer> nonNull = Value.nonNull(0);      // null translates to 0

value.set(4);
value.get();
value.is(4);                                    // equality test
value.update(v -> v + 1);                       // transform in place
value.addConsumer(System.out::println);

// builder for the full option set:
Value<Integer> built = Value.builder()
        .nonNull(0)
        .value(42)                              // initial
        .consumer(v -> doSomething(v))          // initial listener
        .build();
```

**Linking** — bidirectional synchronization; the original's value propagates
on link. This is how the framework binds components to values:

```java
linked.link(value);
```

**Notification strategies:** by default listeners fire only on actual change
(`Notify.CHANGED` — setting an equal value is a no-op). `Notify.SET` (via
`Value.builder()...notify(SET)`) fires on every set. Remember entity equality
is PK-based — a PK-equal-but-different instance does NOT fire under CHANGED.

**Conditional listeners:**
```java
value.when(1).addListener(() -> System.out.println("one"));
value.when(Objects::isNull).addListener(...);
value.when(v -> v > 10).addConsumer(...);
```

## State

An observable boolean; wraps a `Value<Boolean>`, never null (null → false).

```java
State state = State.state();          // false initially; State.state(true) also
ObservableState observable = state.observable();  // read-only view
ObservableState not = state.not();                // inverted view

state.set(true);
state.is();                           // current value
```

**Composition:**
```java
ObservableState saveEnabled = State.and(
        State.or(insertEnabled, updateEnabled),
        State.or(recordNew, recordModified));
```

**Binding to UI** — never call `setEnabled` manually:
```java
Utilities.enabled(saveEnabled, saveButton);   // JComponent or Action

Control.builder()
        .command(this::save)
        .enabled(saveEnabled)                 // controls take it directly
        .build();
```
Component builders (`Components.*`, `create().*` in edit panels) accept
`.enabled(observableState)` too.

**Radio-button semantics:** `State.group(one, two, three)` — at most one
active.

## Weak listeners

Every observer supports `addWeakListener`/`addWeakConsumer`. A short-lived
component observing a long-lived model must use weak listeners (or remove its
listeners on dispose) — otherwise the model keeps it reachable forever. The
caller must hold a strong reference to the listener for as long as it should
stay active.

## ProgressWorker

Background work with EDT-safe result handling (in `codion-common-model`;
`Dialogs.progressWorker()` is the dialog-wrapped UI form — see
`references/ui.md`):

```java
ProgressWorker.builder()
        .task(this::slowQuery)          // background thread
        .onResult(this::showResult)     // EDT
        .onException(this::handleError) // EDT
        .execute();
```
Variants support progress reporting and publishing intermediate results —
see the manual's ProgressWorker chapter for the full progression.
