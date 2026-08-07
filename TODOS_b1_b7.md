
---

# 1
## Bài 1: 
- Hệ thống thông tin tiền lương nhân sự tại một công ty được thực hiện như sau: 
    Kế toán tiền lương thực hiện việc tính lương dựa trên phần mềm và chỉ có duy nhất kế toán tiền lương được quyền truy cập để sửa chữa và điều chỉnh thông tin. Hàng tuần, kế toán tiền lương dựa trên bảng chấm công do các bộ phận sử dụng lao động chuyển đến để tính lương cho nhân viên. Dựa trên bảng tính lương, kế toán tiền lương sẽ lập phiếu chi tiền mặt làm 2 liên để thanh toán lương. Phiếu chi được chuyển cho kế toán trưởng ký duyệt và chuyển lại để kế toán tiền lương nhận tiền, phát tiền cho người lao động. Phiếu chi, bảng tính lương và bảng chấm công được lưu tại bộ phận kế toán. 
- `Yêu cầu`:
    1. Vẽ lưu đồ của hệ thống trên 
    2. Nhận diện những nguy cơ của hệ thống

## Bài 2:
- Chu trình thanh toán tiền lương tại một công ty như sau:
    Bộ phận chấm công thực hiện việc chấm công hàng ngày cho nhân viên, sau đó cuối tháng đưa nhân viên xác nhận và chuyển cho kế toán tiền lương. Kế toán tiền lương nhận bảng chấm công, bảng chấm công làm thêm giờ (nếu nhân viên làm thêm giờ). Căn cứ vào các chứng từ, kế toán tiền lương lập bảng thanh toán tiền lương thành 2 liên, liên 2 giao cho nhân viên, liên còn lại cùng các chứng từ liên quan được chuyển cho kế toán trưởng để kiểm tra và xác nhận. Sau khi kế toán trưởng phê duyệt thì bảng thanh toán tiền lương được chuyển cho Giám đốc ký. Dựa trên bảng thanh toán tiền lương được phê duyệt và ký bởi kế toán trưởng và giám đốc, kế toán lương trả lương cho nhân viên. Nhân viên nhận lương tiền mặt và ký xác nhận. Kế toán tiền lương lưu tất cả các chứng từ. 
- `Yêu cầu`:
    1. Vẽ lưu đồ của hệ thống trên 
    2. Vẽ sơ đồ dòng dữ liệu

---

# 2
- Mô tả hệ thống hiện hành tại Công ty Fresh Fruit như sau:
    - Sau khi nhận phiếu xuất kho do thủ kho chuyển sang, bộ phận gửi hàng đóng gói hàng và lập “phiếu gửi hàng” (PGH) ba liên: liên 1 gửi cho khách hàng cùng hàng hóa, liên 2 gửi cho bộ phận lập hóa đơn, liên 3 gửi cho kế toán, lưu phiếu xuất kho theo số thứ tự.
    - Sau khi nhận được phiếu gửi hàng, bộ phận lập hóa đơn căn cứ vào các thông tin này lập “Hóa đơn” (HĐ) làm hai liên và lưu PGH theo số thứ tự tại bộ phận lập HĐ. Liên 1 HĐ gửi cho khách hàng và liên 2 gửi cho kế toán.
    - Định kỳ, kế toán đối chiếu PGH và HĐ, ghi sổ chi tiết phải thu khách hàng và lưu các chứng từ theo tên khách hàng.
- `Yêu cầu`: Sử dụng công cụ sơ đồ dòng dữ liệu và lưu đồ mô tả hệ thống bán hàng – thu tiền hiện hành tại đơn vị

---

