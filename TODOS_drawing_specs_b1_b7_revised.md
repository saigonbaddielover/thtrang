# Execution specification — Draw.io MCP cho các bài lưu đồ / DFD

> **Mục tiêu:** đây là specification cuối để Codex vẽ đúng các phần sơ đồ của đề bằng Draw.io MCP hiện tại.
>
> **Nguồn sự thật nghiệp vụ:** đề bài.
>
> **Nguồn sự thật kỹ thuật:** audit live của Draw.io MCP ngày 2026-08-07.
>
> **Nguyên tắc cao nhất:** đề yêu cầu gì thì chỉ vẽ đúng cái đó. Không tự thêm loại sơ đồ, cấp sơ đồ, actor, chứng từ, data store, phê duyệt, nghiệp vụ hoặc luồng dữ liệu không có căn cứ.

---

# 0. Contract Draw.io MCP phải hiểu trước khi làm

## 0.1. MCP hiện tại chỉ có hai tool

Codex phải dùng đúng:

```text
mcp__drawio__create_diagram
mcp__drawio__search_shapes
```

Không được giả định có các tool như:

```text
open_file
add_node
update_edge
save
export_svg
export_png
export_pdf
```

Các tool đó **không tồn tại** trên endpoint hiện tại.

## 0.2. Cách MCP thực sự hoạt động

`mcp__drawio__create_diagram` nhận **toàn bộ diagram** trong một call:

```text
xml=<complete single-page mxGraphModel>
```

hoặc Mermaid.

Đối với toàn bộ bài tập trong file này:

- **dùng XML**;
- **không dùng Mermaid**.

Lý do:

- cần swimlane;
- cần document symbol;
- cần DFD primitives;
- cần geometry cụ thể;
- cần kiểm soát connector;
- Mermaid không có DFD notation phù hợp.

## 0.3. Mỗi preview chỉ gửi một `<mxGraphModel>`

Mỗi call MCP:

```xml
<mxGraphModel ...>
  <root>
    ...
  </root>
</mxGraphModel>
```

Không gửi `<mxfile>` nhiều page vào `create_diagram`.

Viewer hiện tại không render multi-page `<mxfile>` đúng.

## 0.4. Canonical source phải nằm ngoài MCP

MCP không save file.

Codex phải giữ **canonical XML source** bằng filesystem/repository tooling của chính Codex.

Khuyến nghị:

```text
drawio-src/
  01_payroll_system_flow.xml
  02_payroll_payment_flow.xml
  03_payroll_payment_dfd.xml
  04_fresh_fruit_dfd.xml
  05_fresh_fruit_flow.xml
  06_purchase_context_dfd.xml
  07_purchase_level0_dfd.xml
  08_material_document_flow.xml
  09_sales_context_dfd.xml
  10_sales_level0_dfd.xml
  11_sales_flow.xml
```

Có **11 diagram unique**.

Bài #5 dùng lại chính xác:

```text
04_fresh_fruit_dfd.xml
```

Không tạo DFD Fresh Fruit thứ hai có logic khác.

## 0.5. Nếu cần file `.drawio`

Sau khi từng page đã đúng, có thể assemble local source thành:

```xml
<mxfile compressed="false">
  <diagram id="..." name="...">
    <mxGraphModel>...</mxGraphModel>
  </diagram>
  ...
</mxfile>
```

Việc assemble/write file dùng filesystem tool của Codex, **không phải Draw.io MCP**.

Không gửi full multi-page `<mxfile>` này lại cho MCP để preview.

## 0.6. Save/export không thuộc MCP

Draw.io MCP hiện tại không có:

- save `.drawio`;
- SVG export;
- PNG export;
- PDF export;
- screenshot;
- page-bound validation.

Nếu environment có external Draw.io CLI/browser/render pipeline thì dùng pipeline đó sau khi source đã pass MCP preview.

Nếu environment không có external export pipeline:

- không được tuyên bố đã export;
- không được tuyên bố đã kiểm tra A4 boundary bằng MCP preview;
- phải báo rõ phần nào chưa thể verify.

---

# 1. Drift check trước khi vẽ

Audit snapshot hiện tại:

```text
MCP alias: drawio
Endpoint: https://mcp.draw.io/mcp
Server: drawio-mcp-app
Version: 1.0.0
Build: 42835e3@2026-08-02T20:17:10.515Z
```

Trước khi dùng các exact style trong spec này:

1. Check server/build hiện tại.
2. Nếu build vẫn là `42835e3...`, dùng các style đã audit bên dưới.
3. Nếu build thay đổi:
   - refresh tool schema;
   - chạy lại `search_shapes` cho các semantic shape cần dùng;
   - không mặc định style cũ vẫn đúng.

---

# 2. Page contract

## 2.1. A4 portrait mặc định

Canonical XML:

```xml
<mxGraphModel
  grid="1"
  gridSize="10"
  guides="1"
  tooltips="1"
  connect="1"
  arrows="1"
  fold="1"
  page="1"
  pageScale="1"
  pageWidth="827"
  pageHeight="1169"
  math="0"
  shadow="0">
```

Mapping:

```text
A4 portrait 210 × 297 mm
→ 827 × 1169 Draw.io model units
```

## 2.2. A4 landscape fallback

Chỉ dùng khi portrait đã tối ưu nhưng không đủ:

```xml
pageWidth="1169"
pageHeight="827"
```

Mapping:

```text
A4 landscape 297 × 210 mm
→ 1169 × 827
```

## 2.3. MCP preview không chứng minh page fit

Viewer MCP fit theo content bounds, không theo A4 frame.

Do đó:

- pageWidth/pageHeight vẫn phải có trong canonical XML;
- page overflow phải kiểm tra bằng external page-aware render/editor;
- không được nói “đã vừa A4” chỉ vì viewer MCP nhìn gọn.

---

# 3. Structural XML bắt buộc

Mỗi diagram:

```xml
<mxGraphModel ...>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>

    <!-- KHÔNG chèn XML comment thật vào production source -->

    ...
  </root>
</mxGraphModel>
```

**Production XML không được có XML comment.**

Mọi ID:

- unique trong page;
- client-defined;
- ổn định giữa các lần sửa.

ID convention:

```text
ln_*   lane
n_*    normal node/process/document
d_*    DFD data store
x_*    DFD external entity
p_*    DFD process
e_*    edge
a_*    annotation/note
```

Mọi edge phải có:

```xml
<mxGeometry relative="1" as="geometry"/>
```

Không self-close edge.

---

# 4. Exact style presets

Codex nên dùng nhất quán các preset này.

## 4.1. Flowchart lane

Cột dọc với header phía trên:

```text
swimlane;
horizontal=1;
startSize=32;
html=1;
whiteSpace=wrap;
fontFamily=Arial;
fontSize=12;
fontStyle=1;
collapsible=0;
recursiveResize=0;
rounded=0;
```

Child node dùng:

```text
parent="<lane-id>"
```

Cross-lane edge dùng:

```text
parent="1"
```

## 4.2. Flowchart process/activity

```text
rounded=1;
html=1;
whiteSpace=wrap;
fontFamily=Arial;
fontSize=11;
align=center;
verticalAlign=middle;
spacing=4;
```

Không dùng diamond nếu đề không có decision thật.

## 4.3. Document

Exact style đã được live search:

```text
strokeWidth=2;
html=1;
shape=mxgraph.flowchart.document2;
whiteSpace=wrap;
size=0.25;
fontFamily=Arial;
fontSize=11;
align=center;
verticalAlign=middle;
spacing=3;
```

Chứng từ 2/3 liên:

- ưu tiên **một document node** ghi rõ `(2 liên)` hoặc `(3 liên)`;
- sau node đó tách connector và label `Liên 1`, `Liên 2`, `Liên 3`.

Không cần dựng composite multiple-document nếu không tăng thông tin.

## 4.4. Paper/document archive

Dùng:

```text
shape=mxgraph.dfd.archive;
html=1;
whiteSpace=wrap;
fontFamily=Arial;
fontSize=11;
```

Chỉ dùng cho nơi lưu hồ sơ/chứng từ giấy.

## 4.4A. System stored data / ledger

Dùng cho sổ/dữ liệu được chương trình hoặc kế toán cập nhật, không phải hồ sơ giấy:

