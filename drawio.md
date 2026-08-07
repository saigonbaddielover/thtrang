# Draw.io MCP capability audit

## Audit snapshot

Audit này được refresh trực tiếp từ MCP endpoint đang chạy ngày `2026-08-07`, không dựa vào danh sách tool cũ trong hội thoại.

| Artifact | Live value |
|---|---|
| MCP alias | `drawio` |
| Endpoint | `https://mcp.draw.io/mcp` |
| Protocol | `2025-06-18` |
| Server | `drawio-mcp-app` |
| Server version | `1.0.0` |
| Build | `42835e3@2026-08-02T20:17:10.515Z` |
| `create_diagram` description length | `52,183` characters |
| `create_diagram` description SHA-256 | `7bdb482998cdbb338849a9d0b0f909c6e2a6b286aac14cecf8d2d085a3d77f15` |
| `search_shapes` description length | `885` characters |
| `search_shapes` description SHA-256 | `05617676e6cdc389c1f5e55f6abbc9481c5187a5fa7d9dc47bc742d53aa2178e` |
| Viewer resource length | `567,069` characters |
| Viewer resource SHA-256 | `fb1a007ad770d7ac86a21419b24641aee40eca68443c60178a52ed22bd386c12` |
| Live runtime test status | Contract, validator, XML preview, `libavoid`, ELK, multi-page, fixed connector và DFD shape search đã được gọi thật |

Các hash trên dùng để phát hiện server drift. Nếu một lần audit sau cho hash khác thì specification này phải được kiểm tra lại.

Viewer tải thêm các bundle CDN không version-pin trong URL. Fingerprint tại thời điểm audit:

| Runtime bundle | Bytes | SHA-256 |
|---|---:|---|
| `viewer-static.min.js` | `4,137,189` | `a19f7399f6417509bd7610138991883d6167af48a5eacf485b70b1334cf8e451` |
| `drawio-elk.min.js` | `916,526` | `712fe154d6e1fc2d6b83d4a7e4234f3195939029f84d0eb82280db5d2ba8b212` |
| `libavoid-routing.js` | `25,842` | `9327d57d3c4f3fa04fc1eeb91d7da045c2b1a2ba87df681e029145d3ee2f04b6` |
| `libavoid.min.js` | `572,189` | `1c963a8f53b464a87c2fba3dc304a720d924fdcda4737cfd950e33f6a4c41c1d` |
| `drawio-mermaid.min.js` | `698,882` | `f406d5b44a36e750393fddde8dcf1952ec5c5b4d3c0d6e70eafec98c9c92aa38` |

Các URL CDN này có cùng observed ETag `"FZ1q9Q"` nhưng không chứa version. Visual behavior có thể drift dù MCP build/hash không đổi; audit lại phải fingerprint cả resource lẫn năm bundle.

Tài liệu này chuẩn hóa toàn bộ thông tin có thể dùng để gọi và vận hành MCP; nó không chép nguyên văn lặp lại toàn bộ description 52.183 ký tự hoặc bundle viewer 567.069 ký tự. Exact schemas, literals, identifiers, defaults, error strings và limitation được giữ nguyên; phần prose/reference trùng lặp được hợp nhất theo capability.

## 0. Kết luận chính

Draw.io MCP hiện tại **không phải một MCP editor CRUD**. Nó không expose các tool kiểu `open_file`, `add_node`, `update_edge`, `save`, `export_svg`.

Nó chỉ expose:

1. `create_diagram`: nhận toàn bộ Mermaid hoặc draw.io XML rồi hiển thị một viewer tương tác.
2. `search_shapes`: tìm style identifier trong thư viện shape.

Vì vậy:

- Có thể tạo sơ đồ cực chi tiết bằng single-page `mxGraphModel` XML rồi gửi vào `create_diagram`; server nhận `mxfile` nhưng current viewer không render multi-page.
- Có thể điều khiển shape, tọa độ, style, connector và page setup thông qua XML.
- Không thể chỉnh sửa tăng dần một diagram đang tồn tại bằng node/edge ID.
- Không thể trực tiếp đọc hoặc ghi file `.drawio`.
- Không có tool export SVG/PNG/PDF.
- Không có tool tự động phát hiện overlap, crossing hoặc phần tử vượt trang.
- Viewer có nút `Open in draw.io` và `Copy XML`, nhưng đây là chức năng UI, không phải MCP tool.

Không có file sơ đồ, source `.drawio` hoặc tài liệu bài tập nào bị tạo/sửa trong quá trình audit. Các live test chỉ tạo viewer fixture độc lập trong conversation; `TT/drawio.md` là file duy nhất được cập nhật theo yêu cầu.

---

# 1. Server thực tế

| Thuộc tính | Giá trị thực tế |
|---|---|
| Codex MCP alias | `drawio` |
| Namespace trong client | `mcp__drawio` |
| Configured endpoint | `https://mcp.draw.io/mcp` |
| MCP `serverInfo.name` | `drawio-mcp-app` |
| MCP `serverInfo.version` | `1.0.0` |
| Build ID trong viewer | `42835e3@2026-08-02T20:17:10.515Z` |
| Negotiated MCP protocol | `2025-06-18` |
| Server capabilities | `tools.listChanged=true`, `resources.listChanged=true` |
| Prompts capability | Không advertise |
| Resource templates | Không có |
| MCP tasks | `taskSupport: "forbidden"` cho cả hai tool |

Build ID là commit `42835e3` cộng thời điểm build/deploy. `create_diagram` cũng chèn `_buildId` vào result payload.

---

# 2. Tools được expose

Server chỉ expose đúng hai tool:

- `create_diagram`
- `search_shapes`

Tên callable trong Codex:

- `mcp__drawio__create_diagram`
- `mcp__drawio__search_shapes`

Không tìm thấy tool thứ ba.

---

## Tool 1

```text
Tool:
Exact name: create_diagram
Codex callable name: mcp__drawio__create_diagram
Purpose: Creates and displays an interactive draw.io diagram. Accepts either draw.io XML or Mermaid.js syntax — provide exactly one.
Relevant to diagram drawing: Yes
```

### Input schema đầy đủ

```json
{
  "type": "object",
  "properties": {
    "xml": {
      "type": "string",
      "description": "draw.io XML content in mxGraphModel format. Must be well-formed XML: no XML comments (<!-- -->), no unescaped special characters in attribute values. Mutually exclusive with 'mermaid'."
    },
    "mermaid": {
      "type": "string",
      "description": "Mermaid.js diagram definition (e.g. 'graph TD\\n  A-->B'). Supports 26 diagram types — see the tool description for the full list. The diagram is parsed and laid out natively (no upstream mermaid runtime) and converted to draw.io format. Mutually exclusive with 'xml'."
    },
    "postLayout": {
      "type": "string",
      "enum": ["elk"]
    },
    "direction": {
      "type": "string",
      "enum": ["vertical", "horizontal"]
    },
    "routing": {
      "type": "string",
      "enum": ["libavoid"]
    }
  },
  "additionalProperties": false,
  "$schema": "http://json-schema.org/draft-07/schema#"
}
```

### Required arguments

JSON Schema không đánh dấu field nào là required, nhưng handler áp dụng điều kiện semantic:

- Phải cung cấp đúng một trong:
  - `xml`
  - `mermaid`
- Chuỗi được cung cấp phải có nội dung sau khi `trim()`.
- Cung cấp cả hai hoặc không cung cấp cái nào đều trả `isError: true`.

### Optional arguments

| Argument | Allowed value | Applicable to |
|---|---|---|
| `postLayout` | `"elk"` | XML hoặc Mermaid |
| `direction` | `"vertical"`, `"horizontal"` | XML dùng cùng `postLayout:"elk"` |
| `routing` | `"libavoid"` | XML only |

### Defaults

- `direction`: mặc định `"vertical"` khi XML dùng `postLayout:"elk"`.
- `postLayout`: không có default; bỏ qua nếu không truyền.
- `routing`: không có default.
- Với Mermaid, hướng lấy từ source như `flowchart TD`, `LR`; `direction` bị ignore.
- Với Mermaid, `routing` bị ignore.

### Return/output

Không có `outputSchema` hoặc `structuredContent`.

#### XML success

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"xml\":\"...\",\"postLayout\":\"elk\",\"direction\":\"vertical\",\"routing\":\"libavoid\",\"_buildId\":\"...\"}"
    }
  ]
}
```

Chỉ các optional field thực sự được truyền mới xuất hiện.

Nếu XML validator phát hiện vấn đề, `content` có thể có block text thứ hai:

```json
{
  "type": "text",
  "text": "ERRORS (will cause rendering issues):\n- ...\n\nWARNINGS (may cause issues):\n- ..."
}
```

Validator warning/error không nhất thiết làm toàn bộ call thành `isError:true`.

#### Mermaid success

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"mermaid\":\"...\",\"postLayout\":\"elk\",\"_buildId\":\"...\"}"
    }
  ]
}
```

`direction` và `routing` không được đưa vào Mermaid result payload.

### Known constraints

- `xml` và `mermaid` mutually exclusive.
- Schema advertise `additionalProperties:false`, nhưng raw MCP runtime hiện tại bỏ qua field lạ thay vì reject; xem live test ở section 33. Client wrapper vẫn có thể pre-validate theo schema, nên không được truyền field ngoài contract.
- XML comments `<!-- -->` bị cấm.
- XML phải escape `&`, `<`, `>`, `"`.
- Mỗi `id` phải unique.
- Edge phải có:

```xml
<mxGeometry relative="1" as="geometry"/>
```

- Server normalizer thực tế chấp nhận root:
  - `<mxGraphModel>`
  - `<mxfile>`
- Server không parse well-formedness đầy đủ trước khi trả payload. XML có closing tag sai đã được nhận và chỉ bị limited validator báo lỗi root/layer; viewer mới là nơi có thể fail render.
- Mermaid không được server parse trong tool handler. Tool chỉ trả source cho viewer; lỗi parse/render có thể chỉ xuất hiện trong viewer.
- `postLayout:"elk"` thay thế vị trí vertex ban đầu.
- `routing:"libavoid"` giữ vertex nhưng tính lại connector.
- Tài liệu server khuyến cáo coi ELK và libavoid là hai lựa chọn thay thế, không nên dùng đồng thời.
- Viewer phụ thuộc các bundle/CDN draw.io. Nếu bundle Mermaid, ELK hoặc libavoid không tải được, layout/routing có thể bị bỏ qua hoặc viewer hiển thị lỗi.
- Tool annotations:

```json
{
  "readOnlyHint": true,
  "destructiveHint": false,
  "idempotentHint": true,
  "openWorldHint": false
}
```

### Mermaid capability được advertise

Danh sách chính:

- `flowchart` / `graph`
- `sequenceDiagram`
- `classDiagram`
- `stateDiagram` / `stateDiagram-v2`
- `erDiagram`
- `gantt`
- `pie`
- `journey`
- `gitGraph`
- `mindmap`
- `timeline`
- `quadrantChart`
- `xychart-beta`
- `sankey-beta`
- `requirementDiagram`
- `C4Context` / `C4Container` / `C4Component`
- `block-beta`
- `architecture-beta`
- `packet-beta`
- `kanban`
- `radar-beta`
- `treemap-beta`
- `treeview-beta`
- `venn`
- `ishikawa`
- `zenuml`

Embedded Mermaid reference còn nhắc `wardley-beta` và `eventmodeling`, trong khi field description nói “26 diagram types”. Đây là inconsistency trong chính contract; không nên mặc định hai loại bổ sung ổn định nếu chưa test.

Không có specialized Mermaid DFD syntax được advertise.

---

## Tool 2

```text
Tool:
Exact name: search_shapes
Codex callable name: mcp__drawio__search_shapes
Purpose: Search the draw.io shape library by keywords. Returns matching shapes with their exact style strings, dimensions, and titles.
Relevant to diagram drawing: Yes
```

### Exact description

Tool nói nó tìm trong khoảng 10.000 built-in stencils, bao gồm cloud, network, P&ID, electrical, Cisco, Kubernetes và BPMN. Khi kết quả built-in ít, nó có thể bổ sung từ Draw.io icon service.

Tool yêu cầu dùng các style trả về trực tiếp trong `mxCell style`.

