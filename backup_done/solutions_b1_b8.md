# Bài làm Hệ thống thông tin kế toán – Bài 1–8

## Danh mục chữ viết tắt

| Chữ viết tắt | Nội dung |
|---|---|
| BCC | Bảng chấm công |
| BCCLTG | Bảng chấm công làm thêm giờ |
| BTTL | Bảng thanh toán tiền lương |
| PXK | Phiếu xuất kho |
| PGH | Phiếu gửi hàng |
| HĐ | Hóa đơn |
| ĐNMH | Đơn đề nghị mua hàng |
| ĐĐH | Đơn đặt hàng |
| PNK | Phiếu nhập kho |

## Bài 1

### Tình huống 1 – Hệ thống thông tin tiền lương nhân sự

#### 1. Lưu đồ hệ thống

![Lưu đồ hệ thống thông tin tiền lương nhân sự](assets/svg/b01_01_payroll_system_flowchart.svg)

*Hình 1. Lưu đồ hệ thống thông tin tiền lương nhân sự.*

#### 2. Những nguy cơ của hệ thống

| STT | Nguy cơ | Phân tích |
|---:|---|---|
| 1 | Dữ liệu chấm công không chính xác | Kế toán tiền lương hoàn toàn dựa vào bảng chấm công do các bộ phận sử dụng lao động chuyển đến. Bảng chấm công sai hoặc chưa được xác nhận sẽ làm tiền lương bị tính sai. |
| 2 | Sai sót hoặc sửa trái phép dữ liệu lương | Chỉ kế toán tiền lương có quyền truy cập, sửa chữa và điều chỉnh dữ liệu nhưng không có bước rà soát độc lập đối với các thay đổi. |
| 3 | Không phân chia trách nhiệm | Kế toán tiền lương đồng thời nhập dữ liệu, tính lương, lập phiếu chi, nhận tiền, phát tiền và lưu chứng từ. |
| 4 | Gian lận tiền lương | Kế toán tiền lương có thể thêm nhân viên không có thật, tăng ngày công hoặc điều chỉnh số tiền rồi chiếm đoạt phần chênh lệch. |
| 5 | Chi trả sai người hoặc sai số tiền | Quy trình không nêu bước đối chiếu danh tính người nhận, danh sách trả lương và số tiền thực tế phát. |
| 6 | Thất thoát tiền mặt | Người tính lương cũng trực tiếp nhận và phát tiền nên có thể biển thủ tiền lương chưa phát hoặc khai khống khoản đã chi. |
| 7 | Kiểm tra và phê duyệt chưa đầy đủ | Kế toán trưởng chỉ ký phiếu chi; quy trình không nêu việc đối chiếu phiếu chi với bảng tính lương và bảng chấm công. |
| 8 | Chứng từ và dữ liệu không được bảo vệ đầy đủ | Tất cả chứng từ được lưu tại bộ phận kế toán, trong khi quy trình không nêu phân quyền đọc, sao lưu dữ liệu hoặc bảo quản hồ sơ dự phòng. |

### Tình huống 2 – Chu trình thanh toán tiền lương

#### 1. Lưu đồ hệ thống

![Lưu đồ hệ thống thanh toán tiền lương](assets/svg/b01_02_payroll_payment_flowchart.svg)

*Hình 2. Lưu đồ hệ thống thanh toán tiền lương.*

#### 2. Sơ đồ dòng dữ liệu tổng quát

![Sơ đồ dòng dữ liệu tổng quát của chu trình thanh toán tiền lương](assets/svg/b01_02_payroll_context_dfd.svg)

*Hình 3. Sơ đồ dòng dữ liệu tổng quát của chu trình thanh toán tiền lương.*

#### 3. Sơ đồ dòng dữ liệu cấp 0

![Sơ đồ dòng dữ liệu cấp 0 của chu trình thanh toán tiền lương](assets/svg/b01_02_payroll_level0_dfd.svg)

*Hình 4. Sơ đồ dòng dữ liệu cấp 0 của chu trình thanh toán tiền lương.*

## Bài 2 – Chu trình bán hàng và ghi nhận phải thu tại Fresh Fruit

### 1. Lưu đồ hệ thống

![Lưu đồ hệ thống bán hàng và ghi nhận phải thu tại Fresh Fruit](assets/svg/b02_fresh_fruit_flowchart.svg)

*Hình 5. Lưu đồ hệ thống bán hàng và ghi nhận phải thu tại Fresh Fruit.*

