#!/bin/bash

# ==============================================================================
# Script tự động cập nhật image cho Docker Compose trên server từ xa.
#
# Cách dùng:
#   ./update_compose_remote.sh <tên_image> <tag_mới>
#
# Ví dụ:
#   ./update_compose_remote.sh alpine 3.20
# ==============================================================================

# --- CẤU HÌNH ---
REMOTE_USER="toancs"                     # << THAY ĐỔI: User trên server
REMOTE_HOST="192.168.1.100"            # << THAY ĐỔI: IP/hostname server
# << THAY ĐỔI: Đường dẫn TUYỆT ĐỐI tới file docker-compose.yml trên server
REMOTE_COMPOSE_FILE="/home/toancs/compose-test/docker-compose.yml"

# --- MÀU SẮC CHO OUTPUT ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- KIỂM TRA THAM SỐ ĐẦU VÀO ---
if [[ -z "$1" || -z "$2" ]]; then
  echo -e "${RED}Lỗi: Thiếu tham số.${NC}"
  echo "Cách dùng: $0 <tên_image> <tag_mới>"
  echo "Ví dụ:    $0 alpine 3.20"
  exit 1
fi

# --- THIẾT LẬP BIẾN ---
IMAGE_NAME="$1"
NEW_TAG="$2"
FULL_IMAGE_NAME="$IMAGE_NAME:$NEW_TAG"
LOCAL_TAR_FILE="/tmp/${IMAGE_NAME}-${NEW_TAG}.tar"

# Hàm dọn dẹp file .tar trên máy client khi script kết thúc
cleanup() {
  echo -e "${YELLOW}🧹 Dọn dẹp file tạm trên client: ${LOCAL_TAR_FILE}${NC}"
  rm -f "$LOCAL_TAR_FILE"
}
trap cleanup EXIT

# ==================================================
# BƯỚC 1: PULL VÀ SAVE IMAGE TRÊN MÁY CLIENT
# ==================================================
echo -e "${GREEN}--- BƯỚC 1: Chuẩn bị Image trên Client ---${NC}"
echo -e "🔽 Đang tải image ${FULL_IMAGE_NAME}..."
docker pull "$FULL_IMAGE_NAME"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ Tải image thất bại!${NC}"
  exit 1
fi

echo -e "📦 Đang đóng gói image vào ${LOCAL_TAR_FILE}..."
docker save -o "$LOCAL_TAR_FILE" "$FULL_IMAGE_NAME"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ Đóng gói image thất bại!${NC}"
  exit 1
fi
echo -e "✅ Chuẩn bị image thành công."

# ==================================================
# BƯỚC 2: GỬI FILE VÀ KIỂM TRA CHECKSUM
# ==================================================
echo -e "\n${GREEN}--- BƯỚC 2: Gửi file lên Server và xác thực ---${NC}"
REMOTE_TEMP_DIR="/tmp" # Gửi vào thư mục /tmp trên server cho an toàn

echo -e "📤 Đang gửi ${LOCAL_TAR_FILE} sang ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_TEMP_DIR} ..."
scp "$LOCAL_TAR_FILE" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_TEMP_DIR}"
if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ Gửi file thất bại!${NC}"
  exit 1
fi

# --- tính checksum local ---
LOCAL_SUM=$(md5sum "$LOCAL_TAR_FILE" | awk '{print $1}')

# --- tính checksum remote ---
REMOTE_TAR_FILE="${REMOTE_TEMP_DIR}/$(basename "$LOCAL_TAR_FILE")"
REMOTE_SUM=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "md5sum ${REMOTE_TAR_FILE}" | awk '{print $1}')

# --- so sánh ---
echo "🔑 MD5 local :  ${LOCAL_SUM}"
echo "🔑 MD5 remote:  ${REMOTE_SUM}"

if [[ "$LOCAL_SUM" != "$REMOTE_SUM" ]]; then
  echo -e "${RED}⚠️ File gửi xong nhưng checksum KHÔNG khớp! Hủy bỏ quá trình.${NC}"
  # (Tùy chọn) Xóa file lỗi trên server
  ssh "${REMOTE_USER}@${REMOTE_HOST}" "rm ${REMOTE_TAR_FILE}"
  exit 1
fi
echo -e "✅ File được gửi thành công và checksum khớp!"

