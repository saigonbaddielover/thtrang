# BPMN

Use `profiles/bpmn.json`. The normative source is [OMG BPMN 2.0.2](https://www.omg.org/spec/BPMN/2.0.2/).

Resolve every `LIVE_SEARCH_REQUIRED` matcher through live MCP shape search and record the server/build fingerprint. Keep sequence flow inside a pool, message flow between participants, and associations distinct. A generic flowchart diamond is not notation proof for a BPMN gateway.

## Live MCP discovery

Discovered from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11. These results prove only that the current renderer exposes the styles; OMG BPMN remains the semantic authority.

| Query | Title | Size | Exact style |
| --- | --- | --- | --- |
| `bpmn user task` | `User` | `120×80` | `points=[[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0.25,0],[1,0.5,0],[1,0.75,0],[0.75,1,0],[0.5,1,0],[0.25,1,0],[0,0.75,0],[0,0.5,0],[0,0.25,0]];shape=mxgraph.bpmn.task2;whiteSpace=wrap;rectStyle=rounded;size=10;html=1;container=1;expand=0;collapsible=0;taskMarker=user;` |
| `bpmn exclusive gateway` | `Exclusive` | `50×50` | `points=[[0.25,0.25,0],[0.5,0,0],[0.75,0.25,0],[1,0.5,0],[0.75,0.75,0],[0.5,1,0],[0.25,0.75,0],[0,0.5,0]];shape=mxgraph.bpmn.gateway2;html=1;verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;align=center;perimeter=rhombusPerimeter;outlineConnect=0;outline=none;symbol=none;gwType=exclusive;` |
| `bpmn none start event` | `None Start` | `50×50` | `points=[[0.145,0.145,0],[0.5,0,0],[0.855,0.145,0],[1,0.5,0],[0.855,0.855,0],[0.5,1,0],[0.145,0.855,0],[0,0.5,0]];shape=mxgraph.bpmn.event;html=1;verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;verticalAlign=top;align=center;perimeter=ellipsePerimeter;outlineConnect=0;aspect=fixed;outline=standard;symbol=general;` |

Automated geometry checks cannot establish BPMN semantics without an explicit semantic manifest and verified stencil mapping. Use `assets/templates/bpmn-live-discovery-landscape.xml` for the verified none-start/user-task/exclusive-gateway subset; use `modeling-landscape.xml` for any other BPMN subset until its styles are resolved.
