# UML

Choose exactly one profile: `uml-class`, `uml-activity`, `uml-state`, `uml-sequence`, `uml-component`, or `uml-deployment`. All cite [OMG UML 2.5.1](https://www.omg.org/spec/UML/2.5.1/).

Use basic compartmented rectangles for classifiers and the exact relationship endpoint styles in the selected profile. Live stencil search is unnecessary for standard class and relationship carriers; use it only for specialized glyphs that basic shapes cannot express. Do not reuse process arrows for generalization, realization, aggregation, composition, dependency, replies, or communication paths. Keep multiplicities, guards, and messages attached to their owning relationship without covering endpoints.

Geometry QA is mandatory but cannot infer UML relationship intent. Use `assets/templates/modeling-landscape.xml` only as a neutral scaffold.
