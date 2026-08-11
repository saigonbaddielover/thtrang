# Network

Use `profiles/network.json`. Declare logical, physical, security-zone, or traffic-flow intent and the applicable vendor convention. Resolve devices through live MCP search.

A connector may mean an undirected link, directed path, or bidirectional traffic; declare the meaning in the manifest. Generic substitution requires explicit acceptance.

## Semantic contract

Set `diagram.context.vendor`, `vendorConvention`, `vendorIconRelease`, `vendorIconSource`, and `networkLayer`. The layer is one of `logical`, `physical`, `security-zone`, or `traffic-flow`. A Draw.io stencil match does not establish the vendor convention or release, so keep approval `UNKNOWN` until both come from a primary vendor source or an explicit project contract.

## Live MCP discovery

Query `cisco router` returned these styles from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11:

| Title | Size | Exact style |
| --- | --- | --- |
| `10700` | `78×53` | `strokeColor=#ffffff;sketch=0;html=1;pointerEvents=1;dashed=0;fillColor=#036897;strokeWidth=2;verticalLabelPosition=bottom;verticalAlign=top;align=center;outlineConnect=0;shape=mxgraph.cisco.routers.10700;` |
| `ATM Router` | `78×53` | `strokeColor=#ffffff;sketch=0;html=1;pointerEvents=1;dashed=0;fillColor=#036897;strokeWidth=2;verticalLabelPosition=bottom;verticalAlign=top;align=center;outlineConnect=0;shape=mxgraph.cisco.routers.atm_router;` |
| `Content Router` | `64×50` | `sketch=0;points=[[0.015,0.015,0],[0.985,0.015,0],[0.985,0.985,0],[0.015,0.985,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0.25,0],[1,0.5,0],[1,0.75,0],[0.75,1,0],[0.5,1,0],[0.25,1,0],[0,0.75,0],[0,0.5,0],[0,0.25,0]];verticalLabelPosition=bottom;html=1;verticalAlign=top;aspect=fixed;align=center;pointerEvents=1;shape=mxgraph.cisco19.rect;prIcon=content_router;fillColor=#FAFAFA;strokeColor=#005073;` |

These prove renderer availability only. Confirm the exact required device and that the selected Cisco icon convention is acceptable.

Copy the exact ATM-router cell from `assets/templates/live-mcp-style-palette.xml` into `topology-landscape.xml` only when that model is intended. Automated checks cannot infer a network layer, vendor, device, or protocol from appearance.
