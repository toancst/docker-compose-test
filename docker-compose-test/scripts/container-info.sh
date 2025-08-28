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