### 2. Sơ đồ dòng dữ liệu tổng quát

![Sơ đồ dòng dữ liệu tổng quát tại Fresh Fruit](assets/svg/b02_fresh_fruit_context_dfd.svg)

*Hình 6. Sơ đồ dòng dữ liệu tổng quát tại Fresh Fruit.*

### 3. Sơ đồ dòng dữ liệu cấp 0

![Sơ đồ dòng dữ liệu cấp 0 tại Fresh Fruit](assets/svg/b02_fresh_fruit_level0_dfd.svg)

*Hình 7. Sơ đồ dòng dữ liệu cấp 0 tại Fresh Fruit.*

## Bài 3 – Chu trình mua hàng và thanh toán

### 1. Bảng mô tả đối tượng và hoạt động

| Đối tượng | Hoạt động |
|---|---|
| Bộ phận có nhu cầu mua hàng | Xác định nhu cầu; lập đơn đề nghị mua hàng hai liên; trình lãnh đạo phê duyệt; chuyển liên 1 đã duyệt cho bộ phận mua hàng và liên 2 cho kế toán. |
| Lãnh đạo công ty | Xem xét và phê duyệt đơn đề nghị mua hàng. |
| Bộ phận mua hàng | Nhận đơn đề nghị mua hàng liên 1; lựa chọn nhà cung cấp; lập đơn đặt hàng ba liên; lưu liên 1, gửi liên 2 cho nhà cung cấp và liên 3 cho kế toán; phối hợp với kho kiểm đếm và xác nhận hàng nhận. |
| Nhà cung cấp | Nhận đơn đặt hàng; giao hàng; gửi hóa đơn cho kế toán; nhận tiền thanh toán. |
| Bộ phận kho | Phối hợp kiểm đếm, nhận và xác nhận hàng; lập phiếu nhập kho hai liên; chuyển liên 1 cho kế toán và lưu liên 2 tại kho. |
| Phòng kế toán | Nhận đơn đề nghị mua hàng liên 2, đơn đặt hàng liên 3, phiếu nhập kho liên 1 và hóa đơn; đối chiếu chứng từ; ghi sổ mua hàng; xử lý thanh toán cho nhà cung cấp. |

### 2. Sơ đồ dòng dữ liệu tổng quát

![Sơ đồ dòng dữ liệu tổng quát của chu trình mua hàng và thanh toán](assets/svg/b03_purchasing_context_dfd.svg)

*Hình 8. Sơ đồ dòng dữ liệu tổng quát của chu trình mua hàng và thanh toán.*

### 3. Sơ đồ dòng dữ liệu cấp 0

![Sơ đồ dòng dữ liệu cấp 0 của chu trình mua hàng và thanh toán](assets/svg/b03_purchasing_level0_dfd.svg)

*Hình 9. Sơ đồ dòng dữ liệu cấp 0 của chu trình mua hàng và thanh toán.*

### 4. Những nguy cơ có thể xảy ra

| STT | Nguy cơ | Phân tích |
|---:|---|---|
| 1 | Mua hàng không cần thiết hoặc chưa được phép | Đơn đề nghị có thể được lập khống, lập vượt nhu cầu hoặc được xử lý khi chưa có phê duyệt hợp lệ. |
| 2 | Lựa chọn nhà cung cấp không phù hợp | Bộ phận mua hàng tự lựa chọn nhà cung cấp nên có thể thông đồng, nhận hoa hồng hoặc chọn mức giá và điều kiện bất lợi. |
| 3 | Đơn đặt hàng sai hoặc bị lập trùng | Sai mặt hàng, số lượng, giá, điều kiện giao hàng hoặc số liên có thể dẫn đến giao nhận và ghi nhận sai. |
| 4 | Nhận thiếu, nhận sai hoặc nhận hàng kém chất lượng | Bộ phận mua hàng tham gia cả đặt hàng và nhận hàng; quy trình không nêu kiểm tra chất lượng độc lập. |
| 5 | Phiếu nhập kho không phản ánh đúng hàng thực nhận | Số lượng trên phiếu có thể sai hoặc hàng chưa nhận vẫn được xác nhận nhập kho. |
| 6 | Ghi nhận hóa đơn không hợp lệ hoặc trùng lặp | Nếu đối chiếu không đầy đủ, kế toán có thể ghi nhận hóa đơn giả, hóa đơn trùng hoặc hóa đơn không khớp hàng nhận. |
| 7 | Thanh toán sai nhà cung cấp, sai số tiền hoặc thanh toán hai lần | Kế toán vừa ghi nhận vừa xử lý thanh toán; quy trình không nêu bước phê duyệt thanh toán độc lập. |
| 8 | Sai kỳ kế toán và sai số dư công nợ, hàng tồn kho | Chứng từ chuyển chậm hoặc thiếu có thể làm giao dịch được ghi nhận sai kỳ hoặc không đầy đủ. |
| 9 | Chứng từ bị thất lạc hoặc sử dụng lại | Quy trình không nêu đánh số trước, kiểm tra tính liên tục và quy tắc lưu toàn bộ đơn đề nghị, đơn đặt hàng, phiếu nhập kho và hóa đơn. |

