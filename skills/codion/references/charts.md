# Charts (JFreeChart)

Charts are plain JFreeChart (`org.jfree:jfreechart`, 1.5.x — see world's
version catalog); Codion adds no chart API of its own. What the demos establish
is the *architecture*: where datasets live, how they stay current, and how
chart panels respect the look and feel. Canonical examples: world
(`CityTableModel`/`ContinentModel` + `ChartPanels`/`ContinentPanel`) and
chinook (`AnalyticsModel` + `AnalyticsPanel`).

## The architecture: dataset in the model, chart in the panel

JFreeChart datasets (`DefaultPieDataset`, `DefaultCategoryDataset`, ...) are
**live** — mutating one updates any chart displaying it, no listener plumbing
needed. So the split is:

- **Model layer** owns the dataset and keeps it current (it's model state,
  like any other observable). Exposes it read-only
  (`public PieDataset<String> chartDataset()`).
- **UI layer** wraps it: `ChartFactory.createPieChart/createBarChart/
  createLineChart(...)` → `new ChartPanel(chart)` → mount like any component
  (a tab, a split-pane side, a base-panel south — see world's
  `ContinentPanel`, chinook's `AnalyticsPanel`).

## Model side — two ways datasets stay current

**Reactive, mirroring the table (world):** refresh from table-model events —
the chart always shows what the table shows:

```java
public final class CityTableModel extends SwingEntityTableModel {

    private final DefaultPieDataset<String> chartDataset = new DefaultPieDataset<>();

    CityTableModel(EntityConnection connection) {
        super(new CityEditModel(connection));
        items().included().addConsumer(this::refreshChartDataset);   // visible rows
    }

    public PieDataset<String> chartDataset() {
        return chartDataset;
    }

    private void refreshChartDataset(Collection<Entity> cities) {
        chartDataset.clear();
        cities.forEach(city -> chartDataset.setValue(city.get(City.NAME), city.get(City.POPULATION)));
    }
}
```
Same pattern at entity-model level with multiple datasets: world's
`ContinentModel` (`tableModel().items().included().addConsumer(this::refreshChartDatasets)`).
Other triggers work too: `selection().items()` for selection-driven charts.

**Query-driven (chinook):** a plain model class (no entity model needed)
holding datasets refreshed by explicit queries — for aggregates the table
doesn't carry:

```java
public final class AnalyticsModel {

    private final EntityConnection connection;

    public final class SalesComparison {
        private final DefaultCategoryDataset dataset = new DefaultCategoryDataset();

        private void refresh() {
            List<Entity> invoices = connection.select(all(Invoice.TYPE));
            // aggregate into dataset ...
        }
    }
}
```
Chinook's `TopArtists` variant refreshes on a genre combo selection
(`EntityComboBoxModel.builder()...onItemSelected(this::refresh)`) — chart
filters as model logic, not UI logic.

**Threading:** table-model consumers fire on the EDT — mutate datasets there
directly. For slow query-driven refreshes, fetch off the EDT
(`ProgressWorker`, see `references/common.md`) and update the dataset in
`onResult`. **The ambiguous middle case — a query-driven refresh triggered
FROM a selection event — is still a query on the EDT**: route it through
ProgressWorker too. (Chinook's own analytics refresh models the lax
version; it's acceptable at demo data volumes, not a pattern to copy into
apps with real query costs. If you follow the demo anyway, say so in your
notes.) Also gate the refresh on the chart actually being visible —
refreshing a hidden chart on every selection is pure waste.

## UI side — the look-and-feel chart panel

Raw `ChartPanel` ignores the Swing look and feel — illegible under dark
FlatLaf themes. Both demos solve it identically: a small `ChartPanel`
subclass that repaints chart colors from `UIManager` whenever the panel
background changes (i.e. on LaF switch). **Copy it, don't reinvent it**:
world's `ChartPanels.java` (pie + bar, complete helper class) or chinook's
`AnalyticsPanel.LookAndFeelChartPanel` (bar + line, with gridline paint).
The shape:

```java
private static final class LookAndFeelChartPanel extends ChartPanel {

    private LookAndFeelChartPanel(JFreeChart chart) {
        super(chart);
        addPropertyChangeListener(new BackgroundListener());  // fires on LaF change
        updateColors();
    }

    private void updateColors() {
        Color background = getBackground();
        Color foreground = UIManager.getColor("TextField.foreground");
        // apply to chart background/title/plot/axes/legend —
        // see ChartPanels.java (world) for the per-plot-type details
    }
}
```

Mounting: chinook's `AnalyticsPanel` composes charts with `Components`
builders (`tabbedPane().tab(...)`, `borderLayoutPanel()`); world's
`ContinentPanel` lays four chart panels into a grid beside the tables.

**Adding a chart to an EXISTING master-detail panel** (the maintenance
case — the master's layout is already occupied by detail panels): two
shapes that don't fight the existing layout, both selection-driven:
- a tab inside a custom `EntityTablePanel` subclass, beside the table
  (config `.table(...)` composition or a tabbed south component), or
- a control (popup menu / toolbar, `setupControls()` — see
  `references/ui.md`) opening the chart in a **modeless** dialog
  (`Dialogs.builder().modal(false)`), refreshing only while showing.
Pick whichever matches how the app already mounts auxiliary views.

## Dependencies

```toml
jfreechart = { module = "org.jfree:jfreechart", version.ref = "jfreechart" }  # 1.5.6
```
Client module only (`implementation(libs.jfreechart)`); JPMS:
`requires org.jfree.jfreechart;` (automatic module name — from world-client's
module-info).
