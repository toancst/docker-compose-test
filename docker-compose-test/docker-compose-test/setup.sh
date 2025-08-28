#!/bin/bash
# setup.sh - Script khởi tạo môi trường test Docker Compose

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Docker Compose Test Setup Script   ${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Tạo thư mục scripts nếu chưa có
if [ ! -d "scripts" ]; then
    mkdir -p scripts
    echo -e "${GREEN}✓${NC} Created scripts directory"
fi

# Tạo script info đơn giản trong thư mục scripts
cat > scripts/container-info.sh << 'EOF'
#!/bin/sh
# Script để hiển thị thông tin container từ bên trong container

echo "=== CONTAINER INTERNAL INFO ==="
echo "Current User: $(whoami)"
echo "Working Directory: $(pwd)"
echo "Available Space:"
df -h | head -5
echo ""
echo "Network Configuration:"
if command -v ip >/dev/null 2>&1; then
    ip route show | head -3
elif command -v route >/dev/null 2>&1; then
    route -n | head -5
else
    echo "No network tools available"
fi
echo ""
echo "Environment Variables:"
env | head -10
echo "==========================="
EOF

chmod +x scripts/container-info.sh
echo -e "${GREEN}✓${NC} Created container info script"

# Tạo README với hướng dẫn sử dụng
cat > README.md << 'EOF'
# Docker Compose Test Environment

Môi trường test Docker Compose với 6 containers sử dụng các base image khác nhau.

## Cấu trúc

### Containers:
- **Alpine 3.16**: `test_alpine_316`
- **Alpine 3.17**: `test_alpine_317`
- **Ubuntu 21.04**: `test_ubuntu_21`
- **Ubuntu 22.04**: `test_ubuntu_22`
- **Busybox 1.35.0**: `test_busybox_135`
- **Busybox 1.36.0**: `test_busybox_136`

### Networks:
- `test-network`: Mạng chung cho tất cả containers
- `alpine-network`: Mạng riêng cho Alpine containers
- `ubuntu-network`: Mạng riêng cho Ubuntu containers
- `busybox-network`: Mạng riêng cho Busybox containers

### Volumes:
- Mỗi container có volume riêng để lưu trữ dữ liệu

## Cách sử dụng

### 1. Khởi chạy tất cả containers:
```bash
docker-compose up -d
```

### 2. Xem logs của tất cả containers:
```bash
docker-compose logs -f
```

### 3. Xem thông tin containers:
```bash
docker-compose ps
```

### 4. Chạy test script tương tác:
```bash
chmod +x test-docker-operations.sh
./test-docker-operations.sh
```

### 5. Kết nối vào container cụ thể:
```bash
# Alpine containers
docker exec -it test_alpine_316 sh
docker exec -it test_alpine_317 sh

# Ubuntu containers  
docker exec -it test_ubuntu_21 bash
docker exec -it test_ubuntu_22 bash

# Busybox containers
docker exec -it test_busybox_135 sh
docker exec -it test_busybox_136 sh
```

### 6. Test các thao tác Docker Compose:

#### Scale containers:
```bash
docker-compose up -d --scale alpine-316=3
docker-compose up -d --scale ubuntu-21=2
```

#### Restart specific service:
```bash
docker-compose restart alpine-316
```

#### Stop và start:
```bash
docker-compose stop
docker-compose start
```

#### Update configuration:
```bash
docker-compose up -d --force-recreate
```

### 7. Xem resource usage:
```bash
docker stats
```

### 8. Cleanup:
```bash
docker-compose down --volumes --remove-orphans
docker system prune -f
```

## Test Operations

Các thao tác có thể test:

1. **Container Management:**
   - Start/Stop/Restart containers
   - Scale containers up/down
   - Update container configuration

2. **Network Testing:**
   - Inter-container communication
   - Network isolation
   - Port mapping

3. **Volume Testing:**
   - Data persistence
   - Volume mounting
   - Backup/Restore

4. **Resource Monitoring:**
   - CPU/Memory usage
   - Network I/O
   - Disk usage

5. **Logging:**
   - Container logs
   - Log aggregation
   - Log rotation

## Troubleshooting

### Container không start:
```bash
docker-compose logs <service_name>
```

### Xem chi tiết container:
```bash
docker inspect <container_name>
```

### Debug network issues:
```bash
docker network ls
docker network inspect <network_name>
```

### Check volumes:
```bash
docker volume ls
docker volume inspect <volume_name>
```
EOF

echo -e "${GREEN}✓${NC} Created README.md"

# Tạo file .env với các biến môi trường
cat > .env << 'EOF'
# Environment variables for Docker Compose Test

# Project settings
COMPOSE_PROJECT_NAME=docker_test
COMPOSE_FILE=docker-compose.yml

# Network settings
TEST_NETWORK_SUBNET=172.20.0.0/16
ALPINE_NETWORK_SUBNET=172.21.0.0/16
UBUNTU_NETWORK_SUBNET=172.22.0.0/16
BUSYBOX_NETWORK_SUBNET=172.23.0.0/16

# Container settings
RESTART_POLICY=unless-stopped

# Testing variables
TEST_MODE=development
DEBUG_LEVEL=info
EOF

echo -e "${GREEN}✓${NC} Created .env file"

# Tạo .gitignore
cat > .gitignore << 'EOF'
# Docker
.docker/

# Logs
*.log
logs/

# Temporary files
*.tmp
*.temp

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
EOF

echo -e "${GREEN}✓${NC} Created .gitignore"

echo ""
echo -e "${YELLOW}Setup completed!${NC}"
echo ""
echo "Next steps:"
echo "1. Run: docker-compose up -d"
echo "2. Run: ./test-docker-operations.sh"
echo "3. Check README.md for detailed usage instructions"
echo ""
echo -e "${BLUE}Happy testing! 🐳${NC}"