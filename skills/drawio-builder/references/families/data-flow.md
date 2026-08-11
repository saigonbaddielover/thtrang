# Data-Flow Diagrams

## Select the profile

Use `profiles/data-flow.json` for a notation-neutral context or level-0 DFD. It cites the data-flowchart scope of [ISO 5807:1985](https://www.iso.org/standard/11955.html), but it does not claim a Gane-Sarson or Yourdon/DeMarco mapping.

If an exact DFD variant is required, obtain an authoritative mapping from the assignment, repository, user, or a primary source. Until then, use `data-flow-gane-sarson-unknown.json` or `data-flow-yourdon-demarco-unknown.json` and keep notation approval `UNKNOWN`. These blocking profiles contain no inferred shape IDs.

## Build contract

Represent only external entities, processes, data stores, and directed data flows. Label flows with data noun phrases. Never insert flowchart decisions or control commands.

For a context/level-0 pair, compare the multiset of `(external entity, direction relative to system, data label)` values. Require an explicit mapping for any renamed decomposed flow.

## Validation boundary

Automated validation can enforce node classes, directed flows, endpoint integrity, label geometry, and boundary conservation when a semantic manifest is supplied. Generic shape-search results cannot prove a named DFD notation.

Use `assets/templates/data-flow-landscape.xml` only for notation-neutral work.