```text
shape=mxgraph.flowchart.stored_data;
html=1;
whiteSpace=wrap;
fontFamily=Arial;
fontSize=10.5;
align=center;
verticalAlign=middle;
spacing=3;
```

Ví dụ:

```text
Sổ chi tiết phải thu khách hàng
Dữ liệu doanh thu
Dữ liệu nợ phải thu
Dữ liệu hàng tồn kho
Dữ liệu theo dõi bán hàng
```

Không dùng `archive` cho các dữ liệu/sổ này nếu mục đích là thể hiện dữ liệu được cập nhật trong hệ thống.

## 4.5. DFD external entity

```text
html=1;
dashed=0;
whiteSpace=wrap;
fontFamily=Arial;
fontSize=11;
align=center;
verticalAlign=middle;
```

Geometry đề xuất:

```text
130 × 55
```

## 4.6. DFD process

Dùng một notation nhất quán cho toàn bộ bài:

```text
shape=ellipse;
html=1;
dashed=0;
whiteSpace=wrap;
perimeter=ellipsePerimeter;
fontFamily=Arial;
fontSize=11;
align=center;
verticalAlign=middle;
spacing=4;
```

Geometry đề xuất:

```text
150 × 70
```

Không gọi notation này là Gane-Sarson hoặc Yourdon/DeMarco vì MCP audit không xác nhận named library.

## 4.7. DFD data store

```text
html=1;
dashed=0;
whiteSpace=wrap;
shape=partialRectangle;
right=0;
left=0;
fontFamily=Arial;
fontSize=10;
align=left;
verticalAlign=middle;
spacingLeft=6;
```

Geometry đề xuất:

```text
160 × 42
```

## 4.8. Standard connector

Base style:

```text
edgeStyle=orthogonalEdgeStyle;
rounded=0;
html=1;
endArrow=classic;
endFill=1;
fontFamily=Arial;
fontSize=10;
labelBackgroundColor=#FFFFFF;
jettySize=auto;
```

Khi cần ép source đi ra cạnh phải:

```text
exitX=1;
exitY=0.5;
```

Khi cần ép target đi vào cạnh trái:

```text
entryX=0;
entryY=0.5;
```

Các side chuẩn:

```text
left   = x=0,   y=0.5
right  = x=1,   y=0.5
top    = x=0.5, y=0
bottom = x=0.5, y=1
```

Không chỉ set một trong X/Y.

---

# 5. Routing policy

## 5.1. Không dùng ELK cho các bài này mặc định

Không dùng:

```text
postLayout="elk"
```

cho các lưu đồ swimlane.

Đối với DFD trong bộ bài này, cũng ưu tiên hand-place để:

- giữ A4;
- giữ layout ổn định;
- kiểm soát direction;
- không phụ thuộc geometry post-layout mà MCP không readback được.

## 5.2. Canonical XML không phụ thuộc libavoid

Canonical source phải tự có:

- vị trí node hợp lý;
- `orthogonalEdgeStyle`;
- entry/exit side hợp lý;
- corridor đủ rộng.

`routing:"libavoid"` chỉ được dùng như **preview aid** khi muốn xem obstacle routing.

Nếu gọi:

```text
mcp__drawio__create_diagram(
  xml=<canonical XML>,
  routing="libavoid"
)
```

phải nhớ:

- libavoid sửa route trong viewer;
- MCP không trả final waypoints/currentXml;
- canonical XML local không tự nhận route đó.

Vì vậy **không được coi libavoid result là persisted source**.

## 5.3. Manual waypoint

Không dùng trong normal path.

Chỉ dùng khi:

- không dùng ELK;
- không dùng libavoid;
- một edge thật sự không thể route sạch chỉ bằng node placement + entry/exit side.

Nếu phải dùng:

```xml
<mxGeometry relative="1" as="geometry">
  <Array as="points">
    <mxPoint x="..." y="..."/>
  </Array>
</mxGeometry>
```

Phải visual QA kỹ.

---

# 5A. Local preflight bắt buộc trước mọi MCP call

`create_diagram` không phải XML/XSD/geometry validator đầy đủ. Vì vậy **không được dùng MCP success làm bằng chứng source hợp lệ**.

Trước mỗi `mcp__drawio__create_diagram`, Codex phải chạy local validation trên canonical XML.

## 5A.1. XML parse

Phải parse được bằng XML parser thật.

Fail ngay nếu:

- malformed XML;
- duplicate attribute;
- unescaped XML character;
- broken nesting.

Không dựa vào regex validator của MCP.

## 5A.2. Structural validation

Tự kiểm tra bằng script:

```text
all cell IDs unique
id=0 exists
id=1 parent=0 exists
all parents exist
parent graph acyclic
all edge source IDs exist
all edge target IDs exist
all edges have expanded mxGeometry relative=1
```

## 5A.3. Geometry validation

Với mọi vertex:

```text
x, y, width, height are finite numbers
width > 0
height > 0
```

Với child trong lane:

- tính absolute bounds bằng cách cộng geometry với parent;
- child phải nằm trong vùng usable của lane;
- không để child chạm header lane.

## 5A.4. Canonical page-bound validation

Vì MCP preview không hiển thị A4 boundary đáng tin cậy, local script phải kiểm tra **absolute geometry bounds** trước:

Portrait:

```text
0 <= left
0 <= top
right <= 827
bottom <= 1169
```

Landscape:

```text
0 <= left
0 <= top
right <= 1169
bottom <= 827
```

Dành safe margin tối thiểu:

```text
20 model units
```

Nghĩa là production target nên nằm trong:

Portrait:

```text
20 <= left/top
right <= 807
bottom <= 1149
```

Landscape:

```text
20 <= left/top
right <= 1149
bottom <= 807
```

Edge path thực tế vẫn phải kiểm tra bằng external render vì orthogonal routing có thể vượt node bounds.

## 5A.5. Known-style validation

Mọi semantic shape phải:

- nằm trong exact preset của spec này; hoặc
- là exact style vừa lấy từ `search_shapes`.

Không dùng unknown `shape=` key.

## 5A.6. Text-density precheck

Trước render:

- font node chính không dưới `10.5–11`;
- edge label không dưới `9.5–10`;
- document/process label dự kiến không quá 3–4 dòng;
- nếu phải wrap quá nhiều → tăng node hoặc đổi landscape;
- không giải quyết bằng giảm font cực nhỏ.

Nếu bất kỳ preflight check nào fail, **không gọi MCP** cho tới khi canonical XML được sửa.

---

# 6. MCP invocation recipe cho mỗi diagram

## Pass A — structural preview

```text
mcp__drawio__create_diagram
xml=<complete mxGraphModel>
```

Mục tiêu:

- validator không báo duplicate ID;
- không dangling source/target;
- không missing parent;
- không missing edge geometry;
- viewer render được.

## Pass B — optional routing preview

Chỉ nếu connector còn khó đọc:

```text
mcp__drawio__create_diagram
xml=<same canonical mxGraphModel>
routing="libavoid"
```

Dùng để đánh giá xem geometry/lane order có hợp lý không.

Không copy route ngầm từ viewer vào assumption.

## Pass C — sửa canonical XML

Nếu preview xấu:

- sửa x/y/width/height;
- đổi lane width;
- đổi node row;
- đổi source/target side;
- đổi edge order;
- submit full XML lại.

Không edit incremental vì MCP không support.

---

# 7. External QA / persistence pipeline

Sau khi MCP preview hợp lý:

```text
canonical mxGraphModel
→ filesystem save
→ external Draw.io/editor/CLI page-aware render
→ SVG/PNG/PDF
→ vision/manual QA
→ patch canonical XML
→ MCP preview lại nếu cần
→ external render lại
```

QA bắt buộc:

- shape overlap;
- text overflow;
- connector crossing;
- connector xuyên node;
- arrow direction;
- dangling connector;
- lane overflow;
- page overflow;
- clipped text;
- số liên chứng từ;
- đúng source/target;
- đúng A4 orientation.

Nếu không có external render:

- ghi `Skipped`;
- không claim page-bound hoặc pixel QA đã pass.

---

# 8. Page geometry templates

## 8.1. Portrait — 4 lanes