### Input schema đầy đủ

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Space-separated search keywords (e.g. 'pid globe valve', 'aws lambda', 'cisco router', 'kubernetes pod')"
    },
    "limit": {
      "type": "number",
      "description": "Maximum number of results to return (default: 10, max: 50)"
    }
  },
  "required": ["query"],
  "additionalProperties": false,
  "$schema": "http://json-schema.org/draft-07/schema#"
}
```

### Required arguments

- `query`

### Optional arguments

- `limit`

### Defaults

- `limit`: `10`
- Maximum thực thi: `50`
- Handler dùng:

```text
Math.min(limit || 10, 50)
```

Schema không yêu cầu integer và không khai báo minimum. Live runtime xác nhận:

- Bỏ `limit` → `10` results.
- `limit=0` → `10` results vì `limit || 10`.
- `limit=1` → `1` result.
- `limit=50` → `50` results.
- `limit=51` → bị cap còn `50` results.
- `limit=-1` không bị schema reject nhưng trả `No shapes found`.
- `limit=1.5` không bị schema reject và thực tế trả `2` results do cách cắt array.

Vì vậy execution specification phải chỉ truyền integer trong `1..50`; mọi giá trị khác tuy có thể lọt runtime nhưng không có semantics sạch.

### Return/output

Success trả `CallToolResult.content[0].text`.

Text chứa JSON array:

```json
[
  {
    "style": "shape=...;",
    "w": 100,
    "h": 60,
    "title": "Shape title"
  }
]
```

Các field result thực tế:

- `style`: exact Draw.io style string.
- `w`: suggested width.
- `h`: suggested height.
- `title`: tên shape.

Nếu không tìm thấy:

```text
No shapes found for query: <query>
```

Đây không phải `isError:true`.

### Known constraints

- Tool không đảm bảo notation family của một result nếu title/style không nói rõ.
- Một số result là `shape=image` trỏ tới `icons.diagrams.net`, không phải built-in vector stencil.
- Search ranking có thể trả result không liên quan nếu query dài hoặc chung chung.
- Không có field library name riêng; đôi khi library chỉ xuất hiện trong `title`.
- Không trả shape ID riêng ngoài style string.
- Không trả perimeter/ports ngoài những gì đã nằm trong `style`.
- `query=""` và query chỉ có whitespace được nhận nhưng trả `No shapes found`; handler không trim/reject query rỗng.
- `limit` sai type, ví dụ string, trả `MCP error -32602` với `invalid_type`.
- Tool annotations:

```json
{
  "readOnlyHint": true,
  "destructiveHint": false,
  "idempotentHint": true,
  "openWorldHint": false
}
```

---

# 3. Resources, templates và prompts

## Resource được expose

```text
URI: ui://drawio/mcp-app.html
Name: Draw.io Diagram Viewer
MIME type: text/html;profile=mcp-app
Description field: Not exposed
```

`resources/read` trả viewer HTML self-contained dài `567,069` ký tự ở build hiện tại. Resource này chứa/inject viewer logic, MCP Apps integration và các bundle cần thiết; số liệu lấy từ output wrapper bị rút gọn trước đây không được dùng làm kích thước resource.

Viewer UI thực tế có:

- Zoom in.
- Zoom out.
- Fit/1:1.
- Expand vertical area.
- Fullscreen.
- Toggle layout.
- `Open in draw.io`.
- `Copy XML`.
- Pan/zoom tương tác.

Các nút này không trở thành MCP tool.

`Open in draw.io` mở một URL có diagram payload trong Draw.io editor. `Copy XML` copy XML hiện tại vào clipboard của viewer.

### Resource `_meta`

```json
{
  "ui": {
    "domain": "5604f724840cf26674b8350fa1891c47.claudemcpcontent.com",
    "csp": {
      "resourceDomains": [
        "https://viewer.diagrams.net",
        "https://app.diagrams.net",
        "https://icons.diagrams.net"
      ],
      "connectDomains": [
        "https://viewer.diagrams.net"
      ]
    }
  }
}
```

Domain trên là deployment-dependent và có thể đổi dù server contract không đổi.

## Resource templates

```json
[]
```

## Prompts

`prompts/list` trả:

```json
{
  "code": -32601,
  "message": "Method not found"
}
```

Kết luận: server không expose prompts.

---

# 4. File / diagram lifecycle

| Capability | Status | Exact mechanism | Notes |
|---|---|---|---|
| Create new diagram | Supported | `create_diagram` | Gửi toàn bộ `xml` hoặc `mermaid` |
| Open existing `.drawio` by path | Not supported | — | Không có `path` argument |
| Display externally-read `.drawio` XML | Supported | `create_diagram(xml=...)` | Client khác phải đọc file trước |
| Read existing diagram structure | Not supported | — | Không có diagram handle hoặc read tool |
| Modify existing diagram incrementally | Not supported | — | Không có update-node/update-edge |
| Re-render a modified full XML | Supported | `create_diagram(xml=...)` | Đây là call mới, không phải edit transaction |
| Save diagram | Not supported | — | Viewer chỉ có `Copy XML`/`Open in draw.io` |
| Save as another file | Not supported | — | Không có output path |
| Create multiple pages | Not supported by the current interactive viewer | Raw server nhận `<mxfile>`, nhưng viewer không import page | `initStreamGraphFromXml` chỉ chuyển `documentElement` vào `streamMergeXmlDelta`; hàm này return ngay nếu node không phải `mxGraphModel` |
| Rename page | Partial | Thay `diagram name` trong full XML rồi call lại | Không có rename operation |
| Delete page | Partial | Bỏ `<diagram>` khỏi full XML rồi call lại | Không có delete operation |
| Duplicate page | Partial | Tạo thêm `<diagram>` với page ID mới trong full XML | Không có duplicate operation |

`mxfile` format được server-linked XSD xác định:

```xml
<mxfile compressed="false">
  <diagram id="page-id" name="Page name">
    <mxGraphModel>...</mxGraphModel>
  </diagram>
</mxfile>
```

- Một `mxfile` chứa một hoặc nhiều `diagram`.
- `diagram.id` phải unique trong file.
- `diagram.name` mặc định `Page-N` nếu bỏ qua.
- `pages` trên `mxfile` chỉ informational; số page thực lấy từ số phần tử `diagram`.
- Live test với hai page chuẩn, mỗi page có structural cells `0` và `1`, được server nhận nhưng limited validator gom ID toàn `mxfile` và báo `Duplicate IDs: 0, 1`. Đây là validator false-positive đối với multi-page, không phải bằng chứng rằng source multi-page sai.
- Viewer implementation audit xác nhận `<mxfile>` root không được decode thành page. Tool call success chỉ chứng minh server transport nhận payload; nó không chứng minh viewer render được multi-page.
- Production rule: mỗi `create_diagram` XML call phải chứa đúng một root `<mxGraphModel>`. Muốn review nhiều page phải gọi từng page riêng.

---

# 5. Page setup

Tất cả page setup nằm trong `<mxGraphModel>`, không phải argument riêng của MCP.

Phân biệt bắt buộc:

- Source/Open-in-Draw.io capability: các page fields được giữ trong XML gốc.
- MCP inline preview capability: viewer streaming hiện tại chỉ decode cells bên trong `<root>` và không apply attributes của `<mxGraphModel>` vào `Graph`.
- Vì vậy preview MCP fit theo content bounds, không hiển thị đáng tin cậy page frame, A4 boundary, grid, page background hoặc page overflow.
- Khi ELK/libavoid chạy, viewer serialize lại live graph thành `currentXml`; implementation không reapply original page attributes. Không được coi `Copy XML` sau post-pass là nơi bảo toàn page setup nếu chưa kiểm tra lại trong Draw.io editor.

## Đơn vị

Server-linked XSD định nghĩa page và geometry bằng **pixels / Draw.io model units**.

## A4

### A4 portrait

```xml
<mxGraphModel
  page="1"
  pageScale="1"
  pageWidth="827"
  pageHeight="1169">
```

Mapping được XSD expose:

```text
210 × 297 mm → 827 × 1169 px
```

### A4 landscape

```xml
<mxGraphModel
  page="1"
  pageScale="1"
  pageWidth="1169"
  pageHeight="827">
```

Mapping:

```text
297 × 210 mm → 1169 × 827 px
```

Không cần tự áp dụng công thức mm→px nếu dùng đúng common values trên. MCP không nhận đơn vị `mm`.

## Page fields

| Capability | Status | XML field | Default |
|---|---|---|---|
| Page size | Supported in source/Open XML; ignored by inline preview | `pageWidth`, `pageHeight` | `850 × 1100` |
| A4 | Supported in source/Open XML; not preview-verifiable | `827 × 1169` hoặc `1169 × 827` | — |
| Custom width/height | Supported | Positive integer pixels | — |
| Portrait/landscape | Supported | Đổi width/height | — |
| Page scale | Supported | `pageScale` | `1` |
| Page margin | Not exposed | — | — |
| Grid visibility | Supported in source/Open XML; ignored by inline preview | `grid="0\|1"` | `1` |
| Grid size | Supported in source/Open XML; ignored by inline preview | `gridSize` | `10` px |
| Snap-to-grid | Unknown | — | `grid` chỉ được mô tả là hiển thị grid |
| Alignment guides | Supported | `guides="0\|1"` | `1` |
| Background | Supported in source/Open XML; ignored by inline preview | `background="#RRGGBB"` hoặc `"none"` | Không nêu |
| Background image | Supported in source/Open XML; ignored by inline preview | `backgroundImage` JSON string | — |
| Page boundary | Supported in source/Open XML; ignored by inline preview | `page="0\|1"` | `1` |
| Custom page-border style | Not exposed | — | — |
| Global shadow | Supported | `shadow="0\|1"` | `0` |

---

# 6. Shape primitives

Mọi node XML dùng cấu trúc chung:

```xml
<mxCell
  id="node-id"
  value="Label"
  style="..."
  vertex="1"
  parent="1">
  <mxGeometry
    x="100"
    y="100"
    width="140"
    height="60"
    as="geometry"/>
</mxCell>
```

Fields điều khiển chính:

- Identity: `id`.
- Text: `value`.
- Appearance/type: `style`.
- Containment: `parent`.
- Geometry: `x`, `y`, `width`, `height`.

## Shape matrix

| Shape | Status | Exact exposed identifier/style |
|---|---|---|
| Generic rectangle/process | Supported | `shape=rectangle` hoặc bỏ `shape` |
| Rounded process | Supported | `rounded=1` |
| Predefined process | Supported | `shape=process` |
| Document | Supported and live fixture accepted | Ưu tiên exact searched style `shape=mxgraph.flowchart.document2;size=0.25`; generic `shape=document` cũng có trong reference |
| Multiple documents | Composite verified at call path; no dedicated native searched ID | Ba `mxgraph.flowchart.document2` children lệch vị trí trong `group;`; remote image alternative phụ thuộc `icons.diagrams.net` |
| Manual input | Supported and live fixture accepted | `shape=manualInput;boundedLbl=1;rounded=1;size=26;arcSize=11` |
| Database | Supported | `shape=cylinder3`, `shape=cylinder`, `shape=mxgraph.flowchart.database` |
| Generic data store | Supported | `shape=datastore` |
| DFD process | Supported as native/basic stencil | `shape=ellipse;html=1;dashed=0;whiteSpace=wrap;perimeter=ellipsePerimeter;` |
| DFD external entity | Supported as generic rectangle | `html=1;dashed=0;whiteSpace=wrap;` |
| DFD data store | Supported | `shape=partialRectangle;right=0;left=0;` hoặc `shape=partialRectangle;right=0;` |
| DFD data store with ID | Supported | `shape=mxgraph.dfd.dataStoreID` |
| Terminator | Supported and live fixture accepted | `shape=mxgraph.flowchart.terminator`; DFD search còn trả `shape=mxgraph.dfd.start` |
| Decision | Supported | `shape=rhombus;perimeter=rhombusPerimeter` |
| Annotation | Supported | `shape=mxgraph.flowchart.annotation_1` hoặc `annotation_2` |
| Note/comment | Supported | `shape=note`, `shape=note2` |
| Swimlane | Supported | `swimlane;startSize=...;horizontal=...` |
| Container | Supported | `container=1;pointerEvents=0` |
| Invisible group | Supported | `group;` |
| Computer/system symbol | Supported through searched remote image; live fixture accepted | `shape=image;...image=https://icons.diagrams.net/assets/devices/1/PC.svg`; phụ thuộc CSP/network |
| File/archive | Supported | `shape=mxgraph.dfd.archive`, `shape=folder`, `shape=mxgraph.flowchart.stored_data` |
| Internal storage | Supported | `shape=internalStorage` |
| Display | Supported | `shape=display` hoặc `shape=mxgraph.flowchart.display` |

Không có tool `create_shape`. Những identifier trên chỉ có hiệu lực khi chúng được viết vào XML gửi cho `create_diagram`.

Live visual-primitive fixture đã đi qua tool path không validator warning với:

- Vietnamese Unicode text.
- `&#xa;` multiline.
- Escaped HTML `<b>`, `<br>`, `<i>` cùng `html=1`.
- `fontFamily=Arial`, `fontSize`, `fontStyle`, align, verticalAlign, spacing, wrapping.
- Terminator, manual input, rounded process, decision, document, DFD entity/process/data store/archive, note.
- Edge labels, label offset, dashed line, stroke width và classic arrow.
- Composite three-copy document, remote PC icon, stored data, cylinder database và display.

Call acceptance không chứng minh text không overflow; width/height vẫn phải review bằng render.

---

# 7. Node geometry và layout

| Capability | Status | Mechanism |
|---|---|---|
| `x` | Supported | `mxGeometry.x` |
| `y` | Supported | `mxGeometry.y` |
| `width` | Supported | `mxGeometry.width` |
| `height` | Supported | `mxGeometry.height` |
| Rotation | Supported | `rotation=<degrees>` |
| 90° direction | Supported | `direction=north\|south\|east\|west` |
| Flip horizontal | Supported | `flipH=0\|1` |
| Flip vertical | Supported | `flipV=0\|1` |
| Parent/container | Supported | `parent="<container-id>"` |
| Z-order | Supported structurally | Layer order và cell order; không có z-order operation |
| Align | Not exposed as operation | Phải tính geometry hoặc dùng ELK |
| Distribute | Not exposed as operation | Phải tính geometry |
| Group | Supported in source XML | `style="group;"` và child `parent` |
| Ungroup | Not exposed as operation | Phải viết lại full XML |
| Move | Partial | Đổi `x/y` rồi submit lại toàn bộ XML |
| Resize | Partial | Đổi `width/height` rồi submit lại |
| Incremental move/resize | Not supported | Không có element edit tool |

## Auto-layout

### ELK

```json
{
  "postLayout": "elk",
  "direction": "vertical"
}
```

hoặc:

```json
{
  "postLayout": "elk",
  "direction": "horizontal"
}
```

- Chỉ một algorithm được expose: `"elk"`.
- ELK dùng layered-flow layout.
- ELK thay thế vị trí vertex ban đầu.
- ELK tự route edge.
- Không nên dùng cho swimlane/container mà vị trí mang ý nghĩa.

Exact current CDN defaults cho exposed vertical/horizontal flow:

```text
elk.algorithm=layered
elk.direction=DOWN | RIGHT
elk.edgeRouting=ORTHOGONAL
elk.hierarchyHandling=INCLUDE_CHILDREN
elk.spacing.nodeNode=30
elk.layered.spacing.nodeNodeBetweenLayers=30
elk.edgeLabels.inline=true
elk.spacing.edgeLabel=5
elk.layered.cycleBreaking.strategy=DEPTH_FIRST
elk.layered.considerModelOrder.strategy=NODES
elk.layered.crossingMinimization.forceNodeModelOrder=true
```

Viewer additionally sets:

```text
mermaidPolicy=true
applierOptions.resizeParent=false
edgeStyleMode=orthogonalEdgeStyle
corners=rounded
```

Operational consequences:

- XML child/model order affects node ordering because model order is forced.
- ELK does not guarantee zero crossings; forcing model order can preserve a visually poor order.
- Edge style is canonicalized to orthogonal with rounded corners.
- Edge labels participate in layout.
- Node sizes are pinned; ELK moves nodes but does not solve text overflow caused by undersized input boxes.
- `INCLUDE_CHILDREN` means containers are in the layout graph; this is another reason not to apply ELK to hand-placed swimlanes/document-flow layouts.
- Bundle exposes other presets such as tree/radial/organic internally, nhưng tool schema chỉ cho `postLayout:"elk"` và viewer resolver chỉ chọn `verticalFlow` hoặc `horizontalFlow`.

