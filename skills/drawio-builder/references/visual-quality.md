# Visual Quality Standard

## Contents

- Typography
- Shape-safe areas
- Connectors and labels
- Composition
- Color and print
- Inspection

## Typography

Use the active quality profile. Keep body, edge, lane, and title text at or above their minimums. Prefer reflow, shape resize, lane resize, or page relayout over smaller type.

Measure rendered ink, not XML label length. Inspect SVG text, embedded label images, and HTML-rendered labels. Confirm that the selected font exists and covers every glyph. Treat fallback or missing glyphs as an error when it changes layout or meaning.

Keep hierarchy consistent: title, lane header, node label, metadata, and edge label must remain visually distinct without excessive font variation.

## Shape-safe areas

- Rectangle and rounded process: use the padded rendered outline.
- Document and multiple documents: clear every curved bottom copy.
- Ellipse: use the central elliptical region, not the bounding box corners.
- Decision/rhombus: keep ink inside the central diamond region.
- Note: clear the folded corner.
- Cylinder and data store: clear curved caps and internal store lines.
- Archive triangle: keep ink below the divider and clear both slopes, bottom, and apex.
- Swimlane: keep header text inside `startSize`; keep children inside the client area.
- Unknown stencil: require outline-aware inspection; a bounding-box pass is only a warning-level partial check.

Resize symmetrically around an intentional connector port when possible. After any resize, recompute physical anchor fractions and audit incident routes, labels, dividers, and neighboring shapes.

## Connectors and labels

Inspect the actual arrow polygon and target contact point. A correct source/target pair can still render a tangent, floating, buried, or wrong-side arrow.

Use orthogonal routes for process, document, DFD, architecture, network, and most engineering flows unless the notation requires another line family. Keep meaningful endpoint shafts visible. Remove non-semantic micro-segments.

Place edge labels in clear whitespace. Keep every label clear of shapes, unrelated routes, bends, arrowheads, labels, lane headers, and dividers. Require a measurable association advantage to its own edge.

Keep the rendered label center within `clearance.edgeLabelOwnerMaximum` of its owner polyline. A label can be closer to its owner than every unrelated edge and still be visually detached when the absolute gap is too large.

## Composition

Align repeated nodes and normalize repeated sizes within the quality-profile tolerance. Use a stable spacing grid and preserve deliberate whitespace around dense nodes, fan-in/fan-out, and return flows.

Maintain one dominant reading direction. Use secondary corridors without weakening the primary narrative. Avoid unexplained voids, edge walls, icon walls, and uniform density that erases hierarchy.

Treat composition metrics as warnings that require visual disposition. Do not force an aesthetically poor layout merely to satisfy alignment arithmetic.

## Color and print

Use a restrained palette with semantic roles rather than per-node decoration. Keep text/background contrast at or above the quality profile. Ensure line classes remain distinguishable in grayscale and at A4 print scale.

Do not use color as the only carrier of direction, status, cardinality, or ownership. Preserve notation through shape, line type, label, or legend.

## Inspection

Inspect page-aware SVG and high-resolution PNG. Review the full page, every automatically generated problem crop, and every dense routing region at full resolution.

Confirm:

- notation and semantic reading order;
- text fit, glyphs, wrapping, padding, and hierarchy;
- actual outline, port, arrow, corridor, label, lane, and page clearances;
- fan-in/fan-out separation and return-flow logic;
- alignment, balance, density, whitespace, contrast, and print readability;
- artifact revision consistency.

Automated zero-issue output is necessary but insufficient. If full-resolution inspection cannot run, mark the visual gate `SKIPPED` and keep the page `NOT APPROVED`.