```text
page: 827 × 1169
lane y: 20
lane h: 1100
lane width: 190

lane 1 x=20
lane 2 x=210
lane 3 x=400
lane 4 x=590
```

Child node trong lane:

```text
x=15
width=160
```

## 8.2. Portrait — 5 lanes

```text
lane y: 20
lane h: 1100
lane width: 150

x:
20
170
320
470
620
```

Child:

```text
x=12
width=126
```

Nếu label phải wrap quá 3 dòng ở font 11 hoặc node cao bất thường → landscape.

## 8.3. Portrait — 6 lanes

```text
lane width: 125
x:
20
145
270
395
520
645
```

Chỉ dùng nếu vẫn đọc rõ.

Nếu không, chuyển landscape.

## 8.4. Landscape — 6 lanes

```text
page: 1169 × 827
lane y: 20
lane h: 760
lane width: 180

x:
25
205
385
565
745
925
```

Child:

```text
x=15
width=150
```

## 8.5. Row spacing

Flowchart child rows:

```text
row 1 y=55
row 2 y=145
row 3 y=235
row 4 y=325
row 5 y=415
row 6 y=505
row 7 y=595
row 8 y=685
row 9 y=775
row 10 y=865
row 11 y=955
```

Node height mặc định:

```text
process: 58–68
document: 64–72
archive: 60
```

Tăng height khi text cần, không giảm font dưới 10.5–11 để ép vừa trang.

---

# 9. #1 — Bài 1 — Lưu đồ hệ thống tiền lương

## 9.1. Output

Chỉ:

```text
01_payroll_system_flow.xml
```

Không vẽ DFD.

## 9.2. Page

Bắt đầu:

```text
A4 portrait
4 lanes
```

Lane:

```text
ln_bpsd  Bộ phận sử dụng lao động
ln_kttl  Kế toán tiền lương
ln_ktt   Kế toán trưởng
ln_nld   Người lao động
```

## 9.3. Node table

| ID | Parent | Type | Label | Row |
|---|---|---|---|---:|
| n_bcc | ln_bpsd | document | Bảng chấm công | 1 |
| n_receive_bcc | ln_kttl | process | Nhận bảng chấm công | 1 |
| n_calc | ln_kttl | process | Tính lương bằng phần mềm | 2 |
| n_btl | ln_kttl | document | Bảng tính lương | 3 |
| n_pc | ln_kttl | document | Phiếu chi tiền mặt (2 liên) | 4 |
| n_approve | ln_ktt | process | Ký duyệt phiếu chi | 4 |
| n_receive_cash | ln_kttl | process | Nhận tiền | 5 |
| n_pay | ln_kttl | process | Phát tiền lương | 6 |
| n_worker_receive | ln_nld | process | Nhận tiền lương | 6 |
| n_archive | ln_kttl | archive | Lưu Phiếu chi + Bảng tính lương + Bảng chấm công | 8 |

Không thêm:

```text
Thủ quỹ
Ngân hàng
Nguồn tiền
```

vì đề không xác định.

Không ghi `Bộ phận sử dụng lao động lập BCC`; chỉ thể hiện họ **chuyển** BCC.

## 9.4. Edge table

| ID | Source | Target | Label | Exit | Entry |
|---|---|---|---|---|---|
| e01 | n_bcc | n_receive_bcc | Bảng chấm công | right | left |
| e02 | n_receive_bcc | n_calc |  | bottom | top |
| e03 | n_calc | n_btl |  | bottom | top |
| e04 | n_btl | n_pc |  | bottom | top |
| e05 | n_pc | n_approve | Phiếu chi 2 liên | right | left |
| e06 | n_approve | n_receive_cash | Phiếu chi đã ký duyệt | left | right |
| e07 | n_receive_cash | n_pay |  | bottom | top |
| e08 | n_pay | n_worker_receive | Tiền lương | right | left |
| e09 | n_pay | n_archive | Phiếu chi + Bảng tính lương + Bảng chấm công | bottom | top |

Để thể hiện 3 chứng từ được lưu, label archive phải ghi đủ:

```text
Phiếu chi
Bảng tính lương
Bảng chấm công
```

Không cần kéo ba đường dài riêng nếu làm sơ đồ rối; có thể dùng một connector từ bước hoàn tất tới archive và label archive ghi đủ bộ hồ sơ.

## 9.5. Routing

- Không ELK.
- Canonical edges orthogonal.
- Không cần libavoid nếu các lane/node đặt đúng.
- e05/e06 phải tách cao độ hoặc entry side để không chồng nhau.

---

# 10. #1 — Bài 2 — Lưu đồ thanh toán tiền lương

## 10.1. Output

```text
02_payroll_payment_flow.xml
```

## 10.2. Page

Bắt đầu:

```text
A4 portrait
5 lanes
```

Lane:

```text
ln_time   Bộ phận chấm công
ln_emp    Nhân viên
ln_pay    Kế toán tiền lương
ln_chief  Kế toán trưởng
ln_dir    Giám đốc
```

Nếu portrait làm node width < 120 và text wrap quá mức → landscape.

## 10.3. BCCLTG — quy tắc bắt buộc

Đề nói kế toán tiền lương **nhận** BCCLTG nếu có nhưng không nói ai lập/chuyển.

Do đó:

- không tạo actor nguồn;
- không nối từ `Bộ phận chấm công` nếu đề không nói;
- đặt document node trong lane `Kế toán tiền lương`:

```text
n_ot = Bảng chấm công làm thêm giờ (nếu có)
```

và annotation nhỏ:

```text
Nguồn không xác định trong đề
```

Annotation không phải actor, không tạo data flow giả.

## 10.4. Node table

| ID | Parent | Type | Label | Row |
|---|---|---|---|---:|
| n_daily | ln_time | process | Chấm công hàng ngày | 1 |
| n_bcc | ln_time | document | Bảng chấm công cuối tháng | 2 |
| n_confirm | ln_emp | process | Xác nhận bảng chấm công | 2 |
| n_receive | ln_pay | process | Nhận BCC đã xác nhận | 3 |
| n_ot | ln_pay | document | BCC làm thêm giờ (nếu có) | 2 |
| a_ot | ln_pay | note | Nguồn BCCLTG không xác định trong đề | 1 |
| n_bttl | ln_pay | document | Bảng thanh toán tiền lương (2 liên) | 4 |
| n_emp_copy | ln_emp | document | BTTL liên 2 | 4 |
| n_check | ln_chief | process | Kiểm tra và xác nhận | 5 |
| n_sign | ln_dir | process | Ký BTTL | 6 |
| n_pay_cash | ln_pay | process | Trả lương cho nhân viên | 7 |
| n_emp_receive | ln_emp | process | Nhận lương tiền mặt và ký xác nhận | 7 |
| n_archive | ln_pay | archive | Lưu BCC + BCCLTG (nếu có) + BTTL + xác nhận nhận lương | 9 |

## 10.5. Edge table

1. `n_daily → n_bcc`
2. `n_bcc → n_confirm` label `BCC`
3. `n_confirm → n_receive` label `BCC đã xác nhận`
4. `n_receive → n_bttl`
5. `n_ot → n_bttl` label `Nếu có`
6. `n_bttl → n_emp_copy` label `Liên 2`
7. `n_bttl → n_check` label `Liên 1 + chứng từ liên quan`
8. `n_check → n_sign` label `BTTL đã phê duyệt`
9. `n_sign → n_pay_cash` label `BTTL đã ký`
10. `n_pay_cash → n_emp_receive`
11. `n_emp_receive → n_archive` label `Xác nhận đã nhận lương`
12. `n_pay_cash → n_archive` label `BCC + BCCLTG (nếu có) + BTTL`

Không tạo decision diamond `Có làm thêm?`.

---

# 11. #1 — Bài 2 — Sơ đồ dòng dữ liệu

## 11.1. Output

```text
03_payroll_payment_dfd.xml
```

Chỉ **một DFD**.

Không tự thêm context + level 0 thứ hai.

## 11.2. Notation

Dùng:

```text
external entity = rectangle
process = ellipse
data store = partialRectangle
```

Không gọi notation bằng tên framework không được đề yêu cầu.

## 11.3. Boundary

Boundary được khóa là **phần xử lý thanh toán tiền lương do kế toán tiền lương thực hiện**.

