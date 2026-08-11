# Floorplan

Use `profiles/floorplan.json`. [ISO 4157-1:1998](https://www.iso.org/standard/26189.html) supports building and space designation but does not define every plan symbol. Require the applicable building-symbol convention, dimensions, scale, units, and room identifiers.

Preserve wall and opening relationships, fixture containment, circulation clearance, z-order, and measurement labels. Never run topology auto-layout.

## Semantic contract

Set `diagram.context.scaleRatio` as explicit `drawingUnits`, `modelUnits`, and `modelUnit` values. Record authoritative `dimensions`, `wallOpenings`, and `circulationClearances`; every wall opening names its wall, handedness, swing, width, unit, and source. ISO 4157 designation plus a live door stencil is insufficient to approve a building-symbol convention.

## Live MCP discovery

Query `floorplan door` returned these styles from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11:

| Title | Size | Exact style |
| --- | --- | --- |
| `Door` left-hand variant | `80×85` | `verticalLabelPosition=bottom;html=1;verticalAlign=top;align=center;shape=mxgraph.floorplan.doorLeft;aspect=fixed;` |
| `Door` right-hand variant | `80×85` | `verticalLabelPosition=bottom;html=1;verticalAlign=top;align=center;shape=mxgraph.floorplan.doorRight;aspect=fixed;` |

These prove renderer availability only. Confirm handedness, swing, dimensions, wall contact, and the selected building-symbol convention.

Copy the required door handedness from `assets/templates/live-mcp-style-palette.xml` into `spatial-landscape.xml` after confirming geometry. Automated checks cannot prove building-code compliance or measurement truth without authoritative inputs.