### Mermaid layout

Flowchart direction:

- `TD`
- `TB`
- `BT`
- `LR`
- `RL`

Không có align/distribute mode riêng.

---

# 8. Connectors / edges

Cấu trúc cơ bản:

```xml
<mxCell
  id="edge-id"
  value="Label"
  style="edgeStyle=orthogonalEdgeStyle;endArrow=classic;html=1;"
  edge="1"
  parent="1"
  source="source-node-id"
  target="target-node-id">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

## Core connector capability

| Capability | Status | Exact mechanism |
|---|---|---|
| Source node | Supported | `source="<node-id>"` |
| Target node | Supported | `target="<node-id>"` |
| Direction | Supported | `source → target` cộng arrow markers |
| Start arrow | Supported | `startArrow=<type>` |
| End arrow | Supported | `endArrow=<type>` |
| Orthogonal | Supported | `edgeStyle=orthogonalEdgeStyle` |
| Elbow | Supported | `edgeStyle=elbowEdgeStyle;elbow=horizontal\|vertical` |
| Straight | Supported | `edgeStyle=none` hoặc không khai báo |
| ER connector | Supported | `edgeStyle=entityRelationEdgeStyle` |
| Curved | Supported | `curved=1` |
| Segmented | Supported | `edgeStyle=segmentEdgeStyle` |
| Waypoints | Accepted by live XML call, but operationally conflicted | `<Array as="points">`; top-level tool instruction lại yêu cầu không hand-route |
| Entry point | Supported and live-call accepted | `entryX`, `entryY`, `entryDx`, `entryDy` |
| Exit point | Supported and live-call accepted | `exitX`, `exitY`, `exitDx`, `exitDy` |
| Source/target side | Supported | Dùng `exitX/exitY`, `entryX/entryY` |
| Port constraint | Supported by raw Draw.io styles; not passed into current libavoid wrapper | `eastwest`, `northsouth`, `perimeter`, `fixed`; dùng fixed `entryX/Y`, `exitX/Y` nếu cần libavoid honor side |
| Obstacle avoidance | Supported | `routing:"libavoid"` |
| Reroute | Supported only during create/render | `routing:"libavoid"` |
| Crossing minimization | Unknown | Không có guarantee |
| Edge label | Supported | `value` trên edge |
| Edge-label position | Supported | `mxGeometry x/y relative="1"` |
| Line width | Supported | `strokeWidth=<number>` |
| Dashed | Supported | `dashed=1`, `dashPattern="..."` |
| Remove/replace edge incrementally | Not supported | Phải submit lại full XML |
| Dangling-edge validation | Supported as warning | XML validator |

## Exact current libavoid behavior

Viewer wrapper:

- Collects every positive-size vertex as an axis-aligned rectangular obstacle.
- Routes only edges whose source and target both resolve to vertex cells.
- Converts absolute routes back into the edge parent coordinate frame.
- Uses `shapeBufferDistance=16` px.
- Uses `idealNudgingDistance=14` px, nên parallel routes có thể được spread.
- Reads fixed `exitX/exitY` and `entryX/entryY`; both coordinates must be numeric.
- Clamps fixed coordinates to `0..1`.
- Reads `sourceJettySize`, `targetJettySize`, then `jettySize`; missing/`auto` normally resolves to `20` px for standard arrow sizes.
- Skips self-loops; their original loop style/waypoints remain.
- Does not pass raw port-constraint masks or shape snap points into `AvoidRouting.computeRoutes`, dù shared routing core có support các concepts đó.
- Geometrically enclosing non-terminal vertices are filtered out as obstacles. This prevents lanes/containers enclosing terminals from blocking all routes, nhưng cũng có thể loại một large background rectangle chỉ vì nó encloses a terminal.
- Edge labels are not registered as obstacles.

For every successfully routed edge, viewer rewrites:

```text
edgeStyle=orthogonalEdgeStyle
rounded=0
curved=<removed>
libavoidRouting=1
orthogonalLoop=1
jettySize=auto   # only when no explicit jettySize exists
html=1
```

Other style fields such as stroke color, width, dash, arrows and label remain unless changed elsewhere.

Consequences:

- `routing:"libavoid"` is not style-neutral.
- A curved, elbow or rounded edge becomes square-corner orthogonal.
- Existing manual waypoints are replaced for routed non-loop edges.
- Dangling edges and self-loops are not obstacle-routed.
- A fixed corner point with two directions can route, nhưng jetty enforcement is skipped for ambiguous multi-direction corners.
- Failure returns no machine-readable error to the tool caller and leaves the diagram on its earlier route.

## Edge styles

```text
orthogonalEdgeStyle
segmentEdgeStyle
elbowEdgeStyle
entityRelationEdgeStyle
isometricEdgeStyle
loopEdgeStyle
sideToSideEdgeStyle
topToBottomEdgeStyle
none
```

## Arrow values

```text
none
classic
classicThin
block
blockThin
open
openThin
oval
diamond
diamondThin
box
halfCircle
circle
circlePlus
cross
baseDash
doubleBlock
dash
async
openAsync
manyOptional
```

Related properties:

```text
startSize
endSize
startFill
endFill
```

## Entry/exit coordinates

- `exitX`: `0.0–1.0`
- `exitY`: `0.0–1.0`
- `entryX`: `0.0–1.0`
- `entryY`: `0.0–1.0`

Meanings:

- `x=0`: left.
- `x=0.5`: horizontal center.
- `x=1`: right.
- `y=0`: top.
- `y=0.5`: vertical center.
- `y=1`: bottom.

Ví dụ exact right-to-left constraint:

```text
exitX=1;
exitY=0.5;
entryX=0;
entryY=0.5;
edgeStyle=orthogonalEdgeStyle;
```

`libavoid` implementation thực tế đọc những fixed constraints này.

Live `create_diagram` call đã nhận không cảnh báo một edge có right exit, left entry và custom waypoint. Kết quả này chứng minh contract/validator chấp nhận syntax; MCP không có geometry query hoặc screenshot để chứng minh machine-readably rằng viewer giữ đúng pixel route sau render.

## Custom waypoints

Syntax được server-linked style reference expose:

```xml
<mxGeometry relative="1" as="geometry">
  <Array as="points">
    <mxPoint x="300" y="150"/>
    <mxPoint x="300" y="250"/>
  </Array>
</mxGeometry>
```

Nhưng có limitation quan trọng:

- Top-level `create_diagram` instruction nói không được tự thêm waypoints.
- `routing:"libavoid"` tính lại edge path, nên custom waypoints không nên được kỳ vọng giữ nguyên.
- `postLayout:"elk"` cũng layout và route lại.
- Custom waypoints chỉ có khả năng giữ ý nghĩa khi bỏ cả ELK và libavoid.
- Vì contract tự mâu thuẫn, execution specification nên coi manual waypoints là **last resort**, không phải đường chính.

## Câu hỏi connector cụ thể

Có thể ép:

```text
source → target
orthogonal 90°
exit right
enter left
```

bằng XML style và `source`/`target`.

Có thể thêm custom waypoints ở raw XML, nhưng không thể đồng thời kỳ vọng `libavoid` hoặc ELK giữ nguyên chúng.

---

# 9. Text và styling

| Capability | Status | XML style/property |
|---|---|---|
| Node label | Supported | `value` |
| Multiline | Supported | `&#xa;` hoặc escaped `&lt;br&gt;` |
| HTML label | Supported | `html=1` |
| Font family | Supported | `fontFamily` |
| Font size | Supported | `fontSize` |
| Bold | Supported | `fontStyle=1` |
| Italic | Supported | `fontStyle=2` |
| Underline | Supported | `fontStyle=4` |
| Bold + italic | Supported | `fontStyle=3` |
| Horizontal align | Supported | `align=left\|center\|right` |
| Vertical align | Supported | `verticalAlign=top\|middle\|bottom` |
| Label position | Supported | `labelPosition`, `verticalLabelPosition` |
| Text wrapping | Supported | `whiteSpace=wrap\|nowrap` |
| Padding | Supported | `spacing`, `spacingTop`, `spacingBottom`, `spacingLeft`, `spacingRight` |
| Fill | Supported | `fillColor` |
| Stroke | Supported | `strokeColor`, `strokeWidth` |
| Rounded corners | Supported | `rounded=1`, `arcSize` |
| Overall opacity | Supported | `opacity=0–100` |
| Fill opacity | Supported | `fillOpacity=0–100` |
| Stroke opacity | Supported | `strokeOpacity=0–100` |
| Text opacity | Supported | `textOpacity=0–100` |
| Overflow control | Supported | `overflow=visible\|hidden\|fill\|width` |

Multiline rules:

- `\n` trong XML attribute không được server khuyến nghị vì có thể render literal.
- Dùng `&#xa;`.
- Hoặc `&lt;br&gt;` cùng `html=1`.
- HTML trong `value` phải XML-escaped.

---

# 10. Swimlane support

## Native support

**Supported.**

Exact style base:

```text
swimlane;
```

## Orientation

```text
horizontal=1
```

- Header nằm phía trên.

```text
horizontal=0
```

- Header nằm bên trái.
- Đây là dạng server reference dùng cho flat cross-functional lanes xếp theo chiều dọc.

## Header size

```text
startSize=<pixels>
```

- Default trong style reference: `23`.
- Flat-lane template của server dùng `startSize=110`.
- Nested architecture template dùng `startSize=24` hoặc `30`.

## Lane geometry

```xml
<mxGeometry
  x="0"
  y="0"
  width="1800"
  height="150"
  as="geometry"/>
```

- Width và height dùng pixel/model unit.
- Không có argument MCP riêng cho lane width/height.

## Add child vào lane

```xml
<mxCell
  id="child"
  vertex="1"
  parent="lane-id">
  <mxGeometry
    x="120"
    y="45"
    width="140"
    height="60"
    as="geometry"/>
</mxCell>
```

Child coordinates tương đối với lane.

## Cross-lane connector

Edge nối child ở các lane khác nhau phải dùng:

```text
parent="1"
```

Không đặt edge vào một lane, nếu không có nguy cơ bị clip theo container.

## Resize

Style reference expose:

```text
recursiveResize=0|1
resizeParent=0|1
resizeParentMax=0|1
resizeLast=0|1
horizontalStack=0|1
```

- `recursiveResize` default `1`.
- Tuy nhiên MCP không có incremental resize tool.
- Muốn resize bằng MCP phải sửa full XML và gọi `create_diagram` lại.
- Side effect chính xác khi người dùng resize trong Draw.io editor thuộc editor UI, không phải MCP transaction.

## Side effects

- Child geometry relative với parent, nên đổi container structure có thể làm vị trí tuyệt đối của child thay đổi.
- ELK không nên dùng cho hand-placed swimlane.
- `routing:"libavoid"` phù hợp hơn vì giữ vertex và chỉ route connector.
- Không có tool kiểm tra child bị tràn khỏi lane.

---

# 11. DFD support

## Native DFD library

**Partially supported / discoverable.**

`search_shapes` thực tế trả các style thuộc namespace:

```text
mxgraph.dfd.*
```

Các exact identifiers tìm được:

```text
shape=mxgraph.dfd.dataStoreID
shape=mxgraph.dfd.start
shape=mxgraph.dfd.check2
shape=mxgraph.dfd.archive
shape=mxgraph.dfd.loop
```

Ngoài ra có generic DFD primitives:

### External entity

```text
html=1;dashed=0;whiteSpace=wrap;
```

Title từ search:

```text
Activity / Process / Entity / External Interactor
```

### Yourdon-style circular process candidate

```text
shape=ellipse;
html=1;
dashed=0;
whiteSpace=wrap;
perimeter=ellipsePerimeter;
```

Title:

```text
Data Process
```

### Data store

```text
shape=partialRectangle;right=0;left=0;
```

hoặc:

```text
shape=partialRectangle;right=0;
```

### Data store with ID

```text
shape=mxgraph.dfd.dataStoreID;
align=left;
spacingLeft=3;
```

## Gane-Sarson

**Unknown.**

Live search `gane sarson` không trả shape được định danh là Gane-Sarson; các result chủ yếu là false matches như `Game`/`GameLift`.

Có thể dùng rounded rectangle/generic process để dựng ký pháp tương đương, nhưng MCP không expose một identifier được gắn nhãn rõ là Gane-Sarson.

## Yourdon/DeMarco

**Unknown as a named library.**

Ellipse `Data Process`, rectangle external entity và open-ended data store đủ để dựng notation kiểu Yourdon/DeMarco, nhưng server không gắn nhãn library/result là `Yourdon` hoặc `DeMarco`.

Live search exact `yourdon demarco` trả:

```text
No shapes found for query: yourdon demarco
```

---

# 12. Export / rendering

## Render preview

```text
Supported
Exact tool: create_diagram
Output: interactive viewer through ui://drawio/mcp-app.html
```

Viewer có pan, zoom, fullscreen, fit, layout toggle.

Preview semantics:

- Viewer render một single-page `<mxGraphModel>`.
- Camera fit theo cell/content bounds, không theo `pageWidth/pageHeight`.
- Page frame, page background, grid và out-of-page state không phải visual assertions của MCP preview.
- `<mxfile>` được server nhận nhưng viewer import rỗng vì root không phải `mxGraphModel`.

Live runtime calls đã tạo thành công các viewer payload sau:

- A4 portrait + two flat swimlanes + native flowchart shapes + `routing:"libavoid"`.
- XML hierarchical flow + `postLayout:"elk"` + `direction:"horizontal"`.
- Fixed right-exit/left-entry orthogonal edge + custom waypoint, không layout/routing pass.
- Two-page `<mxfile>` transport payload; source audit sau đó xác nhận viewer không import pages.

“Thành công” ở đây nghĩa là tool trả viewer payload và không trả `isError:true`. MCP không expose screenshot hoặc post-layout geometry result, nên agent không thể biến việc nhìn thấy cuối cùng thành assertion machine-readable.

## Export capability matrix