External entity:

```text
x_time    Bộ phận chấm công
x_emp     Nhân viên
x_chief   Kế toán trưởng
x_dir     Giám đốc
```

Không tạo `Kế toán tiền lương` thành external entity vì các process bên trong đại diện cho hoạt động của kế toán tiền lương.

Quan trọng:

- Việc `Nhân viên xác nhận BCC` diễn ra **trước khi BCC được chuyển cho kế toán tiền lương** theo narrative.
- Vì vậy không tạo process nội bộ để gửi BCC sang nhân viên rồi nhận ngược lại.
- DFD bắt đầu bằng dữ liệu `BCC đã xác nhận` đi từ `Bộ phận chấm công` vào hệ thống.

## 11.4. Process

```text
p1  Tiếp nhận chứng từ chấm công
p2  Lập bảng thanh toán tiền lương
p3  Xử lý luân chuyển phê duyệt BTTL
p4  Xử lý thanh toán lương
p5  Lưu chứng từ
```

`p3` chỉ đại diện cho việc hệ thống/kế toán tiền lương chuyển BTTL đi kiểm tra, nhận lại kết quả và chuyển tiếp cho giám đốc.

Không ghi `p3 = Kế toán trưởng phê duyệt` hoặc `Giám đốc ký` vì hai hành động đó thuộc external entity.

Không bắt buộc suffix `.0` vì đề không chỉ định cấp.

## 11.5. Data store

```text
d1  Hồ sơ chứng từ tiền lương
```

Không tự thêm database nhân sự.

## 11.6. BCCLTG

Đề xác nhận kế toán tiền lương nhận `BCCLTG` nếu có nhưng **không xác định nguồn**.

Không vẽ external entity giả.

Đặt annotation cạnh `p2`:

```text
Input bổ sung nếu có:
Bảng chấm công làm thêm giờ
Nguồn không xác định trong đề
```

Không vẽ mũi tên từ `Bộ phận chấm công` tới BCCLTG nếu đề không nói.

## 11.7. Data flow

1. `x_time → p1`: `BCC đã được nhân viên xác nhận`
2. `p1 → p2`: `BCC đã xác nhận`
3. `p2 → x_emp`: `BTTL liên 2`
4. `p2 → p3`: `BTTL liên 1 + chứng từ liên quan`
5. `p3 → x_chief`: `BTTL + chứng từ cần kiểm tra`
6. `x_chief → p3`: `BTTL đã phê duyệt`
7. `p3 → x_dir`: `BTTL đã phê duyệt cần ký`
8. `x_dir → p3`: `BTTL đã ký`
9. `p3 → p4`: `BTTL đã được kế toán trưởng phê duyệt và giám đốc ký`
10. `x_emp → p4`: `Xác nhận đã nhận lương`
11. `p4 → p5`: `Chứng từ thanh toán hoàn tất`
12. `p5 → d1`: `BCC + BCCLTG (nếu có) + BTTL + xác nhận nhận lương`

### Luồng vật lý không vẽ thành data flow

Đề nói kế toán lương trả lương tiền mặt và nhân viên nhận tiền.

Trong DFD:

- **không vẽ tiền mặt thành data flow/data store**;
- đặt note cạnh `p4`:

```text
Thanh toán tiền mặt cho nhân viên
(luồng vật lý; không biểu diễn như data flow)
```

Không tự tạo data flow `Thông tin thanh toán` hoặc `BTTL thanh toán` nếu đề không nêu.

## 11.8. Geometry gợi ý

Portrait:

```text
x_time  x=25  y=130
x_emp   x=650 y=300
x_chief x=650 y=500
x_dir   x=650 y=680

p1 x=245 y=120
p2 x=245 y=285
p3 x=245 y=485
p4 x=245 y=700
p5 x=245 y=875

d1 x=235 y=1020
```

Annotation BCCLTG đặt bên trái `p2`.

Annotation tiền mặt đặt bên phải `p4`, nhưng phải nằm ngoài corridor của edge `x_emp → p4`.

Không dùng libavoid để “cứu” layout nếu canonical geometry đang chật; ưu tiên sửa geometry trước.

# 12. #2 — Fresh Fruit — DFD

## 12.1. Output

```text
04_fresh_fruit_dfd.xml
```

Bài #5 dùng lại chính xác file này.

Không tạo DFD thứ hai.

## 12.2. External entity

```text
x_warehouse  Thủ kho
x_customer   Khách hàng
```

## 12.3. Process

```text
p1  Gửi hàng
p2  Lập hóa đơn
p3  Đối chiếu và ghi sổ phải thu
```

## 12.4. Data store

```text
d1  PXK lưu theo số thứ tự
d2  PGH lưu theo số thứ tự
d3  Sổ chi tiết phải thu khách hàng
d4  Chứng từ lưu theo tên khách hàng
```

## 12.5. Data flow

1. `x_warehouse → p1`: `Phiếu xuất kho`
2. `p1 → x_customer`: `PGH liên 1`
3. `p1 → p2`: `PGH liên 2`
4. `p1 → p3`: `PGH liên 3`
5. `p1 → d1`: `Phiếu xuất kho`
6. `p2 → x_customer`: `HĐ liên 1`
7. `p2 → p3`: `HĐ liên 2`
8. `p2 → d2`: `PGH`
9. `p3 → d3`: `Thông tin phải thu khách hàng`
10. `p3 → d4`: `PGH + HĐ đã đối chiếu`

Không vẽ:

```text
thu tiền
phiếu thu
ngân hàng
thủ quỹ
```

vì narrative không có.

## 12.6. Geometry gợi ý

Portrait, left-to-right:

```text
x_warehouse x=25  y=220
p1          x=200 y=210
p2          x=400 y=210
p3          x=400 y=470
x_customer  x=650 y=180

d1 x=180 y=390
d2 x=380 y=360
d3 x=380 y=650
d4 x=380 y=750
```

Tách `PGH liên 3` đi xuống p3 để không chồng `PGH liên 2`.

---

# 13. #2 — Fresh Fruit — Lưu đồ

## 13.1. Output

```text
05_fresh_fruit_flow.xml
```

## 13.2. Page/lane

Bắt đầu portrait, 5 lanes:

```text
ln_warehouse  Thủ kho
ln_shipping   Bộ phận gửi hàng
ln_billing    Bộ phận lập hóa đơn
ln_accounting Kế toán
ln_customer   Khách hàng
```

## 13.3. Node table

**Thủ kho**

```text
n_pxk  document  Phiếu xuất kho
```

**Bộ phận gửi hàng**

```text
n_receive_pxk process   Nhận PXK
n_pack        process   Đóng gói hàng
n_pgh         document  Phiếu gửi hàng (3 liên)
n_store_pxk   archive   Lưu PXK theo số thứ tự
```

**Bộ phận lập hóa đơn**

```text
n_receive_pgh process   Nhận PGH liên 2
n_invoice     document  Hóa đơn (2 liên)
n_store_pgh   archive   Lưu PGH theo số thứ tự
```

**Kế toán**

```text
n_receive_docs process      Nhận PGH liên 3 và HĐ liên 2
n_reconcile    process      Định kỳ đối chiếu PGH và HĐ
n_ar           process      Ghi sổ chi tiết phải thu khách hàng
n_ar_ledger    stored_data  Sổ chi tiết phải thu khách hàng
n_store_docs   archive      Lưu PGH + HĐ theo tên khách hàng
```

**Khách hàng**

```text
n_customer_pgh document PGH liên 1
n_customer_inv document HĐ liên 1
```

## 13.4. Edge semantics

- `PXK → shipping`
- shipping:
  - `PGH liên 1 → customer`
  - `PGH liên 2 → billing`
  - `PGH liên 3 → accounting`
  - `n_receive_pxk → n_store_pxk` label `PXK`; archive lineage must not originate from `n_pgh`
- billing:
  - `HĐ liên 1 → customer`
  - `HĐ liên 2 → accounting`
  - `n_receive_pgh → n_store_pgh` label `PGH`; archive lineage must not originate from `n_invoice`
