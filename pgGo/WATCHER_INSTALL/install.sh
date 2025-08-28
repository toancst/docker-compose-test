#!/bin/bash

# --- Cấu hình ---
PROGRAM_NAME="pgGo_watcher"
INSTALL_DIR="/opt/${PROGRAM_NAME}"
WATCH_DIR="/home/developer/cpt/pgGo/storage"
LOG_DIR="/home/developer/cpt/pgGo/log"
SERVICE_USER="pg_watcher" # Người dùng dành riêng cho dịch vụ
SERVICE_GROUP="pg_watcher" # Nhóm dành riêng cho dịch vụ
SERVICE_FILE="/etc/systemd/system/${PROGRAM_NAME}.service"

# --- Kiểm tra quyền root ---
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script này với quyền sudo."
  exit 1
fi

echo "--- Bắt đầu cài đặt ${PROGRAM_NAME} ---"

# --- 1. Tạo người dùng và nhóm dịch vụ (nếu chưa có) ---
if ! id -u ${SERVICE_USER} > /dev/null 2>&1; then
    echo "Tạo người dùng và nhóm ${SERVICE_USER}..."
    sudo groupadd --system ${SERVICE_GROUP}
    sudo useradd --system -g ${SERVICE_GROUP} -d ${INSTALL_DIR} -s /sbin/nologin ${SERVICE_USER}
fi

# --- 2. Tạo các thư mục cần thiết ---
echo "Tạo các thư mục: ${INSTALL_DIR}, ${WATCH_DIR}, ${LOG_DIR}..."
mkdir -p ${INSTALL_DIR}
mkdir -p ${WATCH_DIR}
mkdir -p ${LOG_DIR}

# --- 3. Sao chép và cấp quyền cho chương trình ---
echo "Sao chép chương trình ${PROGRAM_NAME} vào ${INSTALL_DIR}..."
# Giả sử file thực thi nằm cùng thư mục với script cài đặt
cp "./${PROGRAM_NAME}" "${INSTALL_DIR}/${PROGRAM_NAME}"
chmod +x "${INSTALL_DIR}/${PROGRAM_NAME}"
chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${INSTALL_DIR}
chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${WATCH_DIR}
chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${LOG_DIR} # Đảm bảo service có quyền ghi log

# --- 4. Tạo Systemd Service File ---
echo "Tạo file Systemd service: ${SERVICE_FILE}..."
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=PG Go Directory Watcher Service
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/${PROGRAM_NAME}
WorkingDirectory=${INSTALL_DIR}
Restart=always
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
# Environment="WATCH_DIR=${WATCH_DIR}" # Uncomment nếu bạn muốn override thông qua biến môi trường
# Environment="LOG_DIR=${LOG_DIR}"     # Uncomment nếu bạn muốn override thông qua biến môi trường
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- 5. Tải lại cấu hình Systemd và Bật dịch vụ ---
echo "Tải lại cấu hình Systemd, bật và khởi động dịch vụ..."
systemctl daemon-reload
systemctl enable ${PROGRAM_NAME}.service
systemctl start ${PROGRAM_NAME}.service

echo "--- Cài đặt ${PROGRAM_NAME} hoàn tất! ---"
echo "Kiểm tra trạng thái dịch vụ: sudo systemctl status ${PROGRAM_NAME}.service"
echo "Xem log dịch vụ: sudo journalctl -u ${PROGRAM_NAME}.service -f"
echo "Xem log chương trình: cat ${LOG_DIR}/history.log"