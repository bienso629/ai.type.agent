// Các element trên giao diện
const btnGetSheets = document.getElementById('btnGetSheets');
const sheetSelect = document.getElementById('sheetSelect');
const btnRead = document.getElementById('btnRead');
const btnWrite = document.getElementById('btnWrite');
const statusDiv = document.getElementById('status');
const dataTable = document.getElementById('dataTable');

// 1. TÍNH NĂNG: LẤY DANH SÁCH CÁC TAB (SHEETS)
btnGetSheets.addEventListener('click', async () => {
  const spreadsheetId = document.getElementById('sheetId').value.trim();

  if (!spreadsheetId) {
    statusDiv.style.color = 'red';
    statusDiv.innerText = 'Vui lòng nhập Spreadsheet ID trước!';
    return;
  }

  statusDiv.style.color = '#5f6368';
  statusDiv.innerText = 'Đang tải danh sách các Tab...';

  // Gọi hàm xuyên tiến trình qua Preload Bridge
  const result = await window.api.getSheetsList(spreadsheetId);

  if (result.success) {
    statusDiv.style.color = 'green';
    statusDiv.innerText = 'Đã tải xong danh sách Tab!';

    // Xóa danh sách cũ và đổ danh sách mới vào thẻ <select>
    sheetSelect.innerHTML = '';
    result.data.forEach(title => {
      const option = document.createElement('option');
      option.value = title;
      option.innerText = title;
      sheetSelect.appendChild(option);
    });
  } else {
    statusDiv.style.color = 'red';
    statusDiv.innerText = `Lỗi tải danh sách: ${result.error}`;
  }
});

// 2. TÍNH NĂNG: ĐỌC DỮ LIỆU TỪ SHEET ĐÃ CHỌN
btnRead.addEventListener('click', async () => {
  const spreadsheetId = document.getElementById('sheetId').value.trim();
  const selectedSheet = document.getElementById('sheetSelect').value;
  const rangeCells = document.getElementById('rangeCells').value.trim();

  if (!spreadsheetId || !selectedSheet) {
    statusDiv.style.color = 'red';
    statusDiv.innerText = 'Vui lòng nhập ID và Bấm Tải/Chọn danh sách Tab trước!';
    return;
  }

  // Tự động ghép tên Sheet và vùng cell (Ví dụ: Sheet1!A1:C10)
  const range = `${selectedSheet}!${rangeCells}`;

  statusDiv.style.color = '#5f6368';
  statusDiv.innerText = `Đang kết nối API và lấy dữ liệu từ vùng ${range}...`;
  dataTable.innerHTML = '';

  const result = await window.api.readSheet(spreadsheetId, range);

  if (result.success) {
    statusDiv.style.color = 'green';
    statusDiv.innerText = 'Đồng bộ dữ liệu thành công!';

    if (result.data && result.data.length > 0) {
      result.data.forEach((row, index) => {
        const tr = document.createElement('tr');
        row.forEach(cellText => {
          const cell = index === 0 ? document.createElement('th') : document.createElement('td');
          cell.innerText = cellText;
          tr.appendChild(cell);
        });
        dataTable.appendChild(tr);
      });
    } else {
      statusDiv.innerText = 'Kết nối thành công nhưng vùng dữ liệu trống.';
    }
  } else {
    statusDiv.style.color = 'red';
    statusDiv.innerText = `Thất bại: ${result.error}`;
  }
});

// 3. TÍNH NĂNG: GHI DỮ LIỆU VÀO SHEET ĐÃ CHỌN
btnWrite.addEventListener('click', async () => {
  const spreadsheetId = document.getElementById('sheetId').value.trim();
  const selectedSheet = document.getElementById('sheetSelect').value;
  const rangeCells = document.getElementById('rangeCells').value.trim();

  const colA = document.getElementById('inputColA').value.trim();
  const colB = document.getElementById('inputColB').value.trim();
  const colC = document.getElementById('inputColC').value.trim();

  if (!spreadsheetId || !selectedSheet) {
    statusDiv.style.color = 'red';
    statusDiv.innerText = 'Vui lòng nhập ID và Bấm Tải/Chọn danh sách Tab trước!';
    return;
  }

  if (!colA && !colB && !colC) {
    statusDiv.style.color = 'red';
    statusDiv.innerText = 'Vui lòng nhập ít nhất một trường dữ liệu (Cột A, B hoặc C)!';
    return;
  }

  const range = `${selectedSheet}!${rangeCells}`;
  statusDiv.style.color = '#5f6368';
  statusDiv.innerText = `Đang đẩy dữ liệu lên Tab "${selectedSheet}"...`;

  const newRowValues = [[colA, colB, colC]];
  const result = await window.api.writeSheet(spreadsheetId, range, newRowValues);

  if (result.success) {
    statusDiv.style.color = 'green';
    statusDiv.innerText = `Đã thêm thành công dữ liệu vào hàng tiếp theo!`;
    // Xóa trắng các ô input sau khi gửi thành công
    document.getElementById('inputColA').value = '';
    document.getElementById('inputColB').value = '';
    document.getElementById('inputColC').value = '';
  } else {
    statusDiv.style.color = 'red';
    statusDiv.innerText = `Lỗi ghi dữ liệu: ${result.error}`;
  }
});