- accounting:
  - PGH3 + HĐ2 hội tụ tại `n_receive_docs`
  - `n_receive_docs → n_reconcile`
  - từ `n_reconcile` tách thành hai kết quả:
    - `n_reconcile → n_ar → n_ar_ledger`
    - `n_reconcile → n_store_docs` label `PGH + HĐ đã đối chiếu`

Không nối hàng hóa vào accounting.

Có thể label edge tới customer:

```text
PGH liên 1 + hàng hóa
```

vì lưu đồ có thể thể hiện luồng vật lý.

## 13.5. Layout

Nếu portrait gây crossing giữa hai nhánh customer/accounting:

- giữ customer lane ngoài cùng phải;
- HĐ1 và PGH1 đi thẳng sang phải;
- PGH3/HĐ2 đi vào accounting ở giữa;
- không route vòng qua customer.

---

# 14. #3 — DFD tổng quát mua hàng và thanh toán

## 14.1. Output

```text
06_purchase_context_dfd.xml
```

## 14.2. Process duy nhất

```text
p0  Chu trình mua hàng và thanh toán
```

## 14.3. External entity

```text
x_requester  Bộ phận có nhu cầu mua hàng
x_leader     Lãnh đạo công ty
x_supplier   Nhà cung cấp
```

Không dùng `Bộ phận kho` làm external entity vì hoạt động kho nằm bên trong decomposition cấp 0.

## 14.4. Data flow

1. `x_requester → p0`: `Đơn đề nghị mua hàng`
2. `p0 → x_leader`: `Đơn đề nghị mua hàng cần phê duyệt`
3. `x_leader → p0`: `Đơn đề nghị mua hàng đã phê duyệt`
4. `p0 → x_supplier`: `Đơn đặt hàng`
5. `x_supplier → p0`: `Thông tin hàng giao`
6. `x_supplier → p0`: `Hóa đơn`
7. `p0 → x_supplier`: `Thông tin/kết quả thanh toán`

`Thông tin hàng giao` là abstraction dữ liệu của sự kiện trong đề: `Khi hàng hóa được chuyển đến`.

- Không vẽ bản thân hàng hóa vật lý như data flow.
- Không đổi tên abstraction này thành `Phiếu giao hàng`, `Biên bản giao hàng` hoặc chứng từ khác vì đề không nêu.

Không có data store trong context.

## 14.5. Geometry

```text
p0          x=315 y=380 w=200 h=100
x_requester x=40  y=220
x_leader    x=40  y=520
x_supplier  x=650 y=370
```

Hai luồng tới/về leader phải dùng top/bottom offset hoặc khác entry side để không chồng.

---

# 15. #3 — DFD chi tiết cấp 0

## 15.1. Output

```text
07_purchase_level0_dfd.xml
```

## 15.2. External entity

Giữ cân bằng:

```text
x_requester
x_leader
x_supplier
```

Không thêm warehouse external entity.

## 15.3. Process

```text
p1  Xử lý đề nghị mua hàng
p2  Lựa chọn nhà cung cấp và lập đơn đặt hàng
p3  Kiểm đếm, nhận và xác nhận hàng
p4  Đối chiếu chứng từ và ghi sổ mua hàng
p5  Xử lý thanh toán
```

## 15.4. Data store

```text
d1  ĐNMH liên 2 tại kế toán
d2  ĐĐH liên 1 lưu tại bộ phận mua hàng
d3  PNK liên 2 lưu tại kho
d4  Sổ mua hàng
```

## 15.5. Data flow

1. `x_requester → p1`: `ĐNMH 2 liên`
2. `p1 → x_leader`: `ĐNMH cần phê duyệt`
3. `x_leader → p1`: `ĐNMH đã phê duyệt`
4. `p1 → p2`: `ĐNMH liên 1 đã duyệt`
5. `p1 → d1`: `ĐNMH liên 2`
6. `p2 → x_supplier`: `ĐĐH liên 2`
7. `p2 → d2`: `ĐĐH liên 1`
8. `p2 → p4`: `ĐĐH liên 3`
9. `x_supplier → p3`: `Thông tin hàng giao`
10. `p3 → p4`: `PNK liên 1`
11. `p3 → d3`: `PNK liên 2`
12. `x_supplier → p4`: `Hóa đơn`
13. `d1 → p4`: `ĐNMH liên 2`
14. `p4 → d4`: `Thông tin ghi sổ mua hàng`
15. `p4 → p5`: `Thông tin cần thanh toán`
16. `p5 → x_supplier`: `Thông tin/kết quả thanh toán`

## 15.6. Process p3 và sự kiện hàng đến

Đề có sự kiện vật lý:

```text
hàng hóa được chuyển đến
```

DFD không biểu diễn bản thân hàng hóa vật lý.

Để `p3` không trở thành process tự sinh `PNK` mà không có input, dùng data flow trừu tượng:

```text
Nhà cung cấp → p3: Thông tin hàng giao
```

`Thông tin hàng giao` chỉ là abstraction của sự kiện có thật trong đề:

```text
Khi hàng hóa được chuyển đến
```

Không bịa:

```text
Phiếu giao hàng
Thông báo giao hàng
Biên bản giao hàng
```

vì đề không nêu các chứng từ đó.

Có thể đặt annotation cạnh p3:

```text
Bộ phận kho phối hợp bộ phận mua hàng
kiểm đếm, nhận và xác nhận khi hàng đến.
```

Annotation không thay data flow.

## 15.7. Cân bằng context ↔ level 0

Boundary flow phải giữ:

```text
Requester → system: ĐNMH
System ↔ Leader: approval
System → Supplier: ĐĐH
Supplier → System: Thông tin hàng giao
Supplier → System: Hóa đơn
System → Supplier: thanh toán
```

Không được xuất hiện boundary flow mới ở cấp 0.

## 15.8. Geometry

Nếu portrait:

```text
x_requester x=20  y=120
x_leader    x=20  y=360
x_supplier  x=655 y=330

p1 x=220 y=100
p2 x=220 y=280
p3 x=220 y=500
p4 x=430 y=410
p5 x=430 y=650

d1 x=30  y=650
d2 x=210 y=760
d3 x=210 y=850
d4 x=430 y=820
```

Nếu edge density quá lớn, chuyển landscape thay vì ép.

---

# 16. #4 — Lưu đồ tài liệu vật tư công trình

## 16.1. Output

```text
08_material_document_flow.xml
```

## 16.2. Lane

```text
Phòng thiết kế
Phòng dự án
Đội thi công
Thủ kho
Phòng vật tư
Kế toán
```

Có 6 lane.

**Thử portrait trước**, nhưng nếu node width thực tế < 110 hoặc text/edge rối thì chuyển page này sang landscape.

Không thêm `Nhà cung cấp`.

## 16.3. Exact nghiệp vụ

### Phòng thiết kế

```text
Bản vẽ công trình (3 bản)
├─ Bản 1 → lưu
├─ Bản 2 → Phòng dự án
└─ Bản 3 → Đội thi công
```

### Phòng dự án

Sau khi nhận bản vẽ:

```text
Lập dự toán công trình
Lập kế hoạch thi công từng giai đoạn
```

Luồng tài liệu dùng cách đọc bảo thủ theo hai câu liên tiếp của đề:

```text
Dự toán + Kế hoạch → Kế toán
Kế hoạch thi công → Đội thi công
```

Lý do: câu sau của đề xác định đội thi công `nhận bản vẽ công trình và kế hoạch thi công` trước khi lập đề nghị cấp vật tư.

Không ép `Dự toán → Đội thi công` khi đề không xác nhận lại tài liệu đó ở đầu vào của đội thi công.

### Đội thi công

Nhận:

```text
Bản vẽ
Kế hoạch thi công
```

Sau đó:

```text
Lập Đề nghị cấp vật tư
→ Thủ kho
```

Cuối quy trình nhận vật tư.

### Thủ kho

```text
Nhận Đề nghị cấp vật tư
→ Kiểm tra/đối chiếu tồn kho
→ Lập Đề nghị mua vật tư (2 liên)
   ├─ Liên 1 → lưu
   └─ Liên 2 → Phòng vật tư
```

Sau khi nhận vật tư từ phòng vật tư:

```text
Lập Phiếu nhập kho (2 liên)
├─ Liên 1 → lưu tại kho
└─ Liên 2 → Kế toán

Vật tư → Đội thi công
```

