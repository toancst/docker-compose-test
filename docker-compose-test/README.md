# docker-compose-test

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