| Capability | Status | Tool |
|---|---|---|
| Export SVG | Not supported | — |
| Export PNG | Not supported | — |
| Export PDF | Not supported | — |
| Page-specific export | Not supported | — |
| All-pages export | Not supported | — |
| Transparent background export | Not supported | — |
| Crop/content bounds export | Not supported | — |
| Page bounds export option | Not supported | — |
| Export scale | Not supported | — |
| DPI | Not supported | — |
| Embed fonts | Not supported | — |
| Output file path | Not supported | — |

Viewer có `Open in draw.io`; sau khi mở, con người có thể dùng chức năng export của Draw.io editor. Việc đó nằm ngoài MCP contract.

`Copy XML` cũng là viewer UI, không phải export tool callable từ agent.

---

# 13. Inspection và visual QA

| Capability | Status | Notes |
|---|---|---|
| Render preview | Supported | `create_diagram` |
| Screenshot page | Not supported | Không có MCP screenshot tool |
| Inspect geometry | Not supported as query | Agent chỉ biết XML mà nó tự gửi |
| List all shapes | Not supported | — |
| List all edges | Not supported | — |
| Query element by ID | Not supported | — |
| Read element style | Not supported | — |
| Detect overlap | Not supported | — |
| Detect connector crossing | Not supported | — |
| Validate dangling edge | Supported as warning | Khi gọi `create_diagram(xml=...)` |
| Validate dangling parent | Supported as warning | Khi gọi `create_diagram(xml=...)` |
| Validate element outside page bounds | Not supported | — |
| Validate negative/invalid node geometry | Không được validator thực tế kiểm tra | XSD/reference và renderer có thể xử lý khác nhau |
| Validate unknown shape | Not supported | Unknown shape key có thể bị ignore/fallback |
| Crossing minimization | Unknown | Không có QA result |
| Obstacle avoidance | Supported | `routing:"libavoid"` |

Visual QA bắt buộc phải làm theo pipeline bên ngoài MCP:

```text
create_diagram preview
→ inspect bằng mắt/vision
→ sửa full XML
→ create_diagram lại
```

MCP không trả machine-readable overlap/crossing report.

Các live preview test không thay đổi limitation này: server response trả source XML cùng option; ELK/libavoid chạy client-side và geometry sau pass chỉ tồn tại trong viewer `currentXml`. Không có MCP tool để đọc lại `currentXml`.

## XML checks validator thực tế làm

### Errors

- XML comments.
- Duplicate IDs.
- Missing `id="0"`.
- Missing default layer `id="1" parent="0"`.
- Self-closing edge.
- Edge thiếu `mxGeometry`.

### Warnings

- Edge source không tồn tại.
- Edge target không tồn tại.
- Parent không tồn tại.
- Cell có `source`/`target` nhưng thiếu `edge="1"`.

### Limitation được live-test

- Validator là regex-based, không phải XML parser/XSD validator.
- Malformed XML `<mxGraphModel><root></mxGraphModel>` vẫn được trả trong success payload, kèm lỗi missing root/layer.
- Duplicate node ID, dangling parent, dangling source và self-closing edge được báo chung trong block text thứ hai; call không thành `isError:true`.
- Với multi-page `<mxfile>`, validator kiểm tra ID toàn file thay vì theo từng page và báo false-positive cho structural IDs `0`, `1`.

---

# 14. IDs và references

## Diagram ID

Không có MCP diagram ID hoặc server-side diagram handle.

Mỗi `create_diagram` call độc lập.

## Page ID

Trong `<mxfile>`:

```xml
<diagram id="page-id" name="Page name">
```

- Client cung cấp.
- Phải unique trong file.
- Có thể bỏ ở older files, nhưng nên luôn cung cấp.
- Live multi-page call xác nhận page IDs `page-one` và `page-two` được giữ nguyên trong payload.

## Node ID

```xml
<mxCell id="node-id" .../>
```

- XML path: client tự cung cấp.
- Phải unique trong một page model.
- Structural IDs:
  - `0`: root.
  - `1`: default layer.
- Nhiều page hợp lệ thường lặp `0` và `1`; server validator hiện tại báo false-positive vì kiểm tra global.

## Edge ID

```xml
<mxCell id="edge-id" edge="1" source="a" target="b">
```

- Client tự cung cấp.
- Phải unique.

## Parent ID

```text
parent="1"
parent="lane-id"
parent="group-id"
```

- Child geometry relative với parent container.
- Cross-container edge thường dùng `parent="1"`.

## Connector references

```text
source="<node-id>"
target="<node-id>"
```

Source và target phải tồn tại trong cùng diagram/page model.

## Mermaid IDs

- Mermaid source có node IDs riêng.
- Viewer chuyển Mermaid thành draw.io XML.
- Viewer ổn định hóa generated IDs theo content để streaming preview và final render giữ identity tốt hơn.
- MCP không có tool trả danh sách ID sau conversion.
- Muốn lấy XML IDs phải dùng viewer `Copy XML`, không thể query qua MCP.

## Stability

| Situation | Stability |
|---|---|
| XML ID qua một create call | Stable vì client cung cấp |
| Save/reload nguyên XML | Thường giữ nguyên, nhưng MCP không quản lý save |
| Mermaid re-render cùng source | Viewer cố tạo deterministic/content-based ID |
| Duplicate/import/export qua editor | Unknown |
| ELK/libavoid | Dự kiến giữ cell ID, nhưng thay geometry/edge route |
| Page duplication | Client phải tự tạo page ID mới |

---

# 15. Transaction / edit model

| Capability | Status |
|---|---|
| Apply immediately | Có, mỗi call tạo một viewer/result độc lập |
| Persistent server-side state | Không expose |
| Transaction | Không |
| Undo/redo qua MCP | Không |
| Batch create | Có theo nghĩa gửi toàn bộ diagram XML trong một call |
| Batch update | Không có update operation |
| Atomic persistent operation | Không áp dụng vì MCP không save |
| Rollback | Không |
| Diagram lock/version | Không |
| Optimistic concurrency | Không |

Nếu call XML có validation warnings, server vẫn có thể trả viewer payload. Đây không phải transaction rollback.

Nếu viewer fail trong Mermaid/ELK/libavoid:

- Không có persistent diagram để rollback.
- Viewer có thể giữ graph cũ trong quá trình streaming.
- Final tool result được viewer coi là authoritative.
- Routing failure có thể để diagram ở trạng thái chưa route thay vì fail tool call.

---

# 16. Error handling

## Exact tool errors

### Cả hai hoặc không có `xml`/`mermaid`

```text
Provide exactly one of 'xml' or 'mermaid'. Both were provided.
```

hoặc:

```text
Provide exactly one of 'xml' or 'mermaid'. Neither was provided.
```

`isError: true`.

### Không extract được XML

```text
Could not extract draw.io XML from input. Expected <mxGraphModel> or <mxfile> root element. Received (first 200 chars): ...
```

`isError: true`.

### Mermaid viewer errors

Viewer có thể hiển thị:

```text
Failed to convert Mermaid diagram: ...
Failed to render diagram: ...
Unsupported Mermaid diagram type
draw.io viewer failed to load
drawio-mermaid bundle not loaded
```

### Schema errors

MCP SDK có thể reject:

- Sai type.
- Enum ngoài:
  - `"elk"`
  - `"vertical"`, `"horizontal"`
  - `"libavoid"`

Live raw MCP behavior:

- Invalid enum thực sự trả `MCP error -32602` và `invalid_enum_value`.
- `search_shapes` thiếu `query` trả `MCP error -32602`, message `Required`.
- `search_shapes.limit` là string trả `MCP error -32602`, message `Expected number, received string`.
- Unknown argument trên `create_diagram` trái với exposed `additionalProperties:false`: server nhận call, bỏ field lạ và trả success. Không được dựa vào behavior này vì MCP client wrapper có thể enforce schema trước khi gửi.

## Constraint matrix

| Error category | Actual handling |
|---|---|
| Invalid shape | Live-tested: server nhận unknown shape không warning; viewer fallback/appearance unknown |
| Invalid parent | Warning nếu parent ID không tồn tại |
| Invalid edge source | Warning |
| Invalid edge target | Warning |
| Missing edge geometry | Error text appended |
| Duplicate IDs | Error text appended |
| Invalid node geometry | Live-tested: negative, zero và nonnumeric geometry đều được server nhận không warning |
| File/path error | Không áp dụng; không có path tool |
| Export error | Không áp dụng; không có export tool |
| Unsupported format | Non-XML text bị normalization error; malformed XML-like text có thể lọt tới viewer; Mermaid syntax error chỉ có thể xuất hiện ở viewer |
| Page error | Không có specialized page validator; multi-page vừa có duplicate-ID false-positive vừa không render trong viewer |
| Libavoid failure | Có thể silently keep unrouted diagram |
| ELK failure | Có thể skip layout; không có machine-readable call failure guarantee |

---

# 17. Capability matrix cuối

| Operation needed by our diagrams | Supported? | Exact MCP tool | Important args | Notes |
|---|---|---|---|---|
| Create diagram | Yes | `create_diagram` | `xml` hoặc `mermaid` | Full-document call |
| Set A4 portrait | Source/Open XML only | `create_diagram` | XML `pageWidth="827" pageHeight="1169"` | Inline preview ignores page bounds |
| Set A4 landscape | Source/Open XML only | `create_diagram` | XML `pageWidth="1169" pageHeight="827"` | Inline preview ignores page bounds |
| Create swimlane | Yes | `create_diagram` | XML `swimlane;horizontal=...;startSize=...` | Child dùng `parent=lane-id` |
| Create document shape | Yes; live fixture accepted | `create_diagram` | XML `shape=mxgraph.flowchart.document2;size=0.25` | Exact current searched style |
| Create process | Yes | `create_diagram` | XML rectangle/rounded/process | — |
| Create DFD external entity | Yes, generic | `create_diagram` | Rectangle style | Không có named Gane-Sarson ID |
| Create DFD data store | Yes | `create_diagram` | `shape=partialRectangle` hoặc `mxgraph.dfd.dataStoreID` | — |
| Connect nodes | Yes | `create_diagram` | XML `edge=1`, `source`, `target` | Edge geometry bắt buộc |
| Orthogonal routing | Yes | `create_diagram` | `edgeStyle=orthogonalEdgeStyle` | — |
| Control entry/exit side | Yes | `create_diagram` | `exitX/Y`, `entryX/Y` | Libavoid đọc fixed constraints |
| Custom waypoints | Partial/conflicted; live-call accepted | `create_diagram` | XML `<Array as="points">` | Không dùng cùng ELK/libavoid |
| Move/resize node | Partial | `create_diagram` | Sửa XML geometry rồi resubmit | Không incremental |
| Align/distribute | No dedicated support | — | ELK hoặc manual geometry | ELK là full layout |
| Add edge label | Yes | `create_diagram` | Edge `value`, geometry `x/y` | — |
| Save `.drawio` | No | — | — | Viewer chỉ Copy/Open |
| Export SVG | No | — | — | — |
| Export PNG | No | — | — | — |
| Export PDF | No | — | — | — |
| Inspect element geometry | No query support | — | — | Chỉ inspect XML client có sẵn |
| Preview/render | Yes | `create_diagram` | `xml`/`mermaid` | Interactive MCP App viewer |
| Preview multi-page | No | — | — | Submit one `<mxGraphModel>` per call |

---

# 18. Recommended low-level workflow

Với flowchart tài liệu và DFD cần layout chính xác, workflow ổn định nhất của chính MCP này là XML-first:

```text
1. Discover capability
   → tools/list
   → resources/list

2. Resolve specialized stencil only when necessary
   → search_shapes(query, limit)

3. Build one complete mxGraphModel per page outside MCP
   → no MCP tool
   → configure A4 page in mxGraphModel
   → create layers/lanes
   → create nodes with stable client IDs
   → create edges referencing those IDs

4. Render hand-placed diagram
   → create_diagram(
       xml=<full XML>,
       routing="libavoid"
     )
   → omit postLayout for swimlanes/precise placement

5. Render hierarchical non-container diagram
   → create_diagram(
       xml=<full XML>,
       postLayout="elk",
       direction="vertical|horizontal"
     )
   → omit routing

6. Inspect viewer manually/with external vision
   → no MCP inspection tool
   → check overlap, crossing, clipping and text/icon appearance
   → do NOT infer page bounds from this content-fit preview

7. Patch geometry
   → modify the original full XML outside MCP
   → call create_diagram again

8. Persist
   → MCP cannot save
   → use viewer “Copy XML” or “Open in draw.io”
   → after ELK/libavoid, recheck page setup because viewer serializes the live graph
   → saving to local .drawio requires Draw.io UI or a separate filesystem tool

9. Export
   → MCP cannot export
   → use Draw.io UI or an external Draw.io CLI/rendering pipeline
   → perform A4/page-overflow QA here
```

Cho use case flowchart tài liệu và DFD:

- DFD: XML vì Mermaid không có DFD notation được advertise.
- Lưu đồ tài liệu/swimlane: XML vì cần document shape, lane containment và precise geometry.
- `routing:"libavoid"` phù hợp cho hand-placed swimlane khi square-corner orthogonal edges được chấp nhận và transformed XML sẽ được Copy/Open; nếu canonical local XML phải tự đủ, không được phụ thuộc post-pass.
- Không dùng `postLayout:"elk"` cho swimlane.
- Không dựa vào MCP để save/export/audit visual tự động.

---

# 19. Unsupported / Missing / Unclear capabilities

## Unsupported

- Open `.drawio` bằng file path.
- Read local `.drawio`.
- Save `.drawio`.
- Save As.
- Incremental create/update/delete node.
- Incremental create/update/delete edge.
- Incremental page management.
- Undo/redo qua MCP.
- Diagram transaction.
- Rollback.
- SVG export.
- PNG export.
- PDF export.
- Page-specific export.
- All-pages export.
- DPI/scale/font-embedding export options.
- Output file path.
- Screenshot tool.
- List elements.
- Query element by ID.
- Geometry query.
- Style query.
- Automatic overlap detection.
- Automatic crossing detection/report.
- Page-bound overflow detection.
- Automatic align/distribute tool.
- Page margin setting.
- Custom page-border styling.
- Multi-page `<mxfile>` rendering/page tabs trong current MCP viewer.
- Reliable A4/page-bound preview.

## Missing as dedicated primitives

- Dedicated multiple-document flowchart stencil được định danh rõ.
- Dedicated Gane-Sarson process identifier.
- Dedicated named Yourdon/DeMarco library contract.
- DFD-specific Mermaid syntax.
- File/archive management tool.
- Connector replacement tool.