# 3
- Chu trình mua hàng và thanh toán tại công ty ABC như sau: 
    Bộ phận có nhu cầu mua hàng lập đơn đề nghị mua hàng làm 2 liên và sau đó được lãnh đạo công ty phê duyệt. Liên 1 của đơn đề nghị mua hàng đã duyệt được chuyển tới bộ phận mua hàng để xử lý. Liên 2 của đơn đề nghị mua hàng được chuyển cho bộ phận kế toán. Bộ phận mua hàng tiến hành lựa chọn nhà cung cấp và lập đơn đặt hàng thành 3 liên. Liên 1 lưu tại bộ phận mua hàng, liên 2 gửi cho nhà cung cấp, liên 3 gửi cho kế toán. Khi hàng hóa được chuyển đến, bộ phận kho kết hợp với bộ phận mua hàng tiến hành kiểm đếm, nhận hàng và xác nhận hàng. Bộ phận kho lập phiếu nhập kho thành 2 liên, liên 1 kế toán lưu, liên 2 thủ kho lưu. Nhà cung cấp chuyển hóa đơn cho phòng kế toán. Phòng kế toán đối chiếu chứng từ với hóa đơn và ghi sổ mua hàng. Cuối cùng kế toán xử lý thanh toán tiền cho nhà cung cấp.
- `Yêu cầu`:
    1. Lập bảng mô tả đối tượng và hoạt động theo quy trình trên.
    2. Vẽ sơ đồ dòng dữ liệu tổng quát và sơ đồ dòng dữ liệu chi tiết cấp 0 cho quy trình trên.  
    3. Nhận diện những nguy cơ có thể xảy ra trong quy trình trên. 

---

# 4
- Theo yêu cầu tại công trình:
    Phòng thiết kế lập bản vẽ công trình làm 3 bản, lưu lại 1 bản, gửi 1 bản cho phòng dự án và 1 bản cho đội thi công. Phòng dự án nhận bản vẽ công trình từ phòng thiết kế để lập dự toán công trình cùng kế hoạch thi công từng giai đoạn rồi gửi cho kế toán và đội thi công. Đội thi công sau khi nhận bản vẽ công trình và kế hoạch thi công sẽ lập đề nghị cấp vật tư cần thiết theo giai đoạn và gửi cho thủ kho. Thủ kho sau khi nhận đề nghị cấp vật tư tiến hành kiểm tra, đối chiếu khối lượng vật tư tồn kho và lập đề nghị mua vật tư (2 liên), lưu liên 1, giao phòng vật tư liên 2. Phòng vật tư sau khi nhận được đề nghị mua vật tư sẽ tiến hành mua vật tư theo kế hoạch. Vật tư mua về được phòng vật tư nhận và lập biên bản giao nhận. Sau đó biên bản giao nhận và hóa đơn được phòng vật tư chuyển đến cho kế toán. Thủ kho sau khi nhận vật tư từ phòng vật tư lập phiếu nhập kho (2 liên) thì lưu liên 1 tại kho, chuyển liên 2 cho kế toán và vật tư cho đội thi công. Kế toán nhận hóa đơn, biên bản giao nhận hàng hóa cùng phiếu nhập kho để đối chiếu và ghi sổ kế toán. 
- `Yêu cầu`: 
    1. Lập bảng mô tả đối tượng và hoạt động theo quy trình trên.
    2. Vẽ lưu đồ tài liệu mô tả quy trình trên.
    3. Nhận diện những nguy cơ có thể xảy ra trong quy trình trên. 
 
---

# 5
- Mô tả hệ thống hiện hành tại Công ty Fresh Fruit như sau:
    - Sau khi nhận phiếu xuất kho do thủ kho chuyển sang, bộ phận gửi hàng đóng gói hàng và lập “phiếu gửi hàng” (PGH) ba liên: liên 1 gửi cho khách hàng cùng hàng hóa, liên 2 gửi cho bộ phận lập hóa đơn, liên 3 gửi cho kế toán, lưu phiếu xuất kho theo số thứ tự.
    - Sau khi nhận được phiếu gửi hàng, bộ phận lập hóa đơn căn cứ vào các thông tin này lập “Hóa đơn” (HĐ) làm hai liên và lưu PGH theo số thứ tự tại bộ phận lập HĐ. Liên 1 HĐ gửi cho khách hàng và liên 2 gửi cho kế toán.
    - Định kỳ, kế toán đối chiếu PGH và HĐ, ghi sổ chi tiết phải thu khách hàng và lưu các chứng từ theo tên khách hàng.