## Bài 4 – Quy trình mua và cấp vật tư công trình

### 1. Bảng mô tả đối tượng và hoạt động

| Đối tượng | Hoạt động |
|---|---|
| Phòng thiết kế | Lập bản vẽ công trình ba bản; lưu một bản; gửi một bản cho phòng dự án và một bản cho đội thi công. |
| Phòng dự án | Nhận bản vẽ; lập dự toán công trình và kế hoạch thi công từng giai đoạn; gửi cho kế toán và đội thi công. |
| Đội thi công | Nhận bản vẽ và kế hoạch thi công; lập đề nghị cấp vật tư theo giai đoạn gửi thủ kho; nhận vật tư để thi công. |
| Thủ kho | Nhận đề nghị cấp vật tư; kiểm tra và đối chiếu vật tư tồn kho; lập đề nghị mua vật tư hai liên; lưu liên 1, chuyển liên 2 cho phòng vật tư; nhận vật tư mua về; lập phiếu nhập kho hai liên; lưu liên 1, chuyển liên 2 cho kế toán; giao vật tư cho đội thi công. |
| Phòng vật tư | Nhận đề nghị mua vật tư liên 2; mua vật tư theo kế hoạch; nhận vật tư; lập biên bản giao nhận; chuyển biên bản giao nhận và hóa đơn cho kế toán; chuyển vật tư cho thủ kho. |
| Kế toán | Nhận dự toán và kế hoạch thi công; nhận hóa đơn, biên bản giao nhận và phiếu nhập kho liên 2; đối chiếu chứng từ và ghi sổ kế toán. |

### 2. Lưu đồ tài liệu

![Lưu đồ tài liệu của quy trình mua và cấp vật tư công trình](assets/svg/b04_construction_materials_document_flowchart.svg)

*Hình 10. Lưu đồ tài liệu của quy trình mua và cấp vật tư công trình.*

### 3. Những nguy cơ có thể xảy ra

| STT | Nguy cơ | Phân tích |
|---:|---|---|
| 1 | Sử dụng sai phiên bản bản vẽ hoặc kế hoạch | Bản vẽ được phát hành thành nhiều bản nhưng quy trình không nêu mã phiên bản, thu hồi bản cũ hoặc xác nhận thay đổi. |
| 2 | Dự toán và nhu cầu vật tư không chính xác | Sai khối lượng hoặc tiến độ có thể dẫn đến mua thiếu, mua thừa hoặc cấp vật tư không đúng giai đoạn. |
| 3 | Đề nghị mua vật tư không được phê duyệt | Thủ kho tự lập đề nghị mua sau khi kiểm tra tồn kho nhưng quy trình không nêu người có thẩm quyền xét duyệt. |
| 4 | Mua vật tư sai giá, sai chủng loại hoặc thông đồng với nhà cung cấp | Quy trình không nêu việc lập đơn đặt hàng, so sánh báo giá, phê duyệt nhà cung cấp và điều kiện mua. |
| 5 | Nhận thiếu hoặc nhận vật tư kém chất lượng | Phòng vật tư vừa mua vừa nhận hàng; không có bộ phận độc lập kiểm tra số lượng và chất lượng khi nhận. |
| 6 | Phiếu nhập kho và biên bản giao nhận không khớp thực tế | Thủ kho lập phiếu nhập dựa trên vật tư do phòng vật tư giao nhưng không nêu bước đối chiếu với đơn mua đã duyệt. |
| 7 | Cấp vật tư không có chứng từ xuất kho | Quy trình chỉ nêu giao vật tư cho đội thi công, không nêu việc lập phiếu xuất kho hoặc ký nhận. |
| 8 | Ghi nhận hóa đơn không hợp lệ hoặc trùng lặp | Kế toán đối chiếu hóa đơn, biên bản giao nhận và phiếu nhập kho nhưng thiếu đơn đặt hàng hoặc đề nghị mua đã phê duyệt. |
| 9 | Thất thoát hoặc sử dụng vật tư sai công trình | Việc mua, nhận, nhập kho và cấp cho thi công thiếu các bước kiểm tra độc lập và theo dõi theo công trình, giai đoạn. |
| 10 | Chứng từ bị thất lạc hoặc ghi nhận sai kỳ | Nhiều chứng từ luân chuyển qua nhiều bộ phận nhưng không nêu đánh số trước, theo dõi tình trạng hoặc thời hạn chuyển kế toán. |

