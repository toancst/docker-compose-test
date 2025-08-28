#!/bin/bash

# ==============================================================================
# Script tự động cập nhật image cho Docker Compose trên máy local.
#
# Cách dùng:
#   ./update.sh <đường_dẫn_file_compose> <đường_dẫn_file_tar> <tên_image> <tag_mới>
#
# Ví dụ:
#   ./update.sh ./docker-compose.yml ./alpine-3.20.tar alpine 3.20
# ==============================================================================

# ~/dker-prj/alpine-3.19.tar 

# --- MÀU SẮC CHO OUTPUT ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- KIỂM TRA THAM SỐ ĐẦU VÀO ---
if [[ $# -ne 4 ]]; then
  echo -e "${RED}Lỗi: Cần đúng 4 tham số.${NC}"
  echo "Cách dùng: $0 <file_compose> <file_tar> <tên_image> <tag_mới>"
  echo "Ví dụ:    $0 ./docker-compose.yml ./alpine-3.20.tar alpine 3.20"
  exit 1
fi

# --- THIẾT LẬP BIẾN ---
COMPOSE_FILE="$1"
IMAGE_TAR_FILE="$2"
IMAGE_NAME="$3"
NEW_TAG="$4"
FULL_IMAGE_NAME="${IMAGE_NAME}:${NEW_TAG}"

# --- KIỂM TRA SỰ TỒN TẠI CỦA CÁC FILE ---
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo -e "${RED}❌ File compose '${COMPOSE_FILE}' không tồn tại!${NC}"
  exit 1
fi

if [[ ! -f "$IMAGE_TAR_FILE" ]]; then
  echo -e "${RED}❌ File image tar '${IMAGE_TAR_FILE}' không tồn tại!${NC}"
  exit 1
fi

# Dừng script ngay nếu có lỗi
set -e

echo -e "${GREEN}--- BƯỚC 1: Nạp Image từ file .tar ---${NC}"
echo -e "📦 Đang nạp image từ ${IMAGE_TAR_FILE}..."
docker load -i "${IMAGE_TAR_FILE}"
echo -e "✅ Nạp image thành công."

echo -e "\n${GREEN}--- BƯỚC 2: Cập nhật file docker-compose.yml ---${NC}"
echo "🔎 Tìm kiếm image cũ trong ${COMPOSE_FILE}..."
# Grep dòng có chứa "image: <tên_image>:", lấy dòng đầu tiên, và cắt chuỗi để lấy tên đầy đủ
OLD_FULL_IMAGE=$(grep "image: *${IMAGE_NAME}:" "${COMPOSE_FILE}" | head -n 1 | awk '{print $2}')

if [[ -z "$OLD_FULL_IMAGE" ]]; then
  echo -e "${YELLOW}⚠️ Không tìm thấy service nào sử dụng image '${IMAGE_NAME}'. Không có gì để làm.${NC}"
  # Tùy chọn, nếu muốn dọn dẹp file tar dù không update
  # read -p "Bạn có muốn xóa file ${IMAGE_TAR_FILE} không? (y/N) " choice
  # [[ "$choice" == "y" || "$choice" == "Y" ]] && rm -f "$IMAGE_TAR_FILE"
  exit 0
fi

# Kiểm tra xem có cần update không
if [[ "$OLD_FULL_IMAGE" == "$FULL_IMAGE_NAME" ]]; then
  echo -e "${YELLOW}🎉 Các service đã đang sử dụng phiên bản mới nhất '${FULL_IMAGE_NAME}'. Không cần cập nhật.${NC}"
  exit 0
fi

echo "✅ Tìm thấy phiên bản cũ là: ${OLD_FULL_IMAGE}"
echo "✍️  Cập nhật ${OLD_FULL_IMAGE} -> ${FULL_IMAGE_NAME}..."

# Dùng `|` làm dấu phân cách cho sed để tránh lỗi với đường dẫn hoặc các ký tự đặc biệt
sed -i.bak "s|${OLD_FULL_IMAGE}|${FULL_IMAGE_NAME}|g" "${COMPOSE_FILE}"
echo "📝 File compose đã được cập nhật. Một file backup '${COMPOSE_FILE}.bak' đã được tạo."

echo -e "\n${GREEN}--- BƯỚC 3: Áp dụng thay đổi ---${NC}"
echo "🚀 Áp dụng thay đổi với 'docker-compose up'..."

# Lấy thư mục chứa file compose để chạy lệnh `docker-compose` từ đó
COMPOSE_DIR=$(dirname "${COMPOSE_FILE}")
# Dùng -f để chỉ định file compose, an toàn hơn là cd
docker-compose -f "${COMPOSE_FILE}" up -d --remove-orphans
echo -e "✅ Các container đã được cập nhật thành công."

echo -e "\n${GREEN}--- BƯỚC 4: Dọn dẹp (Tùy chọn) ---${NC}"
read -p "Bạn có muốn xóa file tar '${IMAGE_TAR_FILE}' không? (y/N) " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
  rm -f "$IMAGE_TAR_FILE"
  echo "🧹 Đã xóa file ${IMAGE_TAR_FILE}."
fi

echo -e "\n${GREEN}🎉🎉🎉 HOÀN TẤT! 🎉🎉🎉${NC}"