- `Yêu cầu`: Sử dụng công cụ sơ đồ dòng dữ liệu để mô tả hệ thống hiện hành trên

---

# 6
- Xác định những nhận định sau là Đúng hay Sai và có giải thích:
    1. Hệ thống sổ kế toán là thành phần quan trọng nhất trong hệ thống thông tin kế toán. 
    2. Rủi ro lớn nhất trong quá trình tiếp nhận đơn đặt hàng từ khách hàng là ghi nhận sai các khoản phải thu.
    3. Để tránh nhầm lẫn khi chấm công và tính kết quả lao động hàng tháng, doanh nghiệp cần giao toàn quyền chấm công và tính kết quả lao động của toàn doanh nghiệp cho bộ phận nhân sự.
    4. Hệ thống thông tin kế toán bao gồm ba thành phần là chứng từ kế toán, sổ kế toán chi tiết và sổ kế toán tổng hợp.

---

# 7
## Bài 1: 
- ABC là công ty kinh doanh thiết bị xây dựng:
    Hàng hóa được giao miễn phí đến khách hàng. Khi khách hàng đặt hàng, nhân viên bán hàng điều thông tin vào phiếu giao hàng có 3 liên được đánh số thứ tự. 1 liên lưu và 2 liên gửi đến BP kho hàng. Căn cứ vào giấy giao hàng, thủ kho xuất hàng cho BP giao hàng cùng 2 liên giấy giao hàng. BP giao hàng sẽ chuyển hàng cho khách hàng. Khách hàng nhận hàng, ký vào giấy giao hàng sau đó giữ lại 1 phiếu, phiếu còn lại giao cho người giao hàng để đem về chuyển cho kế toán bán hàng vào cuối ngày. Ngày hôm sau, kế toán bán hàng nhận và kiểm tra số thứ tự các liên giấy giao hàng, tính toán cộng doanh số. Sau đó nhập các giấy giao hàng vào phần mềm kế toán được cài trên 1 máy tính dùng chung cho tất cả các nhân viên của công ty. Chương trình sẽ ghi nhận doanh thu, cập nhật nợ phải thu và số dư hàng tồn kho. Ngoài ra kế toán bán hàng còn theo dõi riêng quá trình bán hàng trên phần mềm. 
- `Yêu cầu`: Vẽ sơ đồ dòng dữ liệu tổng quát và chi tiết cấp 0 mô tả quá trình trên

## Bài 2: 
- ABC là công ty kinh doanh thiết bị xây dựng:
    Hàng hóa được giao miễn phí đến khách hàng. Khi khách hàng đặt hàng, nhân viên bán hàng điều thông tin vào phiếu giao hàng có 3 liên được đánh số thứ tự. 1 liên lưu và 2 liên gửi đến BP kho hàng. Căn cứ vào giấy giao hàng, thủ kho xuất hàng cho BP giao hàng cùng 2 liên giấy giao hàng. BP giao hàng sẽ chuyển hàng cho khách hàng. Khách hàng nhận hàng, ký vào giấy giao hàng sau đó giữ lại 1 phiếu, phiếu còn lại giao cho người giao hàng để đem về chuyển cho kế toán bán hàng vào cuối ngày. Ngày hôm sau, kế toán bán hàng nhận và kiểm tra số thứ tự các liên giấy giao hàng, tính toán cộng doanh số. Sau đó nhập các giấy giao hàng vào phần mềm kế toán được cài trên 1 máy tính dùng chung cho tất cả các nhân viên của công ty. Chương trình sẽ ghi nhận doanh thu, cập nhật nợ phải thu và số dư hàng tồn kho. Ngoài ra kế toán bán hàng còn theo dõi riêng quá trình bán hàng trên phần mềm. 
- `Yêu cầu`: Vẽ lưu đồ mô tả quá trình trên theo các bước quy định