## Unclear

- Stable support của `wardley-beta` và `eventmodeling` do contract đếm diagram types không thống nhất.
- Snap-to-grid: XML có grid visibility/size nhưng không expose snap flag.
- Crossing minimization của ELK/libavoid.
- ID behavior khi người dùng duplicate/import/export trong external Draw.io editor.
- Font embedding và font fallback trong viewer/export bên ngoài.
- Custom waypoints là syntax được reference support nhưng top-level tool instruction lại yêu cầu không hand-route.
- Render fallback/appearance của unknown shape key; server không validate.
- Browser font fallback cho font không có trên host.

---

# 20. Exact live tool metadata

Phần này ghi lại metadata ngoài input schema mà `tools/list` thực tế trả.

## `create_diagram`

```json
{
  "name": "create_diagram",
  "title": "Create Diagram",
  "annotations": {
    "readOnlyHint": true,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  },
  "execution": {
    "taskSupport": "forbidden"
  },
  "_meta": {
    "ui": {
      "resourceUri": "ui://drawio/mcp-app.html"
    },
    "openai/toolInvocation/invoking": "Creating diagram...",
    "openai/toolInvocation/invoked": "Diagram ready.",
    "ui/resourceUri": "ui://drawio/mcp-app.html"
  }
}
```

## `search_shapes`

```json
{
  "name": "search_shapes",
  "title": "Search Shapes",
  "annotations": {
    "readOnlyHint": true,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  },
  "execution": {
    "taskSupport": "forbidden"
  },
  "_meta": {
    "openai/toolInvocation/invoking": "Searching shapes...",
    "openai/toolInvocation/invoked": "Shape search complete."
  }
}
```

`readOnlyHint:true` ở đây có nghĩa tool không persist thay đổi vào file/server state. Nó vẫn tạo một result viewer trong host UI.

---

# 21. XML generation discipline embed trong MCP

Đây là instruction được `create_diagram` embed trực tiếp, không phải khuyến nghị tự đặt ra.

## Format decision

- Dùng `mermaid` cho diagram type được Mermaid reference hỗ trợ khi không cần precise Draw.io XML.
- Dùng `xml` khi:
  - Cần swimlane/pool với vị trí custom.
  - Cần container/group.
  - Cần exact colors, fonts, stencils hoặc layout.
  - Cần cloud/network/electrical/P&ID/floorplan/mockup shapes.
  - Người dùng yêu cầu native Draw.io/XML.
- Với document flowchart/DFD cần semantic shapes và precise placement, XML là lựa chọn cần thiết vì Mermaid không expose DFD notation và không đủ document-flow primitives.

## Rigid XML grid

Embedded reference yêu cầu grid sau cho generated XML:

```text
Column x = col_index * 180 + 40
Row y    = row_index * 120 + 40
```

Default size:

| Node type | Width | Height |
|---|---:|---:|
| Rectangle | 140 | 60 |
| Diamond | 140 | 80 |
| Circle | 60 | 60 |
| Document | 120 | 80 |
| Cylinder | 100 | 70 |

Đây là generation convention, không phải giới hạn renderer. Có thể dùng size khác khi text hoặc page layout yêu cầu.

## Shape selection rules

- Dùng semantic shape phù hợp, không thay mọi thứ bằng rectangle.
- Không cần gọi `search_shapes` cho rectangle, diamond, circle, cylinder, standard flowchart/UML/ERD.
- Gọi `search_shapes` cho industry-specific, branded hoặc pictorial icons.
- Text label phải cùng ngôn ngữ với nội dung người dùng yêu cầu.
- Khi nhiều edge hội tụ và gây crossing, embedded reference khuyên dùng một hub/gateway hợp lý thay vì kéo nhiều connector chéo canvas.
- Secondary detail nên đặt trong node text; edge label nên ngắn.

## XML mandatory rules

- Không có XML comments.
- Attribute values phải escape.
- ID phải unique.
- Edge không được self-close.
- Mọi edge phải có:

```xml
<mxGeometry relative="1" as="geometry"/>
```

- Plain text và HTML text đều nên có `html=1`.
- `<br>` chỉ dùng dưới dạng escaped HTML trong attribute.
- `&#xa;` là newline an toàn cho cả `html=0` và `html=1`.

---

# 22. Complete exposed shape catalog families

Các identifier dưới đây đến từ exact-build `style-reference.md` mà tool description link trực tiếp.

## Core mxGraph shapes

| `shape=` value | Meaning |
|---|---|
| `rectangle` | Rectangle; default nếu không đặt shape |
| `ellipse` | Oval/ellipse |
| `rhombus` | Diamond |
| `triangle` | Triangle |
| `hexagon` | Hexagon |
| `cloud` | Cloud |
| `cylinder` | 3D cylinder |
| `line` | Horizontal line |
| `arrow` | Block arrow |
| `arrowConnector` | Arrow-shaped connector |
| `doubleEllipse` | Double-bordered ellipse |
| `image` | Image container |
| `label` | Rectangle có icon area |
| `swimlane` | Container có header |
| `actor` | Actor outline |
| `connector` | Default edge connector |

## Extended Draw.io shapes

```text
cube
isoCube
isoCube2
isoRectangle
cylinder2
cylinder3
datastore
note
note2
document
folder
card
tape
tapeData
process
process2
step
plus
ext
callout
parallelogram
trapezoid
curlyBracket
switch
transparent
message
corner
crossbar
tee
singleArrow
doubleArrow
flexArrow
wire
waypoint
manualInput
internalStorage
dataStorage
loopLimit
offPageConnector
delay
display
or
orEllipse
xor
sumEllipse
sortShape
collate
cross
dimension
partialRectangle
lineEllipse
link
pipe
zigzag
filledEdge
table
tableRow
tableLine
rect2
```

## UML/core modeling shapes

```text
umlActor
umlBoundary
umlEntity
umlDestroy
umlControl
umlLifeline
umlFrame
umlState
lollipop
requires
requiredInterface
providedRequiredInterface
module
component
associativeEntity
endState
startState
```

## Advertised stencil namespaces

```text
mxgraph.flowchart.*
mxgraph.bpmn.*
mxgraph.aws4.*
mxgraph.azure.*
mxgraph.gcp.*
mxgraph.gcp2.*
mxgraph.cisco.*
mxgraph.cisco19.*
mxgraph.kubernetes.*
mxgraph.uml.*
mxgraph.er.*
mxgraph.electrical.*
mxgraph.pid.*
mxgraph.mockup.*
mxgraph.lean_mapping.*
mxgraph.eip.*
```

Stencil syntax được reference nêu:

```text
shape=stencil(<library>.<shape>)
shape=mxgraph.<library>.<shape>
```

Không được tự đoán suffix của stencil. Với stencil cụ thể phải lấy exact style từ `search_shapes`.

---

# 23. Complete style property families

## Fill and stroke

| Property | Values | Default |
|---|---|---|
| `fillColor` | `#RRGGBB`, `none`, `default` | `default` |
| `gradientColor` | `#RRGGBB`, `none` | `none` |
| `gradientDirection` | `north`, `south`, `east`, `west` | `south` |
| `strokeColor` | `#RRGGBB`, `none`, `default` | `default` |
| `strokeWidth` | number | `1` |
| `dashed` | `0`, `1` | `0` |
| `dashPattern` | string such as `1 3`, `8 8` | — |
| `opacity` | `0–100` | `100` |
| `fillOpacity` | `0–100` | `100` |
| `strokeOpacity` | `0–100` | `100` |
| `glass` | `0`, `1` | `0` |
| `shadow` | `0`, `1` | `0` |

## Shape geometry style

| Property | Values | Default |
|---|---|---|
| `shape` | exposed shape identifier | `label` |
| `perimeter` | exposed perimeter identifier | `rectanglePerimeter` |
| `rounded` | `0`, `1` | `0` |
| `arcSize` | `0–50` percentage | — |
| `aspect` | `variable`, `fixed` | `variable` |
| `direction` | `north`, `south`, `east`, `west` | — |
| `flipH` | `0`, `1` | `0` |
| `flipV` | `0`, `1` | `0` |
| `rotation` | degrees `0–360` | `0` |
| `fixedSize` | `0`, `1` | `0` |

## Text and labels

| Property | Values | Default |
|---|---|---|
| `html` | `0`, `1` | `1` |
| `whiteSpace` | `wrap`, `nowrap` | — |
| `fontSize` | number in px | `12` |
| `fontFamily` | string | `Helvetica` |
| `fontColor` | `#RRGGBB`, `default` | `default` |
| `fontStyle` | bitmask `0`, `1`, `2`, `4` | `0` |
| `align` | `left`, `center`, `right` | `center` |
| `verticalAlign` | `top`, `middle`, `bottom` | `middle` |
| `labelPosition` | `left`, `center`, `right` | `center` |
| `verticalLabelPosition` | `top`, `middle`, `bottom` | `middle` |
| `overflow` | `visible`, `hidden`, `fill`, `width` | — |
| `spacing` | number | `2` |
| `spacingTop` | number | `0` |
| `spacingBottom` | number | `0` |
| `spacingLeft` | number | `0` |
| `spacingRight` | number | `0` |
| `textOpacity` | `0–100` | `100` |
| `labelBackgroundColor` | `#RRGGBB`, `none`, `default` | — |
| `labelBorderColor` | `#RRGGBB`, `none` | — |
| `labelWidth` | number | — |
| `textDirection` | `default`, `ltr`, `rtl` | `default` |
| `horizontal` | `0`, `1` | `1` |

`fontStyle` bitmask:

```text
0 = normal
1 = bold
2 = italic
4 = underline
3 = bold + italic
```

## Edge properties

| Property | Values | Default |
|---|---|---|
| `edgeStyle` | exposed edge style | — |
| `curved` | `0`, `1` | `0` |
| `rounded` | `0`, `1` | `1` |
| `jettySize` | `auto`, number | `auto` |
| `sourceJettySize` | number | — |
| `targetJettySize` | number | — |
| `orthogonalLoop` | `0`, `1` | `1` |
| `elbow` | `horizontal`, `vertical` | — |
| `jumpStyle` | `arc`, `gap`, `sharp` | — |
| `jumpSize` | number | `6` |

`jumpStyle` chỉ điều khiển cách biểu diễn crossing; nó không tự giảm số crossing.

## Connection-point properties

```text
exitX
exitY
exitDx
exitDy
exitPerimeter
entryX
entryY
entryDx
entryDy
entryPerimeter
portConstraint
```

Allowed `portConstraint`:

```text
eastwest
northsouth
perimeter
fixed
```

## Container and swimlane properties

| Property | Values | Default |
|---|---|---|
| `container` | `0`, `1` | `0` |
| `collapsible` | `0`, `1` | `1` |
| `recursiveResize` | `0`, `1` | `1` |
| `swimlaneFillColor` | `#RRGGBB` | — |
| `startSize` | number in px | `23` |
| `horizontal` | `0`, `1` | `1` |
| `childLayout` | `stackLayout`, `treeLayout`, `flowLayout` | — |
| `resizeParent` | `0`, `1` | — |
| `resizeParentMax` | `0`, `1` | — |
| `resizeLast` | `0`, `1` | — |
| `horizontalStack` | `0`, `1` | — |
| `marginBottom` | number | — |

## Image properties

| Property | Values | Default |
|---|---|---|
| `image` | URL or data URI | — |
| `imageWidth` | number | `42` |
| `imageHeight` | number | `42` |
| `imageAlign` | `left`, `center`, `right` | — |
| `imageVerticalAlign` | `top`, `middle`, `bottom` | — |
| `imageAspect` | `0`, `1` | `1` |

Relative `image=/...` paths được server absolutize thành `https://app.diagrams.net/...`. Remote image styles phụ thuộc CSP/network.

## Sketch style

```text
sketch=0|1
comic=0|1
fillStyle=solid|hachure|cross-hatch|dots
fillWeight=<number>
hachureGap=<number>
hachureAngle=<degrees>
jiggle=<number>
curveFitting=0..1
simplification=0..1
disableMultiStroke=0|1
disableMultiStrokeFill=0|1
```

## Behavior properties

| Property | Values | Default |
|---|---|---|
| `movable` | `0`, `1` | `1` |
| `resizable` | `0`, `1` | `1` |
| `rotatable` | `0`, `1` | `1` |
| `bendable` | `0`, `1` | `1` |
| `editable` | `0`, `1` | `1` |
| `deletable` | `0`, `1` | `1` |
| `cloneable` | `0`, `1` | `1` |
| `foldable` | `0`, `1` | — |
| `connectable` | `0`, `1` | `1` |
| `pointerEvents` | `0`, `1` | `1` |
| `autosize` | `0`, `1` | `0` |

Viewer MCP vẫn read-only vì graph bị disable; các behavior property chủ yếu có hiệu lực sau khi mở XML trong full Draw.io editor.

---

# 24. Perimeters, predefined classes and colors

## Perimeters

```text
rectanglePerimeter
ellipsePerimeter
rhombusPerimeter
trianglePerimeter
hexagonPerimeter2
parallelogramPerimeter
trapezoidPerimeter
calloutPerimeter
backbonePerimeter
centerPerimeter
stepPerimeter
```

Non-rectangular shape phải dùng matching perimeter, nếu không connector có thể bám vào rectangular bounding box thay vì visible border.

## Predefined style classes

| Class | Effect |
|---|---|
| `text` | No fill/stroke, left/top aligned |
| `edgeLabel` | Text + label background + font size 11 |
| `label` | Bold left-aligned label with image area |
| `icon` | Centered image above text |
| `swimlane` | Swimlane, bold, header 23 |
| `group` | Transparent container |
| `ellipse` | Ellipse + ellipse perimeter |
| `rhombus` | Diamond + rhombus perimeter |
| `triangle` | Triangle + triangle perimeter |
| `line` | Line with stroke width 4 |
| `image` | Image with label below |
| `arrow` | Arrow shape |

## Theme classes

```text
blue
green
yellow
orange
red
pink
purple
gray
turquoise
```

`plain-*` variants dùng cùng color family nhưng không thêm shadow/glass.

## Standard exposed palette

Fill colors:

```text
#DAE8FC
#D5E8D4
#FFF2CC
#F8CECC
#E1D5E7
#E6D0DE
#F5F5F5
#FFCD28
#FFE6CC
```

