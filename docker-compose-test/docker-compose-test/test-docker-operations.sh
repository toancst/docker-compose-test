#!/bin/bash
# test-docker-operations.sh - Script để test các thao tác Docker Compose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_separator() {
    echo -e "\n${BLUE}================================${NC}"
}

# Function to check if docker-compose is available
check_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        print_error "Docker Compose not found!"
        exit 1
    fi
    print_info "Using: $COMPOSE_CMD"
}

# Function to show container information
show_container_info() {
    local container_name=$1
    print_separator
    print_info "Container Information for: $container_name"
    
    if docker ps --filter "name=$container_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$container_name"; then
        echo "Status: Running"
        echo "Container ID: $(docker ps --filter "name=$container_name" --format "{{.ID}}")"
        echo "Image: $(docker ps --filter "name=$container_name" --format "{{.Image}}")"
        echo "Created: $(docker ps --filter "name=$container_name" --format "{{.CreatedAt}}")"
        echo "Ports: $(docker ps --filter "name=$container_name" --format "{{.Ports}}")"
        
        print_info "Networks:"
        docker inspect "$container_name" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{end}}'
        
        print_info "Volumes:"
        docker inspect "$container_name" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{end}}'
        
        print_info "Environment Variables:"
        docker inspect "$container_name" --format='{{range .Config.Env}}{{.}}{{end}}' | head -10
    else
        print_warning "Container $container_name is not running"
    fi
}

# Function to show all containers info
show_all_containers_info() {
    print_separator
    print_info "All Containers Information"
    
    containers=("test_alpine_316" "test_alpine_317" "test_ubuntu_21" "test_ubuntu_22" "test_busybox_135" "test_busybox_136")
    
    for container in "${containers[@]}"; do
        show_container_info "$container"
    done
}

# Function to show networks information
show_networks_info() {
    print_separator
    print_info "Docker Networks Information"
    
    networks=($($COMPOSE_CMD ps --services))
    echo "Available networks:"
    docker network ls --filter "label=com.docker.compose.project"
    
    print_info "Network Details:"
    for network in test-network alpine-network ubuntu-network busybox-network; do
        if docker network ls --filter "name=$network" --format "{{.Name}}" | grep -q "$network"; then
            echo "Network: $network"
            docker network inspect "$network" --format='Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'
            docker network inspect "$network" --format='Driver: {{.Driver}}'
            echo "Connected containers:"
            docker network inspect "$network" --format='{{range $k, $v := .Containers}}  - {{$v.Name}} ({{$v.IPv4Address}}){{end}}'
            echo ""
        fi
    done
}

# Function to show volumes information
show_volumes_info() {
    print_separator
    print_info "Docker Volumes Information"
    
    print_info "Project volumes:"
    docker volume ls --filter "label=com.docker.compose.project"
    
    volumes=("alpine316_data" "alpine317_data" "ubuntu21_data" "ubuntu22_data" "busybox135_data" "busybox136_data")
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter "name=$volume" --format "{{.Name}}" | grep -q "$volume"; then
            echo "Volume: $volume"
            docker volume inspect "$volume" --format='Mountpoint: {{.Mountpoint}}'
            docker volume inspect "$volume" --format='Driver: {{.Driver}}'
            echo ""
        fi
    done
}

# Function to test scaling operations
test_scaling() {
    print_separator
    print_info "Testing Container Scaling"
    
    print_info "Current container count:"
    $COMPOSE_CMD ps
    
    print_info "Scaling alpine-316 to 2 instances..."
    $COMPOSE_CMD up -d --scale alpine-316=2
    
    print_info "Waiting 5 seconds..."
    sleep 5
    
    print_info "New container count:"
    $COMPOSE_CMD ps
    
    print_info "Scaling back to 1 instance..."
    $COMPOSE_CMD up -d --scale alpine-316=1
    
    print_success "Scaling test completed"
}

# Function to test container restart
test_restart() {
    print_separator
    print_info "Testing Container Restart"
    
    containers=("alpine-316" "ubuntu-21" "busybox-11")
    
    for container in "${containers[@]}"; do
        print_info "Restarting $container..."
        $COMPOSE_CMD restart "$container"
        sleep 2
    done
    
    print_success "Restart test completed"
}