### Phòng vật tư

```text
Nhận Đề nghị mua vật tư liên 2
→ Mua vật tư theo kế hoạch
→ Nhận vật tư mua về
→ Lập Biên bản giao nhận

Hóa đơn
(nằm trong custody của Phòng vật tư;
nguồn lập/phát hành không nêu trong đề)
```

Sau đó:

```text
Biên bản giao nhận → Kế toán
Hóa đơn → Kế toán
Vật tư mua về → Thủ kho
```

`Hóa đơn` là document riêng nằm trong custody của Phòng vật tư trước khi được Phòng vật tư chuyển tới Kế toán. Đề không nêu nguồn lập/phát hành hóa đơn, nên diagram phải đặt annotation `Nguồn lập/phát hành không nêu trong đề` và không được nối process lập/phát hành nào vào document này.

### Kế toán

Nhận:

```text
Dự toán + Kế hoạch
Biên bản giao nhận + Hóa đơn
PNK liên 2
```

Sau đó:

```text
Đối chiếu Hóa đơn + Biên bản giao nhận + PNK
→ Ghi sổ kế toán
```

## 16.4. Flowchart semantic shapes

- Bản vẽ, đề nghị, PNK, hóa đơn, biên bản: document.
- Hoạt động: process.
- Nơi lưu liên: archive.
- Vật tư physical flow: connector label `Vật tư`, không dùng document symbol.

## 16.5. Routing layout

Do 6 lane:

- nếu landscape:
  - dùng template 6-lane landscape;
  - flow setup/design ở phần trên;
  - procurement/receiving ở phần giữa;
  - accounting reconciliation ở phần dưới.
- `Dự toán + Kế hoạch` đi tới Kế toán ở upper corridor; `Kế hoạch thi công` đi riêng tới Đội thi công.
- Luồng `Vật tư` chạy lower corridor:
  `n_bought_material → n_warehouse_material → n_construction_material`.
- Không cho luồng vật tư chồng lên luồng chứng từ.

Không dùng ELK.

---

# 17. #5 — DFD Fresh Fruit

Không tạo diagram mới.

Dùng lại:

```text
04_fresh_fruit_dfd.xml
```

Khi đưa vào lời giải #5:

- reuse cùng SVG/PNG/PDF asset nếu pipeline hỗ trợ;
- hoặc export lại từ cùng canonical XML;
- nội dung phải giống 100% DFD ở #2.

---

# 18. #7 — Bài 1 — DFD tổng quát bán hàng

## 18.1. Output

```text
09_sales_context_dfd.xml
```

## 18.2. Process

```text
p0  Quá trình bán hàng
```

## 18.3. External entity

```text
x_customer  Khách hàng
```

## 18.4. Data flow

1. `x_customer → p0`: `Thông tin đặt hàng`
2. `p0 → x_customer`: `Phiếu giao hàng`
3. `x_customer → p0`: `Phiếu giao hàng đã ký`

Không đưa hàng hóa vật lý vào DFD.

Không có data store ở context.

## 18.5. Geometry

```text
p0 x=290 y=410 w=220 h=100
x_customer x=620 y=425 w=140 h=60
```

Dùng entry/exit khác cao độ cho hai luồng ngược chiều nếu cần.

---

# 19. #7 — Bài 1 — DFD chi tiết cấp 0

## 19.1. Output

```text
10_sales_level0_dfd.xml
```

## 19.2. External entity

```text
x_customer  Khách hàng
```

## 19.3. Process

```text
p1  Tiếp nhận đơn hàng và lập Phiếu giao hàng
p2  Xử lý xuất và giao hàng
p3  Nhận Phiếu giao hàng đã ký
p4  Kiểm tra và ghi nhận bán hàng
```

## 19.4. Data store

```text
d1  Phiếu giao hàng liên lưu
d2  Doanh thu
d3  Nợ phải thu
d4  Số dư hàng tồn kho
d5  Theo dõi bán hàng
```

## 19.5. Data flow

1. `x_customer → p1`: `Thông tin đặt hàng`
2. `p1 → d1`: `Một liên Phiếu giao hàng`
3. `p1 → p2`: `Hai liên Phiếu giao hàng`
4. `p2 → x_customer`: `Hai liên Phiếu giao hàng`
5. `x_customer → p3`: `Một liên Phiếu giao hàng đã ký trả lại`
6. `p3 → p4`: `Phiếu giao hàng đã ký chuyển về cuối ngày`
7. `p4 → d2`: `Doanh thu`
8. `p4 → d3`: `Nợ phải thu`
9. `p4 → d4`: `Cập nhật số dư hàng tồn kho`
10. `p4 → d5`: `Thông tin theo dõi bán hàng`

Khách hàng giữ một liên đã ký tại chỗ.

**Không vẽ**:

```text
p3 → customer: một liên khách giữ
```

vì đó là luồng giả.

## 19.6. Process p4 phải phản ánh

Trong label hoặc annotation:

```text
Ngày hôm sau:
- kiểm tra số thứ tự các liên;
- cộng doanh số;
- nhập Phiếu giao hàng vào phần mềm;
- ghi nhận doanh thu;
- cập nhật nợ phải thu;
- cập nhật số dư hàng tồn kho;
- theo dõi riêng quá trình bán hàng.
```

Không cần tách tất cả thành nhiều process nếu làm DFD cấp 0 quá vụn.

## 19.7. Geometry

Portrait:

```text
x_customer x=650 y=260

p1 x=80  y=220
p2 x=300 y=220
p3 x=300 y=430
p4 x=300 y=630

d1 x=60  y=410
d2 x=80  y=820
d3 x=260 y=820
d4 x=440 y=820
d5 x=260 y=930
```

---

# 20. #7 — Bài 2 — Lưu đồ bán hàng

## 20.1. Output

```text
11_sales_flow.xml
```

## 20.2. Lane

Chỉ 5 lane:

```text
ln_sales      Nhân viên bán hàng
ln_warehouse  Bộ phận kho
ln_delivery   Bộ phận giao hàng
ln_customer   Khách hàng
ln_accounting Kế toán bán hàng
```

**Không tạo lane `Phần mềm kế toán`.**

Phần mềm là công cụ bên trong lane kế toán bán hàng.

## 20.3. Thuật ngữ

Ở bài #7 luôn viết đầy đủ:

```text
Phiếu giao hàng
```

Không viết `PGH` để tránh nhầm với `Phiếu gửi hàng` của Fresh Fruit.

## 20.4. Node table

### Nhân viên bán hàng

```text
n_order       process   Nhận thông tin đặt hàng
n_deliverydoc document  Phiếu giao hàng (3 liên, đánh số thứ tự)
n_storecopy   archive   Lưu 1 liên
```

### Bộ phận kho

```text
n_wh_receive process  Nhận 2 liên Phiếu giao hàng
n_wh_issue   process  Xuất hàng
```

### Bộ phận giao hàng

```text
n_deliver_receive process Nhận hàng + 2 liên Phiếu giao hàng
n_deliver         process Giao hàng cho khách hàng
n_return_doc      process Nhận lại 1 liên Phiếu giao hàng đã ký
```

### Khách hàng

```text
n_customer_receive process   Nhận hàng
n_customer_sign    process   Ký Phiếu giao hàng
n_customer_keep    document  Phiếu giao hàng — khách giữ 1 liên
```

Không dùng type mơ hồ `archive/process`.

### Kế toán bán hàng

```text
n_acc_receive process      Nhận bàn giao Phiếu giao hàng đã ký
n_seq         process      Kiểm tra số thứ tự các liên
n_sum         process      Tính toán/cộng doanh số
n_software    process      Nhập Phiếu giao hàng vào phần mềm kế toán
d_revenue     stored_data  Dữ liệu doanh thu
d_ar          stored_data  Dữ liệu nợ phải thu
d_inventory   stored_data  Dữ liệu số dư hàng tồn kho
d_tracking    stored_data  Dữ liệu theo dõi bán hàng
```

`d_*` ở đây là system-flowchart stored-data node, không phải DFD data store notation.

Có thể dùng một note cạnh `n_software`:

```text
Phần mềm cài trên 1 máy tính dùng chung cho tất cả nhân viên
```

Không tạo actor/lane máy tính.