Matching stroke colors:

```text
#6C8EBF
#82B366
#D6B656
#B85450
#9673A6
#996185
#666666
#D79B00
```

Font/accent colors:

```text
#000000
#FFFFFF
#333333
#0000EE
```

Special values:

```text
none
default
```

`default` phụ thuộc theme hiện tại.

---

# 25. HTML labels, links, tags and metadata

## Supported HTML elements

```text
<b> <i> <u> <s>
<br> <br/>
<p> <div> <span>
<font>
<table> <tr> <td> <th>
<ul> <ol> <li>
<hr>
<img>
<a>
<sub> <sup>
```

HTML trong `value` phải XML-escaped. Không đặt raw `<b>` trực tiếp trong XML attribute.

## Layers

Layer là `mxCell` có `parent="0"` và không có `vertex`/`edge`.

```xml
<mxCell id="0"/>
<mxCell id="1" parent="0"/>
<mxCell id="annotations" value="Annotations" parent="0"/>
```

- Assign shape vào layer bằng `parent="<layer-id>"`.
- Later layer render phía trên earlier layer.
- `visible="0"` ẩn layer mặc định.

## Tags

Tags cần `<object>` wrapper:

```xml
<object id="node-id" label="Label" tags="critical accounting">
  <mxCell style="rounded=1;html=1;" vertex="1" parent="1">
    <mxGeometry x="100" y="100" width="140" height="60" as="geometry"/>
  </mxCell>
</object>
```

- Tags là space-separated.
- Tags dùng để filter visibility trong Draw.io UI.
- Tags không thay z-order hoặc containment.
- Khi dùng `<object>`, visible label nằm ở `object.label`, không phải `mxCell.value`.

## Custom metadata

Custom key/value cũng đặt trên `<object>`:

```xml
<object
  id="node-id"
  label="%document%"
  placeholders="1"
  document="Invoice"
  owner="Accounting">
```

## Placeholders

Custom placeholders:

```text
%document%
%owner%
```

Predefined placeholders:

```text
%id%
%width%
%height%
%date%
%time%
%timestamp%
%page%
%pagenumber%
%pagecount%
%filename%
```

- `%%` tạo literal percent.
- Placeholder lookup đi từ shape lên parent/container/layer/root; first match wins.

## Links and tooltips

XSD expose `link` và `tooltip` trên `mxCell`, `object` hoặc `UserObject` tùy structure. MCP không có tool click/query link; behavior chủ yếu xuất hiện trong viewer/editor.

---

# 26. Cross-functional table and advanced containers

## Flat swimlanes

Embedded reference quy định flat lane template:

```text
Lane x      = 0
Lane y      = lane_index * 150
Lane width  = CANVAS_W
Lane height = 150
Lane style  = swimlane;horizontal=0;startSize=110;...
Child x     = 120 + col * 180
Child y     = 45
Child size  = 140 × 60
```

- Các lane đặt ở `parent="1"`.
- Child dùng lane làm parent.
- Cross-lane edge dùng `parent="1"`.
- Embedded reference khuyên flat lanes, không nest chúng trong một pool.

Đây là template mặc định của MCP, không phải giới hạn renderer. Với document flowchart dài, lane height có thể phải tăng có chủ đích để tránh text/connector collision.

## Nested containers

- Container level dùng `swimlane`.
- Nested child coordinates relative với parent.
- Edge giữa child ở container khác nhau dùng `parent="1"`.
- Embedded architecture template dùng `startSize=24`.

## Cross-functional actor × phase table

Khi cần cả actor rows và phase columns, reference dùng native table:

```text
shape=table;
childLayout=tableLayout;
startSize=0;
collapsible=0;
fillColor=none;
```

Rows:

```text
shape=tableRow;
horizontal=0;
startSize=0;
collapsible=0;
```

Rules:

- Outer table chứa rows.
- Row chứa cells.
- Process node nằm trong cell phù hợp.
- Cross-cell edge dùng `parent="1"`.
- Không nest swimlane trong table row.
- Không đặt `startSize` lên row/cell.
- Table layout normalize widths.

## Collapsible alternate bounds

Collapsible container có thể lưu:

```xml
<mxRectangle
  x="100"
  y="100"
  width="200"
  height="26"
  as="alternateBounds"/>
```

AI-generated XML thường không cần tạo `alternateBounds`; Draw.io editor có thể thêm khi người dùng collapse container.

---

# 27. Full mxfile/XSD object model

Exact-build XSD là AI-oriented schema được tool description link trực tiếp.

## `mxfile`

| Attribute | Meaning |
|---|---|
| `host` | Creating application identifier |
| `modified` | ISO 8601 last-modified timestamp |
| `agent` | User agent/tool identifier |
| `version` | Draw.io application version |
| `etag` | Cache/sync entity tag |
| `type` | Storage backend |
| `compressed` | `"true"` hoặc `"false"`; default `"false"` |
| `pages` | Informational page count |

Common `type` values:

```text
device
google
dropbox
onedrive
github
gitlab
browser
```

AI generation nên dùng:

```text
compressed="false"
```

## `diagram`

| Attribute | Meaning |
|---|---|
| `id` | Page identifier; unique trong file |
| `name` | Display tab name; default `Page-N` |

Một `mxfile` chứa một hoặc nhiều `diagram`.

## `mxGraphModel`

| Attribute | Type/default |
|---|---|
| `dx` | double scroll offset |
| `dy` | double scroll offset |
| `pageWidth` | positive integer, default `850` |
| `pageHeight` | positive integer, default `1100` |
| `pageScale` | double, default `1` |
| `grid` | `0\|1`, default `1` |
| `gridSize` | positive integer, default `10` |
| `guides` | `0\|1`, default `1` |
| `tooltips` | `0\|1`, default `1` |
| `connect` | `0\|1`, default `1` |
| `arrows` | `0\|1`, default `1` |
| `fold` | `0\|1`, default `1` |
| `page` | `0\|1`, default `1` |
| `math` | `0\|1`, default `0` |
| `shadow` | `0\|1`, default `0` |
| `background` | `#RRGGBB` or `none` |
| `backgroundImage` | JSON string |
| `adaptiveColors` | `auto`, `simple`, `none`, `default` |

## Structural cells

```xml
<root>
  <mxCell id="0"/>
  <mxCell id="1" parent="0"/>
</root>
```

## `mxCell`

XSD-exposed attributes:

```text
id
value
style
parent
source
target
vertex
edge
connectable
visible
collapsed
link
```

## `<object>` / `<UserObject>`

Exposed fields include:

```text
id
label
tooltip
link
tags
placeholders
```

Custom metadata attributes may coexist on the wrapper.

## `mxGeometry`

Exposed fields/elements include:

```text
x
y
width
height
relative
as
mxPoint
mxRectangle
Array
```

Common point roles:

```text
sourcePoint
targetPoint
offset
points
```

## Coordinate rules

- `x` tăng sang phải.
- `y` tăng xuống dưới.
- Child coordinates relative với parent vertex/container.
- Vertex cần geometry có `x`, `y`, `width`, `height`.
- Edge cần `relative="1"`.
- XSD hỗ trợ broader XML structure hơn regex validator thực tế; tool không chạy full XSD validation cho mỗi call.

---

# 28. Complete Mermaid contract relevant to this server

Mermaid được parse client-side bằng Draw.io native Mermaid parser, không dùng upstream Mermaid runtime.

## General syntax rules

- Header keyword ở first non-directive line chọn diagram type.
- Misspelled header có thể cho blank/unsupported diagram.
- Node IDs không được có trailing punctuation.
- Tránh spaces, problematic hyphens và reserved words trong node ID.
- Put display text trong brackets/quotes.
- Một statement mỗi dòng.
- Label có punctuation/non-ASCII nên dùng double quotes.
- Reliable HTML subset trong Mermaid label:

```text
<br>
<b>
<i>
<u>
```

- Hex color dùng `#`; reference nói không dùng `rgb()`.
- Một số diagram hỗ trợ title frontmatter:

```text
---
title: Diagram title
---
```

## Flowchart

Directions:

```text
TD
TB
BT
LR
RL
```

Node syntax:

```text
A[rectangle]
A(rounded)
A([stadium])
A[[subroutine]]
A[(cylinder)]
A((circle))
A{rhombus}
A{{hexagon}}
A[/parallelogram/]
A[\alternate parallelogram\]
A[/trapezoid\]
A>asymmetric]
```

Edges:

```text
-->
---
-.-> 
==>
<-->
```

Labels:

```text
A -- text --> B
A -->|text| B
```

Grouping:

```text
subgraph GroupName
  A --> B
end
```

Styling:

```text
style A fill:#f9f,stroke:#333,stroke-width:2px,color:#fff
classDef important fill:#fff2cc,stroke:#d6b656
class A,B important
linkStyle 0 stroke:#f00,stroke-width:3px
linkStyle default stroke:#999
```

Advertised Mermaid style properties:

```text
fill
stroke
stroke-width
stroke-dasharray
color
```

ELK threshold embedded trong tool:

- Khoảng 20 node trở lên.
- Hoặc ít nhất 3 decision diamonds.
- Hoặc có feedback/back-edge.
- Hoặc ít nhất 3 distinct endpoints.

Khi gặp một trong các trường hợp trên, tool description yêu cầu `postLayout:"elk"`.

## Sequence

```text
sequenceDiagram
participant U as User
U->>S: Request
S-->>U: Response
```

Arrows:

```text
->
->>
-->>
-x
--x
```

Supported constructs:

```text
activate
deactivate
alt / else / end
opt / end
loop / end
par / and / end
critical / option / end
Note left of
Note right of
Note over
autonumber
```

## Class diagram

Relations:

```text
<|--
*--
o--
-->
..>
..|>
<-->
```

Visibility:

```text
+
-
#
~
```

Annotations:

```text
<<interface>>
<<abstract>>
<<enumeration>>
```

Quoted cardinalities such as `"1"`, `"0..*"`, `"*"` are supported.

## State diagram

Preferred header:

```text
stateDiagram-v2
```

Supported concepts:

```text
[*] start/end
compound states
<<fork>>
<<join>>
<<choice>>
transition labels
guards/actions
```

## ER diagram

Cardinality tokens:

```text
|o
||
}o
}|
```

Attributes may mark:

```text
PK
FK
UK
```

## Other supported/reference types

| Type | Key syntax/capability |
|---|---|
| `journey` | Sections and `Task: score(1-5): Actor` |
| `pie` | Quoted label + numeric value; optional `showData` |
| `gantt` | Mandatory `dateFormat`; IDs, dates, durations, `after`, `done`, `active`, `crit` |
| `gitGraph` | `commit`, `branch`, `checkout`, `merge`, `cherry-pick` |
| `mindmap` | Indentation defines hierarchy |
| `timeline` | Sections, time labels and multiple events |
| `quadrantChart` | Axes and `[0..1,0..1]` point coordinates |
| `requirementDiagram` | Requirement types, elements and trace relations |
| `sankey-beta` | CSV-like `source,target,value` |
| `xychart-beta` | `x-axis`, `y-axis`, `bar`, `line` |
| `block-beta` | `columns`, spans and flowchart edges |
| `C4Context` | Persons, systems and relations |
| `C4Container` | Container-level C4 |
| `C4Component` | Component-level C4 |
| `architecture-beta` | Groups/services, built-in icons and side-specific edge ends |
| `radar-beta` | Axes and positional curves |
| `packet-beta` | Bit ranges |
| `venn-beta` | `set`, `union`, region `text` |
| `treemap-beta` | Indented categories and numeric areas |
| `treeView-beta` | Indentation hierarchy |
| `ishikawa-beta` | Problem, categories, causes |
| `kanban` | Columns/cards and metadata |
| `zenuml` | Actor/boundary/control/entity/database and message blocks |
| `wardley-beta` | Components with visibility/evolution coordinates |
| `eventmodeling` | Time frames, UI/command/read-model/event types |

## Mermaid limits for precision XML use cases

- Không có DFD syntax.
- Không có native document-flow symbol set tương đương Draw.io flowchart library.
- Không có exact swimlane geometry control phù hợp document flowchart.
- Generated cell IDs không query được qua MCP.
- Mermaid conversion/layout xảy ra trong viewer; server handler không validate source trước khi trả success.

---

# 29. Viewer runtime behavior

## Viewer is read-only

Viewer tạo `Graph` rồi gọi:

```text
setEnabled(false)
setTooltips(false)
foldingEnabled=false
```

Do đó MCP App viewer dùng để xem, pan, zoom và mở sang Draw.io editor; không phải editor trực tiếp.

## XML import boundary

Exact import path:

```text
initStreamGraphFromXml(xml)
→ mxUtils.parseXml(xml)
→ streamMergeXmlDelta(graph, ..., doc.documentElement)
```

`streamMergeXmlDelta` starts with:

```text
if (modelNode.nodeName !== 'mxGraphModel') return pendingEdges;
```

It decodes only cells under the first `<root>`. Consequences:

- Root `<mxGraphModel>`: supported.
- Root `<mxfile>`: no page is imported; viewer graph stays empty.
- Attributes on `<mxGraphModel>` such as page size, grid and background are not applied to the preview graph.
- `<object>`/`UserObject` wrappers inside `<root>` are decoded.
- Parent/source/target are resolved against the live model by ID.

## Streaming

- Partial Mermaid/XML có thể được render khi arguments đang stream.
- Partial XML được heal tạm để preview.
- New cells được merge/animate.
- Final `ontoolresult` là authoritative.
- Nếu final result là error, viewer hiển thị tool error.

## Mermaid conversion

- Mermaid source được convert client-side thành Draw.io XML.
- Generated cell IDs được stabilize theo content cho streaming/final identity.
- Unsupported parser type có thể chỉ fail ở viewer.

## Post-layout

- `postLayout:"elk"` chạy client-side sau render.
- Vertex positions bị thay thế.
- Edge routes được ELK tạo cùng layout.
- Viewer có thể animate transition.
- Final `currentXml`/Copy/Open phản ánh layout đã commit, không chỉ input XML ban đầu.
- Current ELK preset is layered `DOWN` or `RIGHT`, 30 px node/layer spacing, inline edge labels, orthogonal edges and rounded corners.
- Viewer serializes the live graph after ELK. Original page-level attributes are not explicitly re-applied; page setup must be rechecked outside MCP.

