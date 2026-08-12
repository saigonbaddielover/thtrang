# Word Figure Layout

Use this contract when a cropped Draw.io figure will be inserted into Word.

## Select the layout

Measure the complete content envelope, including lanes, connectors, labels, and arrowheads. Fit that envelope into the quality profile's Word frame and calculate the minimum effective font size. Reject every candidate below the configured threshold.

Choose the passing candidate with the largest effective minimum font. Within the profile's regression tolerance, choose fewer predicted boundary crossings, then fewer bends, then the taller layout. Use vertical lanes only while their nodes remain readable. Consider horizontal responsibility bands when they improve readability, but reject the change if the rendered route audit regresses; a wider compact layout with larger declared type is preferable to forced bands that create crossings or divider contacts.

Remove an embedded title when the Word heading or caption names the figure. Preserve semantic notes, lane ownership, DFD data nouns, decision outcomes, document copies, and material lineage.

## Compact the figure

Resize or move nodes before shrinking type. Place data stores beside the processes that own them. Align repeated shapes, use one dominant reading direction, and reserve only the corridors that current routes need.

For flowcharts, remove edge labels duplicated by adjacent node text or an unambiguous route. Keep labels that distinguish decisions, copies, materials, return flows, or parallel routes. For DFDs, keep every data-flow noun phrase.

## Route and export

Prefer cardinal ports and a straight route. If that is blocked, use the port-compatible clear orthogonal route with the fewest bends, then the shortest length. Treat a computed shorter route as advisory until visual inspection confirms that it does not introduce a label collision, edge crossing, divider contact, or semantic ambiguity. Use an outer corridor for return or material flows only when it reduces ambiguity; optimize within that corridor.

Export page-aware SVG and temporary page PNG for QA. Export the committed Word PNG with native diagram cropping, the configured border and theme, one limiting pixel dimension, and the configured density metadata. Validate the crop, pixel dimensions, density, effective font, canonical parity, and hashes before approval.