## 20.5. Flow

1. `n_order → n_deliverydoc`
2. `n_deliverydoc → n_storecopy` label `1 liên`
3. `n_deliverydoc → n_wh_receive` label `2 liên`
4. `n_wh_receive → n_wh_issue`
5. `n_wh_issue → n_deliver_receive` label `Hàng + 2 liên Phiếu giao hàng`
6. `n_deliver_receive → n_deliver`
7. `n_deliver → n_customer_receive` label `Hàng + 2 liên Phiếu giao hàng`
8. `n_customer_receive → n_customer_sign`
9. `n_customer_sign → n_customer_keep` label `1 liên khách giữ`
10. `n_customer_sign → n_return_doc` label `1 liên đã ký trả lại`
11. `n_return_doc → n_acc_receive` label `Cuối ngày`
12. `n_acc_receive → n_seq` label `Ngày hôm sau`
13. `n_seq → n_sum`
14. `n_sum → n_software`
15. `n_software → d_revenue` label `Ghi nhận doanh thu`
16. `n_software → d_ar` label `Cập nhật nợ phải thu`
17. `n_software → d_inventory` label `Cập nhật số dư hàng tồn kho`
18. `n_software → d_tracking` label `Theo dõi riêng quá trình bán hàng`

## 20.6. Cách vẽ node phần mềm/dữ liệu

Trong lane `Kế toán bán hàng`:

- `n_software` dùng normal process/computer-processing semantics;
- bốn output dùng exact stored-data preset ở §4.4A;
- xếp bốn stored-data node theo 2×2 hoặc theo cột, tùy orientation;
- mỗi edge từ `n_software` có label ngắn;
- không chồng bốn edge trên cùng một segment rồi mới tách.

Không cần remote PC icon; native process + stored-data ổn định hơn và tránh network dependency.

## 20.7. Bố cục

- Bắt đầu portrait 5 lanes.
- Upper half: order → warehouse → delivery → customer.
- Lower half: signed document quay về delivery → accounting.
- Route return edge ở lower corridor.
- Không cho return edge chồng luồng giao hàng đi.
- Trong lane accounting, đặt `n_software` trước cụm stored-data outputs.
- Nếu bốn stored-data outputs làm lane quá dày:
  - chuyển page sang landscape;
  - không giảm font nhỏ;
  - không ép các data node chồng nhau.

Không dùng ELK.

# 21. Exact XML templates Codex có thể copy

## 21.1. Vertex trong lane

```xml
<mxCell
  id="n_example"
  value="Nhãn"
  style="rounded=1;html=1;whiteSpace=wrap;fontFamily=Arial;fontSize=11;align=center;verticalAlign=middle;spacing=4;"
  vertex="1"
  parent="ln_example">
  <mxGeometry
    x="15"
    y="145"
    width="150"
    height="60"
    as="geometry"/>
</mxCell>
```

## 21.2. Document

```xml
<mxCell
  id="n_doc"
  value="Phiếu giao hàng (3 liên)"
  style="strokeWidth=2;html=1;shape=mxgraph.flowchart.document2;whiteSpace=wrap;size=0.25;fontFamily=Arial;fontSize=11;align=center;verticalAlign=middle;spacing=3;"
  vertex="1"
  parent="ln_sales">
  <mxGeometry
    x="15"
    y="145"
    width="150"
    height="70"
    as="geometry"/>
</mxCell>
```

## 21.3. DFD process

```xml
<mxCell
  id="p1"
  value="Lập hóa đơn"
  style="shape=ellipse;html=1;dashed=0;whiteSpace=wrap;perimeter=ellipsePerimeter;fontFamily=Arial;fontSize=11;align=center;verticalAlign=middle;spacing=4;"
  vertex="1"
  parent="1">
  <mxGeometry
    x="300"
    y="220"
    width="150"
    height="70"
    as="geometry"/>
</mxCell>
```

## 21.4. DFD data store

```xml
<mxCell
  id="d1"
  value="D1  Sổ chi tiết phải thu khách hàng"
  style="html=1;dashed=0;whiteSpace=wrap;shape=partialRectangle;right=0;left=0;fontFamily=Arial;fontSize=10;align=left;verticalAlign=middle;spacingLeft=6;"
  vertex="1"
  parent="1">
  <mxGeometry
    x="300"
    y="600"
    width="180"
    height="44"
    as="geometry"/>
</mxCell>
```

## 21.5. Orthogonal edge