## Libavoid routing

- `routing:"libavoid"` chạy client-side.
- Vertex positions được giữ.
- Router tính orthogonal paths tránh obstacle.
- Fixed `entryX/entryY/exitX/exitY` được router đọc.
- Router có thể spread parallel connectors.
- Default obstacle clearance là `16` px; ideal parallel nudge là `14` px.
- Router force edge family thành square-corner orthogonal, removes `curved`, và writes `libavoidRouting=1`.
- Self-loops và dangling edges không được route.
- Current wrapper honors fixed `entry/exit` coordinates but does not forward raw port-constraint masks.
- Nếu libavoid unavailable/fail, viewer giữ diagram unrouted và không nhất thiết biến tool call thành error.
- Final Copy/Open XML phản ánh routed waypoints khi pass thành công.
- Viewer serializes the live graph after routing. Original page-level attributes are not explicitly re-applied; page setup must be rechecked outside MCP.

## Viewer controls

```text
Zoom in
Zoom out
Fit / 1:1
Pan
Expand vertically
Fullscreen
Layout toggle
Open in draw.io
Copy XML
Help
```

Layout toggle chuyển giữa as-authored và một alternative vertical/horizontal layout được viewer chọn.

## Viewer sizing

- Inline viewer có default height cap khoảng `480 px`.
- Expanded mode dùng cap khoảng `1000 px`.
- Fullscreen bỏ inline cap.
- Viewer fit camera theo diagram bounds.
- Đây là preview viewport, không phải page/export size.
- A4 portrait và landscape có thể trông cùng kiểu content-fit nếu cell bounds giống nhau.

## Network dependencies

Resource CSP cho phép:

```text
resource:
  https://viewer.diagrams.net
  https://app.diagrams.net
  https://icons.diagrams.net

connect:
  https://viewer.diagrams.net
```

Remote icon hoặc viewer bundle failure có thể ảnh hưởng render dù XML hợp lệ.

Relative image URLs trong cell style được viewer rewrite về:

```text
https://app.diagrams.net/<relative-path>
```

Searched image results dùng `app.diagrams.net` hoặc `icons.diagrams.net`, đều nằm trong current CSP. Chúng vẫn là network dependencies; native vector shapes ổn định hơn cho tài liệu chấm điểm.

---

# 30. Contract contradictions and required interpretation

## XML input wording versus implementation

- Field description nói `mxGraphModel format`.
- Handler error nói expected `<mxGraphModel>` hoặc `<mxfile>`.
- Normalizer source thực tế nhận cả hai.

Interpretation:

- Server transport/normalizer nhận cả single-page `mxGraphModel` và full `mxfile`.
- Viewer thực tế chỉ import khi root là `mxGraphModel`.
- `<mxfile>` success payload là false signal đối với visual rendering; không dùng multi-page trong một call.
- Validator multi-page còn báo false-positive `Duplicate IDs: 0, 1`.

## Waypoint contradiction

- Linked style reference document custom `<Array as="points">`.
- Top-level generation discipline nói không hand-route waypoints.
- `routing:"libavoid"` và ELK có thể replace routes.

Interpretation:

- Syntax có thật.
- Không dùng custom waypoint trong normal generated workflow.
- Chỉ dùng khi cả ELK và libavoid bị tắt và exact manual route là yêu cầu bắt buộc.

## Mermaid count contradiction

- `mermaid` field description nói 26 types.
- Embedded reference mô tả thêm `wardley-beta` và `eventmodeling`.

Interpretation: flowchart và các type trong primary advertised list là supported contract; hai type bổ sung phải coi là lower-confidence cho tới khi live-tested.

## XML validator versus XSD

- Server validator là regex-based limited validator.
- Nó không chạy full XSD validation.
- Một call không có warning không chứng minh XML hoàn toàn valid.
- Live test chứng minh malformed closing tags vẫn có thể lọt handler, và standard multi-page structural IDs có thể bị báo duplicate sai.

Interpretation: phải tự validate structure, geometry, parent hierarchy, page bounds và visual result ngoài MCP warning.

## Tool annotation versus UI effect

- `create_diagram` có `readOnlyHint:true`.
- Nó vẫn tạo một viewer result trong conversation.

Interpretation: read-only đối với persistent external state/file, không có nghĩa “không tạo UI output”.

---

# 31. Mandatory operating rules for high-quality diagram generation

Agent dùng báo cáo này để vẽ flowchart/DFD phải tuân thủ:

1. Dùng XML, không dùng Mermaid, cho DFD và document flowchart/swimlane.
2. Mỗi `create_diagram` call chỉ gửi một root `<mxGraphModel>`, không gửi `<mxfile>`.
3. Mỗi diagram có stable client-defined IDs.
4. Dùng A4 pixel mapping chính thức trong canonical source:
   - Portrait `827 × 1169`.
   - Landscape `1169 × 827`.
5. Không dùng MCP content-fit preview để kết luận node nằm trong A4; page-bound QA phải làm bằng external render/editor.
6. Dùng semantic flowchart/DFD shapes; không thay mọi symbol bằng rectangle.
7. Ưu tiên native shapes; remote `shape=image` chỉ dùng khi symbol thật sự cần và phải kiểm tra network render.
8. Child trong lane/container dùng relative coordinates.
9. Cross-lane/container edges dùng `parent="1"`.
10. Chọn một routing strategy trước:
   - Hand-placed + `libavoid`.
   - Hoặc ELK full layout.
11. Không stack ELK và libavoid mặc định.
12. Không dùng manual waypoints cùng libavoid/ELK.
13. Khi cần fixed side:
     - Right exit: `exitX=1;exitY=0.5`.
     - Left entry: `entryX=0;entryY=0.5`.
14. Với libavoid, không dựa vào `portConstraint`; dùng đủ pair `entryX/Y` hoặc `exitX/Y`.
15. Nhớ libavoid force `orthogonalEdgeStyle;rounded=0`; không dùng nếu muốn giữ curved/elbow/rounded edge.
16. Edge luôn có expanded `mxCell` và edge geometry.
17. Label dài phải wrap, đủ padding và đủ node size.
18. Edge label phải ngắn và có position/offset khi cần.
19. Dùng `fontFamily=Arial` hoặc font phổ biến có Vietnamese glyphs; MCP không embed font.
20. Không coi `libavoid` hoặc ELK là crossing validator.
21. Sau mỗi render phải inspect:
     - Shape overlap.
     - Text overflow.
     - Connector crossing.
    - Connector qua node.
    - Dangling edge.
     - Lane overflow.
     - Page-bound overflow.
22. Page-bound overflow không thể kết luận từ MCP preview; dùng external page-aware render.
23. Sửa canonical XML gốc rồi resubmit toàn bộ diagram.
24. Nếu dùng ELK/libavoid, transformed waypoints/positions chỉ nằm trong viewer `currentXml`; agent không có readback tool. Muốn persist phải dùng viewer Copy/Open hoặc không dựa vào post-pass cho canonical local source.
25. Không kỳ vọng MCP save/export; persistence/export phải dùng Draw.io UI hoặc external local pipeline.
26. Nếu MCP build/resource hash hoặc bất kỳ CDN bundle hash khác audit snapshot, refresh discovery trước khi tiếp tục vẽ.

---

# 32. Evidence provenance

Live evidence:

```text
MCP initialize
MCP tools/list
MCP resources/list
MCP resources/read
MCP resources/templates/list
MCP prompts/list
search_shapes read-only queries
create_diagram contract/error calls
create_diagram A4/swimlane/libavoid viewer fixture
create_diagram XML/ELK/horizontal viewer fixture
create_diagram fixed entry/exit/waypoint viewer fixture
create_diagram two-page mxfile viewer fixture
create_diagram Vietnamese text + generic flowchart/DFD primitive viewer fixture
create_diagram composite documents + PC/storage/archive viewer fixture
direct invalid shape/geometry/parent-cycle server cases
viewer implementation import/render/layout/routing source inspection
CDN bundle fingerprint and defaults inspection
```

Configured endpoint:

```text
https://mcp.draw.io/mcp
```

Exact-build references:

```text
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/shared/xml-reference.md
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/shared/mermaid-reference.md
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/shared/style-reference.md
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/shared/mxfile.xsd
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/mcp-app-server/src/shared.js
https://raw.githubusercontent.com/jgraph/drawio-mcp/42835e3/mcp-app-server/src/normalize-diagram-xml.js
https://viewer.diagrams.net/js/viewer-static.min.js
https://viewer.diagrams.net/js/elk/drawio-elk.min.js
https://viewer.diagrams.net/js/libavoid-js/libavoid-routing.js
https://viewer.diagrams.net/js/libavoid-js/libavoid.min.js
https://viewer.diagrams.net/js/mermaid/drawio-mermaid.min.js
```

Không sử dụng capability của `mcp-tool-server` local/stdio variant để mô tả remote `drawio-mcp-app`. Variant đó có thể chứa các tool khác trong source repository, nhưng endpoint thực tế của environment này chỉ expose `create_diagram` và `search_shapes`.

---

# 33. Live runtime test matrix

Test date: `2026-08-07`.

Tested server/build:

```text
drawio-mcp-app 1.0.0
42835e3@2026-08-02T20:17:10.515Z
```

Không có test nào ghi file `.drawio` hoặc export ảnh. `create_diagram` tests chỉ tạo các viewer fixture độc lập trong conversation.

## 33.1 `create_diagram` contract and validation

| Case | Input | Observed result |
|---|---|---|
| Neither source | `{}` | `isError:true`; `Provide exactly one of 'xml' or 'mermaid'. Neither was provided.` |
| Both sources | `xml` + `mermaid` | `isError:true`; `Provide exactly one of 'xml' or 'mermaid'. Both were provided.` |
| Empty XML | `xml:""` | Được coi như không cung cấp source; exact “Neither was provided” error |
| Non-XML text | `xml:"not xml"` | `isError:true`; exact extraction error yêu cầu `<mxGraphModel>` hoặc `<mxfile>` |
| Malformed XML-like source | `<mxGraphModel><root></mxGraphModel>` | Tool trả success payload; block thứ hai báo missing root `0` và default layer `1` |
| Valid minimal XML | Root/layer + one vertex | Success payload, không có validator block |
| Duplicate/dangling/self-closing fixture | Duplicate `n1`, missing parent/source, self-closing edge | Success payload + Errors/Warnings block; không `isError:true` |
| Unknown argument | `unexpected:"value"` | Raw MCP runtime bỏ qua field và trả success, trái `additionalProperties:false` trong exposed schema |
| Invalid `direction` | `"diagonal"` | `MCP error -32602`; allowed `"vertical"`, `"horizontal"` |
| Invalid `postLayout` | `"dagre"` | `MCP error -32602`; allowed `"elk"` |
| Invalid `routing` | `"orthogonal"` | `MCP error -32602`; allowed `"libavoid"` |
| Invalid Mermaid syntax | `mermaid:"definitely-not-a-diagram"` | Server trả success payload; chứng minh Mermaid không được parse tại tool handler |

## 33.2 Viewer-path acceptance tests

| Fixture | Exact options | Server/tool observation | What remains unobservable through MCP |
|---|---|---|---|
| A4 portrait, two flat swimlanes, start/manual-input/process/document, cross-lane edges | `routing:"libavoid"` | Success payload; build ID returned; no validator block | Final routed waypoint geometry, overlap/crossing and pixel appearance |
| Hierarchical XML flow with decision branch | `postLayout:"elk"`, `direction:"horizontal"` | Success payload; both options preserved in result | Final ELK node coordinates and route geometry |
| Orthogonal source→target, right exit, left entry, two waypoints | No ELK/libavoid | Success payload; no validator block | Pixel-level proof of the rendered route |
| Two-page `<mxfile>` with portrait and landscape pages | No layout/routing pass | Server payload accepted; validator emits false-positive `Duplicate IDs: 0, 1` | Source inspection proves viewer does not import root `mxfile`; graph stays empty |

Các tests trên xác nhận call path và payload contract. Chúng không thay thế visual QA vì MCP hiện tại không expose screenshot, rendered geometry, `currentXml` readback, overlap detector hoặc crossing detector.

## 33.3 `search_shapes` input behavior

| Case | Observed result |
|---|---|
| Missing `query` | `MCP error -32602`; `Required` |
| Empty/whitespace query | Không error; `No shapes found for query: ...` |
| Omit `limit` | `10` results |
| `limit=0` | `10` results |
| `limit=1` | `1` result |
| `limit=50` | `50` results |
| `limit=51` | `50` results |
| `limit=-1` | Không schema error; `No shapes found` |
| `limit=1.5` | Không schema error; `2` results |
| String `limit` | `MCP error -32602`; `Expected number, received string` |

Production rule: luôn dùng integer `1..50`.

## 33.4 DFD-relevant shape searches

### Query `dfd process`

Relevant live results:

```text
Activity / Process / Entity / External Interactor
style=html=1;dashed=0;whiteSpace=wrap;
w=100 h=50

Data Process
style=shape=ellipse;html=1;dashed=0;whiteSpace=wrap;perimeter=ellipsePerimeter;
w=30 h=30
```

### Query `dfd data store`

Relevant live results:

```text
Data Store
style=html=1;dashed=0;whiteSpace=wrap;shape=partialRectangle;right=0;left=0;
w=100 h=30

Data Store
style=html=1;dashed=0;whiteSpace=wrap;shape=partialRectangle;right=0;
w=100 h=30

Data Store
style=shape=cylinder;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;
w=60 h=80

Data Store with ID
style=html=1;dashed=0;whiteSpace=wrap;shape=mxgraph.dfd.dataStoreID;align=left;spacingLeft=3;points=[[0,0],[0.5,0],[1,0],[0,0.5],[1,0.5],[0,1],[0.5,1],[1,1]];
w=100 h=30
```

### Query `dfd external entity`

Relevant live result:

```text
Activity / Process / Entity / External Interactor
style=html=1;dashed=0;whiteSpace=wrap;
w=100 h=50
```

Search không trả một dedicated style được title là `DFD External Entity`.

### Query `data process id data flow diagram`

Query này xác nhận thêm các native DFD styles:

```text
shape=mxgraph.dfd.dataStoreID
shape=mxgraph.dfd.check2
shape=mxgraph.dfd.archive
shape=mxgraph.dfd.loop
```

