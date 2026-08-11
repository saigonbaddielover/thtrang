# Wireframe

Use `profiles/wireframe.json`. Declare viewport, fidelity, design system, repeated-component contract, and interaction legend. [WCAG 2.2](https://www.w3.org/TR/WCAG22/) informs accessibility review but is not a wireframe notation standard.

Keep repeated controls dimensionally consistent. Validate containment, alignment, spacing, labels, contrast risks, z-order, and navigation arrows. Never run topology auto-layout.

## Semantic contract

Set `diagram.context.viewport` with pixel units, `fidelity`, `designSystem`, and `designSystemVersion`. Enumerate component states, define every interaction legend entry, and declare repeated-component groups with semantic type, dimensions, and count. Each interaction edge references its legend entry; each repeated node records its group and component state.

## Live MCP discovery

Query `bootstrap button` returned `Button, primary`, `80×40`, from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11 with exact style `html=1;shadow=0;dashed=0;shape=mxgraph.bootstrap.rrect;rSize=5;strokeColor=none;strokeWidth=1;fillColor=#0085FC;fontColor=#FFFFFF;whiteSpace=wrap;align=center;verticalAlign=middle;spacingLeft=0;fontStyle=0;fontSize=16;spacing=5;`.

This proves renderer availability only. Confirm the design-system version, component state, label, contrast, and interaction semantics.

Copy the verified primary-button cell from `assets/templates/live-mcp-style-palette.xml` into `spatial-landscape.xml` when Bootstrap is the selected design system. A wireframe cannot prove accessibility or usability of the implemented interface.