# ==================================================
# BƯỚC 3: THỰC THI CẬP NHẬT TRÊN SERVER
# ==================================================
echo -e "\n${GREEN}--- BƯỚC 3: Thực thi cập nhật trên Server qua SSH ---${NC}"

# Sử dụng "here document" (<< 'EOF') để gửi một loạt lệnh sang server
# Dùng 'EOF' trong nháy đơn để ngăn các biến local bị expand trước khi gửi
ssh -t "${REMOTE_USER}@${REMOTE_HOST}" << 'EOF'
  # --- CẤU HÌNH TRÊN SERVER (được truyền từ client) ---
  # Dòng này sẽ được thay thế bằng lệnh sed trước khi chạy
  # sed sẽ chèn các giá trị biến từ client vào đây
  export IMAGE_NAME="<image_name>"
  export NEW_TAG="<new_tag>"
  export FULL_IMAGE_NAME="<full_image_name>"
  export REMOTE_TAR_FILE="<remote_tar_file>"
  export REMOTE_COMPOSE_FILE="<remote_compose_file>"
  export GREEN='\033[0;32m'
  export YELLOW='\033[1;33m'
  export RED='\033[0;31m'
  export NC='\033[0m' # No Color

  echo -e "${YELLOW}--- ĐANG THỰC THI TRÊN SERVER ---${NC}"

  # Dừng script ngay nếu có lỗi
  set -e

  # 1. Load image
  echo "📦 (Server) Đang nạp image từ ${REMOTE_TAR_FILE}..."
  docker load -i "${REMOTE_TAR_FILE}"

  # 2. Tìm image cũ trong file compose
  echo "🔎 (Server) Tìm kiếm image cũ trong ${REMOTE_COMPOSE_FILE}..."
  # Grep dòng có chứa "image: <tên_image>:", lấy dòng đầu tiên, và cắt chuỗi để lấy tên đầy đủ
  OLD_FULL_IMAGE=$(grep "image: *${IMAGE_NAME}:" "${REMOTE_COMPOSE_FILE}" | head -n 1 | awk '{print $2}')

  if [[ -z "$OLD_FULL_IMAGE" ]]; then
    echo -e "${RED}❌ (Server) Không tìm thấy service nào sử dụng image '${IMAGE_NAME}' trong file compose. Dừng lại.${NC}"
    exit 1
  fi
  echo "✅ (Server) Tìm thấy phiên bản cũ là: ${OLD_FULL_IMAGE}"

  # 3. Thay thế image cũ bằng image mới
  echo "✍️ (Server) Cập nhật ${OLD_FULL_IMAGE} -> ${FULL_IMAGE_NAME}..."
  # Dùng `|` làm dấu phân cách cho sed để tránh lỗi với đường dẫn
  sed -i "s|${OLD_FULL_IMAGE}|${FULL_IMAGE_NAME}|g" "${REMOTE_COMPOSE_FILE}"

  # 4. Chạy docker-compose up
  echo "🚀 (Server) Áp dụng thay đổi với 'docker compose up'..."
  # Lấy thư mục chứa file compose để `cd` vào đó trước khi chạy
  COMPOSE_DIR=$(dirname "${REMOTE_COMPOSE_FILE}")
  cd "${COMPOSE_DIR}" && docker compose up -d --remove-orphans

  # 5. Dọn dẹp file .tar trên server
  echo "🧹 (Server) Dọn dẹp file ${REMOTE_TAR_FILE}..."
  rm "${REMOTE_TAR_FILE}"

  echo -e "${GREEN}✅ (Server) Quá trình cập nhật hoàn tất!${NC}"

EOF` \
| sed -e "s|<image_name>|${IMAGE_NAME}|g" \
      -e "s|<new_tag>|${NEW_TAG}|g" \
      -e "s|<full_image_name>|${FULL_IMAGE_NAME}|g" \
      -e "s|<remote_tar_file>|${REMOTE_TAR_FILE}|g" \
      -e "s|<remote_compose_file>|${REMOTE_COMPOSE_FILE}|g"
# Trick: Đoạn `| sed ...` ở trên sẽ tìm và thay thế các placeholder trong here document
# bằng giá trị biến thực tế từ client trước khi thực thi lệnh ssh.

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Có lỗi xảy ra trong quá trình thực thi trên server!${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉🎉🎉 TOÀN BỘ QUÁ TRÌNH CẬP NHẬT ĐÃ HOÀN TẤT THÀNH CÔNG! 🎉🎉🎉${NC}"