# Function to test stop/start operations
test_stop_start() {
    print_separator
    print_info "Testing Stop/Start Operations"
    
    print_info "Stopping all containers..."
    $COMPOSE_CMD stop
    
    print_info "Container status after stop:"
    $COMPOSE_CMD ps
    
    print_info "Starting all containers..."
    $COMPOSE_CMD start
    
    print_info "Container status after start:"
    $COMPOSE_CMD ps
    
    print_success "Stop/Start test completed"
}

# Function to show resource usage
show_resource_usage() {
    print_separator
    print_info "Resource Usage Information"
    
    print_info "Container resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
    
    print_info "Docker system usage:"
    docker system df
}

# Function to show logs from all containers
show_logs() {
    print_separator
    print_info "Container Logs (last 20 lines each)"
    
    containers=("alpine-316" "alpine-317" "ubuntu-21" "ubuntu-22" "busybox-11" "busybox-12")
    
    for container in "${containers[@]}"; do
        print_info "Logs from $container:"
        $COMPOSE_CMD logs --tail=20 "$container" 2>/dev/null || print_warning "No logs for $container"
        echo ""
    done
}

# Function to run interactive tests
interactive_test() {
    print_separator
    print_info "Interactive Container Test"
    
    echo "Available containers for interactive testing:"
    echo "1) test_alpine_316"
    echo "2) test_alpine_317" 
    echo "3) test_ubuntu_21"
    echo "4) test_ubuntu_22"
    echo "5) test_busybox_135"
    echo "6) test_busybox_136"
    
    read -p "Select container (1-6): " choice
    
    case $choice in
        1) docker exec -it test_alpine_316 sh ;;
        2) docker exec -it test_alpine_317 sh ;;
        3) docker exec -it test_ubuntu_21 bash ;;
        4) docker exec -it test_ubuntu_22 bash ;;
        5) docker exec -it test_busybox_135 sh ;;
        6) docker exec -it test_busybox_136 sh ;;
        *) print_error "Invalid choice!" ;;
    esac
}

# Main menu function
show_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}    Docker Compose Test Suite        ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    echo "1) Start all containers"
    echo "2) Stop all containers"
    echo "3) Show all containers info"
    echo "4) Show networks info"
    echo "5) Show volumes info"
    echo "6) Show resource usage"
    echo "7) Show container logs"
    echo "8) Test scaling operations"
    echo "9) Test restart operations"
    echo "10) Test stop/start operations"
    echo "11) Interactive container test"
    echo "12) Full system info"
    echo "13) Cleanup everything"
    echo "0) Exit"
    echo ""
}

# Cleanup function
cleanup() {
    print_separator
    print_info "Cleaning up..."
    
    $COMPOSE_CMD down --volumes --remove-orphans
    
    print_info "Removing unused images..."
    docker image prune -f
    
    print_info "Removing unused volumes..."
    docker volume prune -f
    
    print_info "Removing unused networks..."
    docker network prune -f
    
    print_success "Cleanup completed"
}

# Full system info function
full_system_info() {
    show_all_containers_info
    show_networks_info
    show_volumes_info
    show_resource_usage
}

# Main script execution
main() {
    check_docker_compose
    
    while true; do
        show_menu
        read -p "Choose an option: " option
        
        case $option in
            1)
                print_info "Starting all containers..."
                $COMPOSE_CMD up -d
                print_success "All containers started"
                ;;
            2)
                print_info "Stopping all containers..."
                $COMPOSE_CMD stop
                print_success "All containers stopped"
                ;;
            3) show_all_containers_info ;;
            4) show_networks_info ;;
            5) show_volumes_info ;;
            6) show_resource_usage ;;
            7) show_logs ;;
            8) test_scaling ;;
            9) test_restart ;;
            10) test_stop_start ;;
            11) interactive_test ;;
            12) full_system_info ;;
            13) 
                read -p "Are you sure you want to cleanup everything? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    cleanup
                fi
                ;;
            0) 
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi