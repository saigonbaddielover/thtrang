# Construction Gates

## Contents

- Build order
- Node and port plan
- Corridor and label plan
- Incremental render loop
- Repair transaction
- Page-edge failures

## Build order

Do not author every edge of a dense diagram before the first rendered audit. Build one page through these blocking stages:

1. containers and lanes;
2. nodes with final labels and intended sizes;
3. semantic backbone routes;
4. boundary and cross-lane routes;
5. store, archive, fan-in, and fan-out routes;
6. return routes;
7. edge labels;
8. final composition.

Render and audit after every stage that adds routes. Do not advance while the current stage has an `ERROR`.

## Node and port plan

Before writing an edge, record:

```text
edge | source | source side | source port | first shaft | corridor | final shaft | target port | target side | label zone
```

Use cardinal-center ports for the first render of ellipses, rhombi, documents, cylinders, archives, and custom stencils. Use an off-center irregular-shape port only when obstacle geometry requires it; give it an explicit normal shaft and verify its actual rendered contact before adding another incident route.

Keep the first bend and final bend outside the source and target outline by at least `clearance.endpointStub`. A waypoint inside a shape bounding box or within the endpoint-stub distance of an irregular outline is not a usable shaft plan.

Reserve distinct physical ports for independent fan-in and fan-out edges. Port uniqueness in XML is insufficient when the rendered arrow tips or final shafts overlap.

## Corridor and label plan

Assign every long segment to a named horizontal or vertical corridor. Record its coordinate and span. Before writing XML, compare occupied spans for:

- strict crossing without a semantic junction;
- touching or T-junction ambiguity;
- shared or near-stacked paths;
- node, divider, header, and page-edge clearance;
- opposing flows that would mask direction.

Keep dense cross-lane routes in separate corridors. Do not repair a crossing by moving it into another occupied corridor.

Reserve an explicit label rectangle on a selected owner segment. The rectangle must clear all nodes, unrelated edges, bends, arrowheads, dividers, and page bounds. Add labels only after route geometry passes; then rerender and run the rendered-label gate.

## Incremental render loop

For each route stage:

1. sync canonical XML to the editable wrapper;
2. preview through MCP;
3. export page-aware SVG and PNG;
4. run `validate_drawio.ps1 -ValidationMode Audit`;
5. inspect the full page and every problem crop;
6. keep the stage only when it introduces no new error.

Treat the first full-graph render as a process failure for a dense page. A page with more than one routing region must be built and audited region by region.

## Repair transaction

Freeze the current canonical XML, rendered assets, and validation report before a repair. Change one connected incident region only: one node and its incident edges, one crossing pair, one fan-in/fan-out group, or one label corridor.

After rerendering, run:

```powershell
pwsh -NoProfile -File scripts/compare_drawio_reports.ps1 -BeforeReportPath before.json -AfterReportPath after.json
```

Accept the repair only when the command returns zero: at least one tracked error or warning disappeared and no new issue fingerprint or multiplicity appeared. Otherwise restore the frozen canonical XML and re-plan the region. `-ErrorsOnly` narrows a diagnostic comparison but is not valid for keeping a final repair. `-AllowNoImprovement` is only for a deliberate visual-only change whose unchanged automated result is separately inspected.

If the same repair class fails twice, stop coordinate patching. Move or resize the affected nodes, reallocate corridors, and rebuild that region from its port plan.

## Page-edge failures

Reserve at least `clearance.pageConnector` between the page edge and every connector, arrowhead, and edge-label background. Node containment alone does not prove rendered page containment.

When page-aware export reports a viewBox larger than the canonical page tolerance, first inspect page-edge nodes, routes, and labels. Do not bypass the exporter or blame the page sentinel until a minimal canonical page reproduces the mismatch with the same renderer.
