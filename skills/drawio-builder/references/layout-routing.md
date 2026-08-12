# Layout and Routing Standard

## Contents

- Layout hierarchy
- Shape placement
- Anchors
- Corridors
- Fan-in and fan-out
- Feedback and return flow
- Containers and lanes

## Layout hierarchy

Lay out the semantic backbone before secondary records or annotations. Choose a primary reading direction and maintain it. Reserve whitespace for labels and routes before filling the page.

For Word figures, compare candidate layouts by effective placed font size first, then predicted cross-region routes, then content area. Use portrait or tall geometry on ties. Page orientation is a QA canvas choice; the cropped content envelope is the delivery shape.

Align repeated nodes to a stable grid. Distribute them consistently. Prefer a larger shape or lane over compressed text or a narrow connector gap.

Build dense routing incrementally. Approve the semantic backbone before adding boundary flows, approve boundary flows before store/fan routes, and approve those before returns and labels. Use the route ledger and repair transaction in [construction-gates.md](construction-gates.md).

## Shape placement

Keep unrelated shapes out of connector corridors. Give dense nodes more surrounding whitespace. Place stores and archives where incoming document flows can approach a valid side without sharing an arrowhead.

Do not place source and target perimeters so close that the rendered arrow shaft disappears. Move the nodes or ports until the visible approach is unambiguous.

## Anchors

Use normalized `exitX`, `exitY`, `entryX`, and `entryY` values in `[0,1]`. At least one coordinate at each end must lie on the perimeter. A right-side departure must begin rightward; a top entry must approach downward; a bottom entry must approach upward.

Avoid corner anchors unless the route is intentionally allowed to use either adjacent side. Recompute anchor fractions after resizing a shape so the physical port remains at the intended coordinate.

Start irregular shapes with cardinal-center ports. Treat an off-center port as a higher-risk exception: place an explicit first or final waypoint outside the rendered outline by the endpoint-stub clearance, then render and validate that edge before adding another edge to the region.

Validate the rendered contact point against the actual source and target outlines. A declared side and a correctly directed segment are insufficient when the arrow tip floats, enters the interior, or lands on a neighboring side of an irregular shape.

## Corridors

Use orthogonal 90-degree routes for process, document, DFD, and most architecture flows. Keep an endpoint shaft at least as long as the quality profile minimum. Remove bends shorter than that minimum.

Minimize bends through node placement and cardinal ports before adding waypoints. Among clear routes, minimize bend count before path length. A shorter path does not justify a crossing, a shared corridor, a label collision, or a wrong-side endpoint.

Keep long parallel routes away from lane dividers and unrelated borders. Do not run a connector on a node border or through a label background.

Apply divider clearance to vertical and horizontal dividers only across the divider's actual span. Include stroke width in obstacle and separation calculations.

Separate parallel connectors visually. Near-stacked paths are ambiguous even when their coordinates are not identical.

## Fan-in and fan-out

Assign distinct source and target ports. Give each independent edge its own final shaft and arrowhead. Never allow two flows to share the same final segment unless a semantic junction node explicitly merges them.

Order nested fan-in routes so outer corridors terminate before inner routes cross them. Use top, side, and bottom ports deliberately when a target accepts flows from several directions.

## Feedback and return flow

Reserve an outer return corridor. Avoid hairpins, perimeter detours, lane excursions, and backtracking. A route should not leave a local region, travel past its destination, and reverse merely to find a port.

## Containers and lanes

Create lanes before children. Keep child geometry relative to its lane and fully contained. Cross-lane edges should be parented above the lanes so their paths are not clipped. Preserve header space and do not let labels or connectors mask lane dividers.

After resizing a lane, rerender every child and incident cross-lane edge because absolute positions and corridors change together.

Reserve the lane header as a non-routing region. Audit z-order after container changes so lanes do not occlude child labels or cross-lane edges.
