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

Use the local Draw.io desktop CLI for persistence and export. Run it in a hidden process and check the exit code. Use native `--size page` for page-aware QA assets and native `--size diagram --border <value>` for cropped figures. Treat missing `--size` support as an unsupported renderer rather than modifying canonical geometry with a page sentinel.

For Word figures, measure the content aspect first and pass only the limiting `--width` or `--height`; passing both lets the renderer choose one dimension and can violate the requested frame. Write the configured PNG density metadata after export and validate it by reopening the final file.

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

Record canonical, wrapper, SVG, page PNG, Word PNG, and requested PDF hashes in an artifact manifest with page ID, page dimensions, delivery metadata, and renderer name/version. Approval binds the manifest's canonical and SVG paths to the current inputs, requires canonical-to-wrapper page parity, and requires every role declared by the task. Regenerate the complete requested output set after any canonical import or geometry change.

Keep the manifest and every referenced artifact on one filesystem volume so the manifest can use portable relative paths. Cross-volume artifact bundles fail before destination replacement.

Do not accept timestamps alone as revision proof. Preserve the complete previous requested output and manifest bundle when a staged output, staged manifest, or destination replacement fails.

## Personal installation

When the skill is versioned in a repository, treat that copy as source. Use the bundled personal-sync command manually after reviewed changes. `Check` verifies installed hashes. `Install` stages, validates, and atomically replaces the personal copy. Reject unexplained destination drift unless the user explicitly forces replacement.