```xml
<mxCell
  id="e01"
  value="PGH liên 2"
  style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=classic;endFill=1;fontFamily=Arial;fontSize=10;labelBackgroundColor=#FFFFFF;jettySize=auto;exitX=1;exitY=0.5;entryX=0;entryY=0.5;"
  edge="1"
  parent="1"
  source="p1"
  target="p2">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

---

# 22. Shape search policy

Không cần gọi `search_shapes` cho các primitive đã audit và cố định trong spec nếu server build không đổi.

Nếu build drift hoặc một shape không render đúng:

```text
mcp__drawio__search_shapes
query="flowchart document"
limit=10
```

hoặc:

```text
query="dfd data store"
query="flowchart terminator"
query="file archive storage"
```

Production rule:

```text
limit = integer 1..50
```

Không dùng:

```text
0
negative
fraction
string
```

Khi chọn result:

- dùng exact `style`;
- không đoán stencil suffix;
- ưu tiên native vector shape;
- tránh remote image nếu không cần.

---

# 23. Visual correctness rules

Agent phải ưu tiên **semantic correctness trước decoration**.

## 23.1. Không được

- connector xuyên node;
- connector xuyên label;
- connector chồng nhau không truy được;
- đường chéo tùy tiện;
- arrowhead sai chiều;
- arrowhead lơ lửng;
- chứng từ nhiều liên bị mất liên;
- node nằm ngoài lane;
- DFD entity nối trực tiếp data store;
- data store nối data store;
- entity nối entity;
- physical goods bị biến thành data store;
- tự thêm approval/data source;
- tự thêm actor chỉ để nối được edge.

## 23.2. Nếu connector khó route

Ưu tiên theo thứ tự:

1. đổi vị trí node;
2. đổi row;
3. đổi lane order nếu không phá nghiệp vụ;
4. đổi entry/exit side;
5. tăng khoảng cách;
6. dùng landscape;
7. optional libavoid preview;
8. manual waypoint chỉ là last resort.

Không bắt đầu bằng waypoint.

---

# 23A. Visual construction contract — chống lỗi trước khi render

Đây là các rule bắt buộc để giảm lỗi hình học ngay từ lúc generate XML.

## 23A.1. Corridor reservation

Trước khi tạo edge, agent phải dành corridor:

- vertical corridor giữa các node cùng lane;
- horizontal corridor giữa các lane;
- return/back-flow corridor riêng ở phía dưới hoặc ngoài biên flow chính;
- không đặt node mới vào corridor đã dành cho edge.

## 23A.2. Minimum clearances

Target tối thiểu:

```text
node ↔ node: 20 units
edge ↔ unrelated node: 12 units
edge label ↔ node/edge: 8 units
lane header ↔ first child: 15 units
page safe margin: 20 units
```

Nếu không đạt, tăng spacing hoặc đổi landscape.

## 23A.3. Edge attachment

Mỗi edge phải chọn entry/exit side theo relative geometry:

- target nằm bên phải → source right / target left;
- target nằm bên dưới → source bottom / target top;
- return edge → dùng outer/lower corridor, không nối xuyên flow chính.

Không dùng cùng một fixed side cho mọi edge.

## 23A.4. Parallel and bidirectional edges

Nếu hai node/lane có edge đi và về:

- không để hai edge trùng đúng một path;
- dùng khác `entryY/exitY` hoặc khác top/bottom side;
- nếu vẫn chồng → tách vertical level hoặc outer corridor.

## 23A.5. Fan-out

Với document nhiều liên:

- node chứng từ nằm trước điểm fan-out;
- các edge tách ngay sau node;
- label `Liên 1`, `Liên 2`, `Liên 3` đặt gần đoạn đầu của nhánh;
- không để ba edge chồng nhau quá lâu rồi mới tách.

## 23A.6. Fan-in

Nếu hai chứng từ hội tụ tại một process:

- cho chúng vào hai side/entry position khác nhau;
- không chồng hai connector trên cùng một đoạn;
- process nhận hồ sơ phải có đủ chiều cao/spacing cho label.

## 23A.7. Text fit

Không dựa vào `overflow=hidden`.

Production nodes:

```text
whiteSpace=wrap
overflow=visible hoặc mặc định
```

Nếu text quá dài:

1. tăng width/height;
2. viết label sát đề nhưng ngắn hơn;
3. đổi landscape;
4. chỉ cuối cùng mới giảm font trong ngưỡng cho phép.

## 23A.8. Landscape trigger tự động

Chuyển từ portrait sang landscape nếu **một** trong các điều kiện sau xảy ra sau layout đầu:

- lane width < 110 units;
- >2 node labels phải wrap quá 4 dòng;
- >2 unavoidable connector crossings;
- một return edge phải chạy xuyên >2 lane/node regions;
- usable page width không đủ minimum clearances;
- node/edge phải vượt safe A4 bounds.

Không cố ép portrait vì yêu cầu là portrait **mặc định**, không phải portrait bằng mọi giá.

---

# 24. Final acceptance checklist

## MCP contract

- [ ] Đã check build/server.
- [ ] Chỉ dùng `create_diagram` và `search_shapes`.
- [ ] Mỗi preview là một `<mxGraphModel>`.
- [ ] Không gửi multi-page `<mxfile>` vào MCP.
- [ ] Không claim MCP đã save/export.
- [ ] Không phụ thuộc ELK/libavoid result mà không có readback.

## Source

- [ ] Canonical XML lưu ngoài MCP.
- [ ] ID unique.
- [ ] Parent tồn tại.
- [ ] Parent graph không cycle.
- [ ] Edge source/target tồn tại.
- [ ] Edge có expanded relative geometry.
- [ ] Geometry numeric finite.
- [ ] Vertex width/height > 0.
- [ ] XML attribute escaped.
- [ ] Không XML comment.
- [ ] XML parser thật parse pass.
- [ ] Parent graph acyclic.
- [ ] Absolute bounds nằm trong safe A4 bounds trước MCP call.
- [ ] Shape styles thuộc preset hoặc exact `search_shapes` result.
- [ ] Text-density precheck pass; không ép font nhỏ để fit.

## Đúng đề

- [ ] #1 Bài 1: 1 lưu đồ.
- [ ] #1 Bài 2: 1 lưu đồ + 1 DFD.
- [ ] #2: 1 DFD + 1 lưu đồ.
- [ ] #3: 1 DFD tổng quát + 1 DFD cấp 0.
- [ ] #4: 1 lưu đồ tài liệu.
- [ ] #5: reuse DFD #2.
- [ ] #7 Bài 1: 1 DFD tổng quát + 1 DFD cấp 0.
- [ ] #7 Bài 2: 1 lưu đồ.

## Những lỗi cũ đã khóa

- [ ] Không gán nguồn BCCLTG.
- [ ] Không thêm thu tiền Fresh Fruit.
- [ ] Không dùng Warehouse vừa external entity vừa internal process ở #3.
- [ ] Không bịa chứng từ giao hàng #3.
- [ ] #4: `Dự toán + Kế hoạch → Kế toán`; `Kế hoạch thi công → Đội thi công`.
- [ ] #7 DFD không vẽ flow giả trả lại liên khách giữ.
- [ ] #7 flowchart không có lane Phần mềm kế toán.
- [ ] #7 luôn viết đầy đủ `Phiếu giao hàng`.
- [ ] Payroll DFD bắt đầu từ `BCC đã xác nhận`, không kéo BCC từ hệ thống ra nhân viên để xác nhận.
- [ ] Payroll DFD không bịa data flow cho tiền mặt.
- [ ] Purchase DFD có `Thông tin hàng giao` cân bằng context/cấp 0 để p3 không tự sinh PNK.
- [ ] Fresh Fruit flowchart có `Sổ chi tiết phải thu khách hàng` tách khỏi archive chứng từ.
- [ ] #7 flowchart dùng stored-data outputs cho doanh thu/phải thu/tồn kho/theo dõi bán hàng.

## Page

- [ ] Canonical source dùng A4 portrait 827 × 1169 mặc định.
- [ ] Chỉ đổi page cần thiết sang 1169 × 827 landscape.
- [ ] Không ép font quá nhỏ.
- [ ] External renderer xác nhận page-bound nếu có.
- [ ] DOCX quay về portrait sau section landscape.

## Visual QA

Chỉ tick phần này sau khi có **pixel-level render thực tế**.

- [ ] Không overlap.
- [ ] Không clipped/text overflow.
- [ ] Không connector xuyên node/text.
- [ ] Không crossing khó chịu.
- [ ] Không hai edge ngược chiều chồng cùng path.
- [ ] Label edge đọc được và không đè edge/node khác.
- [ ] Số liên chứng từ đúng.
- [ ] Arrow direction đúng.
- [ ] Lane/container đúng.
- [ ] Fan-out/fan-in tách rõ.
- [ ] Return edge dùng corridor riêng khi cần.
- [ ] A4 page-bound render pass.
- [ ] External SVG/PNG/PDF asset cuối được inspect nếu pipeline có.

---

# 25. Definition of done cho Codex

## 25.1. Source/preflight pass

Một diagram chưa được gọi MCP nếu chưa đạt:

1. canonical XML tồn tại trên filesystem;
2. XML parser thật parse pass;
3. structural checks pass:
   - unique ID;
   - valid parent;
   - acyclic containment;
   - valid source/target;
   - expanded edge geometry;
4. finite/positive geometry pass;
5. canonical A4 absolute-bounds check pass;
6. known-style check pass.

## 25.2. MCP structural/render pass

Sau preflight:

```text
mcp__drawio__create_diagram(xml=<canonical XML>)
```

Chỉ được claim:

```text
MCP structural/render pass
```

khi:

- call thành công;
- viewer payload được tạo;
- không còn validator warning/error có ý nghĩa chưa xử lý.

**Không được đồng nghĩa bước này với visual QA pass.**

MCP hiện tại không cung cấp screenshot, rendered geometry readback, crossing report hoặc page-aware preview.

## 25.3. Visual QA pass

Chỉ được claim `Visual QA passed` nếu agent thật sự có một trong:

- browser/screenshot có thể đưa pixel render cho vision;
- external SVG/PNG render rồi inspect bằng vision;
- Draw.io/editor render được kiểm tra trực tiếp.

Visual QA phải kiểm tra:

```text
text overflow
shape overlap
connector crossing
connector through node/text
wrong arrow direction
dangling-looking edge
edge-label collision
lane overflow
document-copy semantics
remote asset failure if any
```

Nếu không có pixel/render inspection capability:

```text
Skipped: Visual QA — no screenshot/page-aware render available.
Residual risk: pixel-level overlap/crossing/text overflow remains unverified.
```

Không được viết `visual preview không có lỗi rõ ràng` nếu agent không thực sự nhìn được pixels.

## 25.4. Page-bound QA pass

Chỉ được claim page-bound pass khi:

- external page-aware renderer/editor render đúng A4;
- hoặc local geometry checker + renderer cùng xác nhận.

MCP content-fit viewer **không đủ** để claim A4 fit.

## 25.5. Final asset pass

Nếu environment có export pipeline:

- export SVG/PNG/PDF;
- inspect asset cuối;
- sửa canonical XML nếu có lỗi;
- render/export lại.

Nếu không có export pipeline:

```text
Skipped: final SVG/PNG/PDF export
```

không được claim đã export.

## 25.6. Không có cam kết visual tuyệt đối trước render

Specification này được thiết kế để **ngăn lỗi visual bằng construction + preflight + QA**, nhưng không được tuyên bố “không thể có lỗi visual” trước khi pixel-level render thực tế được inspect.

Definition of done cuối cùng:

```text
semantic correctness pass
+ canonical XML preflight pass
+ MCP structural/render pass
+ visual QA pass
+ page-bound QA pass
+ final asset inspection pass
```

Nếu bất kỳ gate nào không chạy được thì phải ghi `Skipped` cùng residual risk; không được tự chuyển gate đó thành `Passed`.

Không coi `MCP call success` đồng nghĩa với `diagram đúng`.
