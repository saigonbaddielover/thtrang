# Draw.io File Lifecycle

## Contents

- Primary source
- Web edit round trip
- Multi-page files
- Export
- Parity and safety
- Artifact provenance
- Personal installation

## Primary source

Keep one `mxGraphModel` XML file as the primary source for one page. Keep `.drawio` as the editor wrapper. Keep SVG, PNG, and PDF as derived artifacts.

Never patch a derived image and assume the change can be recovered into canonical XML.

## Web edit round trip

1. Give the user the `.drawio` wrapper.
2. Let the user edit and download `.drawio` from diagrams.net.
3. Import the selected page with `sync_drawio.ps1`.
4. Preflight the extracted canonical XML before replacing the existing source.
5. Make canonical XML primary again.
6. Rerender, validate, inspect, and regenerate every derived asset.

Support both standard compressed page payloads and `compressed="false"` wrappers. Write updates atomically and preserve diagram ID and name.

## Multi-page files

Process one page at a time. When a wrapper has multiple pages, require `PageId`. List available IDs and names on ambiguity. Extract each page to its own canonical source. Patch only the selected page when syncing back and preserve all other pages.

## Export

Use the local Draw.io desktop CLI for persistence and export. Run it in a hidden process and check the exit code. Use page bounds rather than content cropping for page-aware deliverables.

The desktop CLI crops to content by default and does not expose a `--size page` option. `export_drawio.ps1` therefore creates a disposable uncompressed wrapper from canonical XML, adds a fully transparent page-bound sentinel, exports from that wrapper, removes the sentinel group from final SVG, and deletes the temporary wrapper. Never add the sentinel to canonical XML or the editable `.drawio` wrapper.

Before export, canonical XML must equal the selected page in the editable `.drawio` wrapper. Pass `PageId` for a multi-page wrapper. If parity fails, import or sync deliberately before exporting; never overwrite a web edit silently.

Each requested output is rendered to a unique sibling temporary file. Validate freshness, nonempty content, SVG page bounds, PNG dimensions, and PDF page contract before changing any destination. Build and validate the artifact manifest against the staged output hashes. Commit the requested outputs and manifest as one recoverable bundle: keep sibling backups until every replacement succeeds, restore the previous complete bundle in reverse order after any replacement failure, and publish the manifest last. A renderer exit code of zero is not sufficient evidence that it wrote a new file.

Automatic CLI discovery selects the highest semantic `app-<version>` directory and reports the resolved version. Pass an explicit executable when reproducibility requires a locked build.

Verify:

- SVG `viewBox` matches canonical page dimensions within the renderer's documented one-pixel page-border tolerance;
- PNG dimensions match the configured scale;
- requested outputs exist and are nonempty;
- PDF contains exactly one page with a `MediaBox` matching the canonical page;
- PDF is generated only when requested;
- final assets were produced after the last canonical change.

The bundled exporter is intentionally one canonical page per call. One-file all-pages PDF and page-range export are unsupported; report that limitation instead of silently exporting only the first page.

## Parity and safety

Before overwriting, parse candidate XML and write to a temporary sibling file. Move the temporary file into place only after validation. Compare canonical and wrapper `mxGraphModel` recursively while ignoring insignificant whitespace and attribute order.

Fail loudly on missing files, ambiguous pages, malformed compressed payloads, export errors, unsupported formats, or parity mismatch.

## Artifact provenance

Record canonical, wrapper, SVG, PNG, and requested PDF hashes in an artifact manifest with page ID, page dimensions, and renderer name/version. Approval binds the manifest's canonical and SVG paths to the current inputs, requires canonical-to-wrapper page parity, and requires the canonical, wrapper, SVG, and PNG roles. Regenerate the complete requested output set after any canonical import or geometry change.

Keep the manifest and every referenced artifact on one filesystem volume so the manifest can use portable relative paths. Cross-volume artifact bundles fail before destination replacement.

Do not accept timestamps alone as revision proof. Preserve the complete previous requested output and manifest bundle when a staged output, staged manifest, or destination replacement fails.

## Personal installation

When the skill is versioned in a repository, treat that copy as source. Use the bundled personal-sync command manually after reviewed changes. `Check` verifies installed hashes. `Install` stages, validates, and atomically replaces the personal copy. Reject unexplained destination drift unless the user explicitly forces replacement.
