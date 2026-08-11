# ERD

Choose `erd-crows-foot`, `erd-chen`, or `erd-idef1x`; never mix them silently. Crow's Foot follows the explicitly selected [MySQL Workbench convention](https://dev.mysql.com/doc/workbench/en/wb-relationship-tools.html), Chen cites the [original ACM paper](https://dl.acm.org/doi/10.1145/320434.320440), and IDEF1X cites [NIST FIPS PUB 184](https://nvlpubs.nist.gov/nistpubs/Legacy/FIPS/fipspub184.pdf).

Use basic compartmented rectangles for Crow's Foot entities. Live Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, exposed `entityRelationEdgeStyle` with `ERzeroToOne`, `ERzeroToMany`, `ERone`, `ERmandOne`, and `ERoneToMany` endpoints on 2026-08-11. The profile encodes the supported endpoint combinations, but the selected MySQL Workbench convention and semantic manifest remain authoritative. Preserve cardinality, optionality, identifying status, roles, and endpoint association. Geometry checks cannot infer schema semantics without a manifest.

Use `assets/templates/modeling-landscape.xml` only after selecting the notation profile.
