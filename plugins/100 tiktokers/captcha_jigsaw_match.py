import cv2
import numpy as np

def process_images(background_path, puzzle_path):
    # Đọc hình ảnh
    background_img = cv2.imread(background_path)
    puzzle_img = cv2.imread(puzzle_path)
    
    # Chuyển sang grayscale và áp dụng edge detection (Canny) để tăng độ chính xác matching
    background_gray = cv2.cvtColor(background_img, cv2.COLOR_BGR2GRAY)
    puzzle_gray = cv2.cvtColor(puzzle_img, cv2.COLOR_BGR2GRAY)
    
    background_edges = cv2.Canny(background_gray, 100, 200)
    puzzle_edges = cv2.Canny(puzzle_gray, 100, 200)
    
    return background_img, puzzle_img, background_edges, puzzle_edges

def find_puzzle_position(background_edges, puzzle_edges):
    # Sử dụng template matching để tìm vị trí khớp nhất
    result = cv2.matchTemplate(background_edges, puzzle_edges, cv2.TM_CCOEFF_NORMED)
    min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(result)
    return max_loc, max_val

def visualize_and_save(background_img, puzzle_img, max_loc):
    # Tính toán góc dưới phải của khung
    h, w = puzzle_img.shape[:2]
    bottom_right = (max_loc[0] + w, max_loc[1] + h)
    
    # Vẽ khung đỏ quanh vị trí khớp trên background
    cv2.rectangle(background_img, max_loc, bottom_right, (0, 0, 255), 2)
    
    # Lưu hình kết quả
    cv2.imwrite('result.png', background_img)
    print("Hình kết quả đã lưu tại 'result.png' với khung đỏ đánh dấu vị trí.")

# Sử dụng
background_path = 'background_demo.webp'  # Đường dẫn đến hình nền với lỗ hổng
puzzle_path = 'piece_demo.webp'    # Đường dẫn đến miếng ghép

background_img, puzzle_img, background_edges, puzzle_edges = process_images(background_path, puzzle_path)
max_loc, max_val = find_puzzle_position(background_edges, puzzle_edges)

# Tính khoảng cách kéo (thường slider bắt đầu từ x=0, kéo sang phải bằng max_loc[0])
movement = max_loc[0]
print(f"Vị trí chính xác để đặt miếng ghép: x = {movement} pixels từ trái (độ khớp: {max_val:.2f}).")

# Visualize và lưu kết quả
visualize_and_save(background_img, puzzle_img, max_loc)