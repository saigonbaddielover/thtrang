# Visual Failure Catalog

## Contents

- Text and shape
- Endpoint and arrow
- Routing
- Labels
- Containers and composition
- Lifecycle
- Audit integrity

## Text and shape

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Text outside a shape | Geometry was sized from character count or XML bounds | Rendered ink remains inside the real outline with profile clearance | Reflow, then enlarge around the intended port center |
| Text touches an outline | Irregular perimeter was treated as a rectangle | Minimum ink-to-outline distance meets the shape adapter threshold | Increase internal padding or shape size |
| Tiny type | Shape or lane was kept too small | Body, edge, and title sizes meet the quality profile | Relayout before reducing type |
| Missing glyph or fallback | Requested font is unavailable or lacks the label script | Rendered font and glyph coverage are known | Use an approved installed font and rerender |
| Document-curve collision | Bottom curve was ignored | Ink clears the rendered curve, not the XML box | Raise/reflow text or enlarge the document |
| Ellipse/rhombus overflow | Corner areas were treated as usable | Ink stays inside the central safe region | Enlarge both axes and recenter |
| Note-fold collision | Folded corner was ignored | Ink clears the fold path | Add right/top padding or enlarge |
| Cylinder/store collision | Caps or open-store lines were ignored | Ink clears every internal and external stroke | Reflow and enlarge |
| Archive overflow | Divider, slopes, or apex were ignored | Ink clears divider, both slopes, and bottom/apex | Preserve the top port, widen or deepen symmetrically, reroute incident edges |

## Endpoint and arrow

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Tangent departure | First segment follows the source border | First visible shaft leaves along an allowed outward normal | Recompute source port and first bend |
| Tangent arrival | Final segment follows the target border | Arrow approaches along an allowed inward normal | Recompute target port and final bend |
| Wrong-side attachment | Declared anchor and rendered route disagree | Declared side, physical contact, and rendered direction agree | Change the port or route topology |
| Floating arrow | Arrow tip does not contact the target outline | Tip-to-outline distance stays within tolerance | Move target port or final waypoint |
| Arrow buried in a node | Shaft crosses the target before the tip | Only the arrow tip contacts the target boundary | Move the final bend outside the target |
| Zero-length shaft | Perimeters are too close or the renderer collapses the segment | Visible source and target shafts meet the profile minimum | Move nodes or ports |
| Duplicate fan-in arrow | Independent edges share a final segment or port | Every independent flow has a distinct final shaft and arrowhead | Assign separate ports and corridors |

## Routing

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Micro-jog | Bend and port coordinates differ by a few pixels | Every non-semantic segment meets the minimum length | Align coordinates or remove the bend |
| Hairpin/backtracking | Route overshoots and reverses | Direction changes only to clear an obstacle or express a return | Choose a nearer side or reserve a direct corridor |
| Perimeter detour | Local flow uses a page-edge or foreign-lane corridor | Route remains in the smallest clear region | Relayout the local nodes and port |
| Shared or near-stacked path | Independent flows reuse one corridor | Parallel independent edges meet separation clearance | Allocate separate corridors |
| False junction | Edges cross or touch without a junction node | Every touch is either separated or modeled as a junction | Reroute or add a semantic junction |
| Border running | Edge overlaps a node or lane border | Stroke-aware clearance remains positive | Move the corridor or obstacle |
| Divider hugging | Long segment runs too close to a lane divider | Parallel-divider clearance meets the profile | Shift the corridor or resize the lane |
| Node crossing | Rectangular-only obstacle logic misses an actual shape | Connector never enters an unrelated rendered outline | Reroute using outline-aware obstacles |

## Labels

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Label-node collision | Offset was chosen from connector center only | Ink and background clear every shape outline | Move, wrap, or create whitespace |
| Label-edge collision | Label masks another route or arrow | Label bounds clear unrelated connector strokes | Move label or route |
| Label-label collision | Dense labels overlap | Every label has an independent readable region | Reorder routes, wrap, or increase spacing |
| Misassociation | Label is closer to another edge than its owner | Own-edge distance beats unrelated-edge distance by the profile margin | Move label into its edge corridor |
| Bend or arrow masking | White background covers route topology | Label clears bends, endpoint shafts, and arrowheads | Move away from the endpoint |
| Divider masking | Label background breaks a lane line | Label clears lane headers and dividers | Use the lane interior or a dedicated corridor |

## Containers and composition

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Child outside lane | Relative and absolute geometry were confused | Child outline and label stay inside the client area | Correct relative geometry or resize lane |
| Header interference | Child or edge uses the lane header region | Header remains reserved for lane identity | Move child/route into the client area |
| Shape-divider contact | Resize consumed the lane margin | Shape-to-divider clearance meets the profile | Resize lane or shape |
| Node-node overlap | Placement was not rechecked after text fit | Rendered outlines and labels remain separate | Relayout neighboring nodes |
| Z-order occlusion | A later object hides required content | Required nodes, labels, and connectors remain visible | Correct parent/layer/order |
| Wrong orientation | Page direction contradicts the topology | Primary reading path fits the selected orientation | Switch page orientation and relayout |
| Imbalance | One region is compressed while another is empty | Density, spacing, and hierarchy read deliberately | Redistribute the semantic backbone |

## Lifecycle

| Failure | Root cause | Required invariant | Repair class |
| --- | --- | --- | --- |
| Content-cropped export | Desktop CLI exports content bounds | Final output matches canonical page bounds | Use the disposable page sentinel |
| Stale-output false pass | Renderer exits zero without writing | Only a fresh validated temporary output replaces the destination | Render to a unique temporary sibling |
| Wrapper drift | Canonical export ignores newer web edits | Selected wrapper page equals canonical XML before export | Import or sync deliberately |
| Wrong PDF page | Old or mismatched PDF survives | Page count and `MediaBox` match canonical page | Reject and preserve the prior output |
| Asset mismatch | Canonical, wrapper, SVG, PNG, or PDF differ | Artifact manifest hashes one reviewed revision | Regenerate the entire requested asset set |
| Renderer drift | Different Draw.io builds alter output | Renderer version is pinned or explicitly reviewed | Rerender and update validated provenance |

## Audit integrity

Treat these as mandatory visual checks even when automation reports zero issues:

- unknown or multi-path stencil safe areas;
- rendered label backgrounds and glyph substitution;
- long but irrational detours;
- subtle edge-label misassociation;
- reading order, hierarchy, density, symmetry, balance, and whitespace;
- color and grayscale contrast;
- final full-resolution asset consistency.

Every confirmed failure becomes a synthetic regression fixture. Never encode an unaudited diagram as a clean golden baseline.
