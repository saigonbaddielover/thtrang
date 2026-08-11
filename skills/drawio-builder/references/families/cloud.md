# Cloud

Use `profiles/cloud.json`, name the provider, and search every service symbol live. Use the current provider-owned guidance, such as [AWS Architecture Icons](https://aws.amazon.com/architecture/icons/) or [Azure Architecture Icons](https://learn.microsoft.com/en-us/azure/architecture/icons/).

Never invent a Draw.io stencil identifier or silently use an obsolete icon. Record the provider icon-set release and MCP build. Follow provider rules for distortion, rotation, and labeling.

## Semantic contract

Set `diagram.context.provider`, `providerIconRelease`, and `providerIconSource` to the exact selected provider release and its primary source. `UNKNOWN`, a rolling "current" label, or an MCP build is not a provider release. Classify every edge as `communication`, `data-flow`, or `association`. Keep approval `UNKNOWN` when the exact provider release is unavailable, even when the stencil style matches.

## Live MCP discovery

Query `aws lambda` returned these AWS4 styles from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11:

| Title | Size | Exact style |
| --- | --- | --- |
| `Lambda` | `78×78` | `sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#232F3E;fillColor=#ED7100;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;` |
| `Lambda Function` | `48×48` | `sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=#ED7100;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;pointerEvents=1;shape=mxgraph.aws4.lambda_function;` |

This is live Draw.io MCP provenance, not proof that either icon is current under AWS guidance or that a node is semantically AWS Lambda.

Copy the exact Lambda cell from `assets/templates/live-mcp-style-palette.xml` into `topology-landscape.xml`; automated checks cannot infer service identity or deployment semantics from an icon alone.