## Bài 5 – Sơ đồ dòng dữ liệu tại Fresh Fruit

### 1. Sơ đồ dòng dữ liệu tổng quát

![Sơ đồ dòng dữ liệu tổng quát tại Fresh Fruit](assets/svg/b02_fresh_fruit_context_dfd.svg)

*Hình 11. Sơ đồ dòng dữ liệu tổng quát tại Fresh Fruit (dùng chung nguồn chuẩn với Bài 2).*

### 2. Sơ đồ dòng dữ liệu cấp 0

![Sơ đồ dòng dữ liệu cấp 0 tại Fresh Fruit](assets/svg/b02_fresh_fruit_level0_dfd.svg)

*Hình 12. Sơ đồ dòng dữ liệu cấp 0 tại Fresh Fruit (dùng chung nguồn chuẩn với Bài 2).*

## Bài 6 – Nhận định Đúng/Sai

| STT | Kết luận | Giải thích |
|---:|:---:|---|
| 1 | Sai | Hệ thống sổ kế toán là một bộ phận của hệ thống thông tin kế toán, không thể mặc nhiên xem là thành phần quan trọng nhất. Hệ thống còn bao gồm con người, quy trình, dữ liệu, chứng từ, phần mềm, hạ tầng và kiểm soát; các thành phần phải phối hợp để tạo thông tin đầy đủ và đáng tin cậy. |
| 2 | Sai | Ghi nhận khoản phải thu thường phát sinh ở bước lập hóa đơn hoặc ghi nhận bán chịu, không phải rủi ro trọng yếu nhất ngay khi tiếp nhận đơn hàng. Ở khâu tiếp nhận, các rủi ro chính là nhận đơn không hợp lệ, sai thông tin, chấp nhận khách hàng không đủ khả năng thanh toán hoặc cam kết giao hàng khi không đủ tồn kho. |
| 3 | Sai | Giao toàn quyền chấm công và tính kết quả lao động cho một bộ phận làm mất sự phân chia trách nhiệm. Bộ phận sử dụng lao động hoặc người quản lý trực tiếp nên xác nhận thời gian và kết quả làm việc; nhân sự quản lý hồ sơ nhân viên; kế toán tiền lương tính lương; người có thẩm quyền kiểm tra và phê duyệt. |
| 4 | Sai | Chứng từ kế toán, sổ chi tiết và sổ tổng hợp chỉ là các cấu phần dữ liệu và ghi chép kế toán. Hệ thống thông tin kế toán còn có con người, quy trình xử lý, phần mềm, cơ sở hạ tầng công nghệ và các biện pháp kiểm soát nội bộ. |

## Bài 7 – DFD chu trình bán hàng thiết bị xây dựng

### 1. Sơ đồ dòng dữ liệu tổng quát

![Sơ đồ dòng dữ liệu tổng quát của chu trình bán hàng thiết bị xây dựng](assets/svg/b07_sales_context_dfd.svg)

*Hình 13. Sơ đồ dòng dữ liệu tổng quát của chu trình bán hàng thiết bị xây dựng.*

### 2. Sơ đồ dòng dữ liệu cấp 0

![Sơ đồ dòng dữ liệu cấp 0 của chu trình bán hàng thiết bị xây dựng](assets/svg/b07_sales_level0_dfd.svg)

*Hình 14. Sơ đồ dòng dữ liệu cấp 0 của chu trình bán hàng thiết bị xây dựng.*

## Bài 8 – Lưu đồ chu trình bán hàng thiết bị xây dựng

![Lưu đồ chu trình bán hàng thiết bị xây dựng](assets/svg/b08_sales_document_flowchart.svg)

*Hình 15. Lưu đồ chu trình bán hàng thiết bị xây dựng.*