### Named notation searches

```text
gane sarson
→ không có result được định danh Gane-Sarson; false matches chiếm ưu thế

yourdon demarco
→ No shapes found for query: yourdon demarco
```

Kết luận test: MCP có DFD-related primitives thật, nhưng không expose một named Gane-Sarson hoặc Yourdon/DeMarco library contract đủ rõ để execution agent chọn notation chỉ bằng tên.

## 33.5 Flowchart shape searches

Exact relevant live results:

```text
Terminator
style=strokeWidth=2;html=1;shape=mxgraph.flowchart.terminator;whiteSpace=wrap;
w=100 h=60

Document
style=strokeWidth=2;html=1;shape=mxgraph.flowchart.document2;whiteSpace=wrap;size=0.25;
w=100 h=60

Manual Input
style=html=1;strokeWidth=2;shape=manualInput;boundedLbl=1;whiteSpace=wrap;rounded=1;size=26;arcSize=11;
w=100 h=60
```

Search `flowchart multiple documents` không trả dedicated native multi-document flowchart stencil. Nó trả single `Document` và các remote Fluent icons. Live fixture đã xác nhận call path của composite ba `document2` children trong một `group`.

Search `computer system` trả nhiều remote images. Một result phù hợp với computer/system semantics:

```text
PC (Devices)
style=shape=image;html=1;verticalAlign=top;verticalLabelPosition=bottom;labelBackgroundColor=default;imageAspect=0;aspect=fixed;image=https://icons.diagrams.net/assets/devices/1/PC.svg
w=120 h=60
```

Search `file archive storage` trả native/cloud/product-specific và remote-image results lẫn nhau. Generic semantic mapping:

- Paper archive: `shape=mxgraph.dfd.archive`.
- Electronic stored data: `shape=mxgraph.flowchart.stored_data`.
- Computer: searched PC remote image only when the explicit computer pictogram adds meaning.

## 33.6 Text, style and primitive acceptance

Live single-page fixtures were accepted without validator blocks for:

| Capability | Exact tested mechanism |
|---|---|
| Vietnamese Unicode | Raw UTF-8 label values |
| Multiline | `&#xa;` |
| Partial bold/italic | XML-escaped HTML with `html=1` |
| Font | `fontFamily=Arial;fontSize=...` |
| Alignment | `align`, `verticalAlign`, `spacing` |
| Wrapping | `whiteSpace=wrap` |
| Edge label offset | Relative edge geometry + `mxPoint as="offset"` |
| Dashed edge | `dashed=1;dashPattern=6 4` |
| Document copies | Three offset `document2` children in `group;` |
| Remote PC icon | `icons.diagrams.net/assets/devices/1/PC.svg` |
| Stored data | `mxgraph.flowchart.stored_data` |
| DFD archive | `mxgraph.dfd.archive` |
| Database | `cylinder3` |
| Display | `mxgraph.flowchart.display` |

Acceptance only proves parser/validator/tool path. Text overflow, glyph fallback, remote icon load and final spacing still require visual inspection.

## 33.7 Validator blind spots affecting visual output

Direct raw MCP calls returned success with no warning for all cases below:

| Case | Tested value |
|---|---|
| Unknown shape | `shape=mxgraph.does_not_exist` |
| Negative position and size | Negative `x`, `y`, `width`, `height` |
| Zero-size vertex | `width="0" height="0"` |
| Nonnumeric geometry | `x="x" y="y" width="wide" height="tall"` |
| Extreme rotation | `rotation=999` |
| Parent cycle | Cell `a parent="b"` and `b parent="a"` |

Therefore:

- No validator block is not a visual-quality signal.
- Geometry must be finite numeric values.
- Vertex width/height must be strictly positive.
- Parent graph must be acyclic.
- Shape identifiers must come from live search/reference or a previously rendered native primitive.
- Negative coordinates may be intentional in generic Draw.io XML, nhưng production diagrams phải giữ final absolute bounds trong page được yêu cầu.

---

# 34. Visual-impact master contract

Section này là condensed execution contract generic cho visual work bằng Draw.io MCP hiện tại.

## 34.1 Capability confidence levels

| Capability | Confidence | Evidence | Production decision |
|---|---|---|---|
| Single-page XML cells/shapes/edges | Verified | Live fixtures + viewer source | Use |
| Vietnamese text/HTML labels | Accepted; visual QA required | Live fixtures | Use Arial, wrap and inspect |
| Flat swimlanes with relative children | Verified at call path and source model | Live fixture + XML decoder | Use |
| DFD generic primitives | Verified | Live search + fixtures | Use |
| Document/manual input/terminator | Verified | Live search + fixtures | Use exact current styles |
| Multiple documents | Composite only | Search has no native result; composite fixture accepted | Use stacked native documents and inspect |
| Computer pictogram | Remote image | Live search + fixture; CSP allows host | Use only when required; verify network render |
| A4 fields in canonical XML | Source-backed | XSD/reference + server echo | Keep in canonical source |
| A4/page-bound preview | Not supported | Viewer imports cells only and fits content | Use external page-aware render |
| Multi-page `<mxfile>` preview | Not supported | Viewer root guard | Call each page separately |
| ELK vertical/horizontal | Source-backed + call accepted | Viewer/ELK bundle + fixture | Only non-container hierarchy |
| Libavoid routing | Source-backed + call accepted | Viewer/routing source + fixture | Hand-placed single-page diagrams only |
| Persist ELK/libavoid result through agent | Not supported | No `currentXml` readback/save tool | User Copy/Open or avoid relying on pass |
| Automatic visual QA | Not supported | No screenshot/geometry/overlap/crossing tool | External render + vision/manual review |

## 34.2 Exact routing decision

Use no post-pass when:

- Layout is already sparse and orthogonal edges have clear corridors.
- Canonical local XML must exactly match preview without user Copy/Open.
- Manual waypoints are deliberately specified.

Use `routing:"libavoid"` when:

- Node positions must stay fixed.
- All important edges may become square-corner orthogonal.
- A 16 px obstacle buffer and 14 px parallel nudge are acceptable.
- Final routed XML will be persisted through viewer Copy/Open, hoặc routing is preview-only.

Use `postLayout:"elk"` when:

- Diagram is a single-page non-container hierarchy.
- Replacing every vertex position is acceptable.
- 30 px default spacing and forced model order are acceptable.
- Orthogonal rounded edges are acceptable.

Do not use ELK for document flowcharts with department swimlanes. Do not use libavoid for curves/elbows that must remain visually distinct.

## 34.3 Exact connector rules for high-quality diagrams

```text
source and target: stable cell IDs
edge parent: default layer for cross-lane/container edges
base style: edgeStyle=orthogonalEdgeStyle
arrow: endArrow=classic;endFill=1
edge geometry: expanded mxGeometry relative=1
fixed right exit: exitX=1;exitY=0.5
fixed left entry: entryX=0;entryY=0.5
label: short value + white labelBackgroundColor when crossing lines
```

For libavoid, always specify both X and Y for a fixed endpoint. Do not rely on `portConstraint`.

## 34.4 Canonical-source rule

The canonical diagram must remain outside MCP as one complete `<mxGraphModel>` per page. MCP is a renderer/preview call, not the source-of-truth store.

Required canonical checks before each call:

```text
unique IDs
existing parents
acyclic parent hierarchy
existing edge terminals
expanded edge geometry
finite numeric geometry
positive vertex dimensions
relative child coordinates
page-aware absolute bounds
escaped XML/HTML
known shape styles
```

After MCP preview:

```text
inspect content appearance
inspect text wrapping
inspect lane containment
inspect connector/node collisions
inspect edge labels
inspect remote images
```

Separately, with a page-aware external render/editor:

```text
inspect A4 boundary
inspect page overflow
persist or export canonical XML
verify final SVG/PDF/image
```

## 34.5 Remaining hard boundary

No further MCP inspection can provide:

- Screenshot pixels visible to the agent.
- Final ELK coordinates.
- Final libavoid waypoints.
- Viewer `currentXml`.
- Page-aware preview.
- Overlap/crossing/text-overflow report.
- Local `.drawio` save or export.

Those are not unaudited mysteries; they are absent capabilities proven by discovery and viewer implementation. Mastery of this MCP therefore means using its verified single-page rendering/routing contract while moving persistence, page-bound QA and pixel inspection to an external pipeline.

---

# 35. Information-source and caller-input boundary

Section này xác định chính xác thông tin nào có thể lấy từ Draw.io MCP và thông tin nào phải đến từ caller hoặc external tooling. Nó không phụ thuộc một bài tập hay repository cụ thể.

## 35.1 Directly obtainable from the MCP endpoint

Các thông tin sau lấy trực tiếp bằng MCP protocol hoặc tool call:

| Information | Exact MCP mechanism |
|---|---|
| Server name/version/protocol/capabilities | `initialize` |
| Tool inventory | `tools/list` |
| Exact tool descriptions | `tools/list` |
| Tool input schemas, required fields, enums and annotations | `tools/list` |
| Resource inventory and metadata | `resources/list` |
| Viewer resource content | `resources/read` |
| Resource templates | `resources/templates/list` |
| Prompt availability | Server capability + `prompts/list` behavior |
| Tool success/error payloads | `tools/call` |
| XML validator Errors/Warnings | `create_diagram(xml=...)` result blocks |
| Current server build ID | `create_diagram` result `_buildId` |
| Shape candidates for a supplied concept query | `search_shapes(query, limit)` |
| Interactive single-page preview | `create_diagram` |
| ELK/libavoid option acceptance | `create_diagram` arguments and result |

Current build exposes no additional tool, resource template or prompt from which more generic diagram data can be retrieved.

## 35.2 Derivable from the MCP viewer resource

Các thông tin sau không phải dedicated tool output, nhưng có thể xác định bằng cách inspect resource mà MCP expose:

- Viewer import root requirements.
- Single-page versus multi-page behavior.
- Streaming/healing/merge behavior.
- Viewer read-only state and controls.
- Content-fit camera behavior.
- `currentXml`, Copy XML and Open-in-Draw.io behavior.
- ELK invocation and serialization path.
- Libavoid invocation, obstacle extraction, route writing and style rewriting.
- Remote image URL rewriting.
- CSP/network hosts.
- CDN script URLs.

Các CDN bundle được chính MCP resource tham chiếu có thể được inspect để xác định:

- Exact ELK defaults/presets.
- Exact libavoid clearance/nudging defaults.
- Shared routing-core behavior.
- Runtime bundle fingerprints.

Đây là implementation-derived evidence. Nó có thể thay đổi mà không đổi public schema, nên phải re-audit khi resource hoặc bundle fingerprint drift.

## 35.3 Query-dependent information

`search_shapes` không expose:

- `list_all_shapes`.
- Shape-library enumeration.
- Stable library catalog resource.
- Query-independent dump của khoảng 10.000 stencils.

Nó chỉ trả candidates cho một `query` cụ thể. Vì vậy:

```text
caller supplies semantic concept
→ search_shapes finds candidates
→ caller/agent selects a result by title, style and dimensions
→ create_diagram verifies call/render path
```

Không thể lấy “toàn bộ mọi shape” từ MCP contract hiện tại mà không tự phát minh một tập query vô hạn. Báo cáo chỉ được phép gọi một shape “discovered” khi exact result đã xuất hiện từ live search hoặc exact server-linked reference.

## 35.4 Information the caller must supply

Draw.io MCP không biết mục đích của diagram. Caller phải cung cấp trực tiếp hoặc cho phép agent đưa ra assumption về:

| Required context | Examples |
|---|---|
| Diagram content | Actors, processes, data, documents, systems, relationships |
| Diagram type/notation | Flowchart, DFD, UML, architecture, Gane-Sarson, Yourdon/DeMarco |
| Label language and wording | English, Vietnamese, exact terminology |
| Semantic direction | Who sends what to whom; source → target |
| Required grouping | Lanes, departments, phases, containers, layers |
| Layout intent | Top-down, left-to-right, hand-placed, hierarchical |
| Page intent | A4/custom, portrait/landscape, one page or several independent pages |
| Visual requirements | Font, colors, line semantics, density, whitespace, brand rules |
| Required pictograms/assets | Logos, computer/device icons, supplied SVG/PNG assets |
| Existing diagram source | Raw XML content if an existing diagram must be reproduced or changed |
| Deliverables | `.drawio`, SVG, PNG, PDF, Markdown embed, preview only |
| Persistence target | File name, output directory, overwrite/versioning rules |
| Acceptance criteria | Reference image, rubric, maximum crossings, required page fit |

Nếu caller không cung cấp một mục và nó ảnh hưởng material đến output, agent phải hỏi hoặc nêu assumption. MCP không thể tự trả lời những câu hỏi này.

## 35.5 Information requiring external tooling

Các capability sau không thể lấy từ caller text hoặc MCP contract alone; chúng cần một tool/pipeline ngoài Draw.io MCP:

| Needed information/action | Required external capability |
|---|---|
| Read existing local `.drawio` by path | Filesystem read |
| Write canonical `.drawio` | Filesystem write |
| Render page-aware SVG/PNG/PDF | Draw.io editor/CLI or compatible renderer |
| Screenshot preview for agent vision | Browser/screenshot capability |
| Inspect pixel-level text overflow | Render + vision/manual inspection |
| Validate A4/page overflow | Page-aware render/geometry checker |
| Detect connector crossings/shape overlaps | Geometry analysis or render + vision |
| Read final ELK coordinates/libavoid waypoints | Viewer `currentXml` readback, which current MCP does not expose |
| Persist ELK/libavoid-transformed XML | Viewer Copy/Open or another renderer/editor integration |
| Verify font availability/fallback | Target renderer/browser inspection |
| Export with DPI, scale or embedded fonts | Export-capable renderer |

These are external dependencies, not missing caller instructions.

## 35.6 Minimum caller package for deterministic execution

Để agent tạo diagram mà không phải đoán material requirements, caller package tối thiểu nên gồm:

```text
diagram content
diagram type or notation
label language
required grouping
flow direction or layout intent
page/orientation requirement
visual constraints or reference
deliverable formats and target paths
```

Nếu cần sửa một diagram có sẵn, caller còn phải cung cấp raw XML/file access. Nếu cần kết quả đã post-layout/routed được lưu tự động, environment phải bổ sung readback/save/export tooling; Draw.io MCP hiện tại không làm được.
