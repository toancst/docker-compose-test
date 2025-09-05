package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/fsnotify/fsnotify"
	"gopkg.in/yaml.v3" // Thêm thư viện YAML
)

// Khai báo biến toàn cục hoặc sử dụng cấu hình
var (
	watchDir          = getEnv("WATCH_DIR", "pgGo/storage") // Thư mục chứa các file .tar mới
	logDir            = getEnv("LOG_DIR", "pgGo/log")
	historyLog        = filepath.Join(logDir, "history.log")
	dockerComposeFile = getEnv("DOCKER_COMPOSE_FILE", "docker-compose.yml") // Tên file docker-compose của bạn
)

// Cấu trúc để map YAML (chỉ các phần chúng ta cần)
type DockerCompose struct {
	Services map[string]Service     `yaml:"services"`
	Networks map[string]interface{} `yaml:"networks"`
	Volumes  map[string]interface{} `yaml:"volumes"`
}

type Service struct {
	Image         string   `yaml:"image"`
	ContainerName string   `yaml:"container_name"`
	Hostname      string   `yaml:"hostname"`
	Networks      []string `yaml:"networks"`
	Environment   []string `yaml:"environment"`
	Volumes       []string `yaml:"volumes"`
	Command       string   `yaml:"command"`
	Restart       string   `yaml:"restart"`
	// Thêm các trường khác nếu cần
}

// getEnv đọc biến môi trường hoặc trả về giá trị mặc định
func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func main() {
	// Đảm bảo các thư mục cần thiết tồn tại
	if err := os.MkdirAll(watchDir, 0755); err != nil {
		log.Fatalf("Không thể tạo thư mục giám sát %s: %v", watchDir, err)
	}
	if err := os.MkdirAll(logDir, 0755); err != nil {
		log.Fatalf("Không thể tạo thư mục log %s: %v", logDir, err)
	}

	// Mở file log ở chế độ append
	logFile, err := os.OpenFile(historyLog, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("Không thể mở history.log: %v", err)
	}
	defer logFile.Close()
	logger := log.New(logFile, "", log.LstdFlags)

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		logger.Fatal(err) // Log fatal ra file
	}
	defer watcher.Close()

	// Kênh để nhận tín hiệu hệ thống
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	// Hàm add watcher đệ quy cho tất cả subfolder
	var addWatchRecursive func(string) error
	addWatchRecursive = func(path string) error {
		info, err := os.Stat(path)
		if err != nil {
			if os.IsNotExist(err) {
				logger.Printf("Thư mục không tồn tại: %s, bỏ qua.", path)
				return nil
			}
			logger.Printf("Lỗi khi lấy thông tin thư mục %s: %v", path, err)
			return err
		}
		if !info.IsDir() {
			return nil
		}

		err = watcher.Add(path)
		if err != nil {
			logger.Printf("Không thể thêm watcher cho thư mục %s: %v", path, err)
			return err
		}
		logger.Printf("Đã thêm watcher cho thư mục: %s", path)

		entries, err := os.ReadDir(path)
		if err != nil {
			logger.Printf("Không thể đọc thư mục con của %s: %v", path, err)
			return nil
		}
		for _, entry := range entries {
			if entry.IsDir() {
				_ = addWatchRecursive(filepath.Join(path, entry.Name()))
			}
		}
		return nil
	}

	err = addWatchRecursive(watchDir)
	if err != nil {
		logger.Fatalf("Không thể theo dõi thư mục gốc %s: %v", watchDir, err)
	}

	logger.Println("=== Bắt đầu theo dõi thư mục:", watchDir, "===")

	// Kênh để biết khi nào chương trình nên dừng
	done := make(chan bool, 1)

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}

				// Chúng ta chỉ quan tâm đến các sự kiện CREATE hoặc WRITE file .tar
				if event.Op&fsnotify.Create == fsnotify.Create || event.Op&fsnotify.Write == fsnotify.Write {
					if strings.HasSuffix(event.Name, ".tar") {
						logger.Printf("[FILE DETECTED] %s | Type: %s | Time: %s\n", event.Name, event.Op.String(), time.Now().Format("2006-01-02 15:04:05"))
						processNewImage(event.Name, logger)
					}
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				logger.Println("Lỗi Watcher:", err)

			case <-sigs:
				logger.Println("Nhận tín hiệu dừng, đóng ứng dụng...")
				done <- true // Báo hiệu cho main goroutine để dừng
				return
			}
		}
	}()

	<-done // Chờ tín hiệu dừng
	logger.Println("Ứng dụng đã dừng.")
}

// processNewImage xử lý file image .tar mới
func processNewImage(imagePath string, logger *log.Logger) {
	logger.Printf("Bắt đầu xử lý image mới: %s\n", imagePath)

	// 1. Phân tích tên file để lấy image name và tag
	fileName := filepath.Base(imagePath)
	re := regexp.MustCompile(`^([a-zA-Z0-9_-]+)-([\d\.]+)\.tar$`)
	matches := re.FindStringSubmatch(fileName)

	if len(matches) < 3 {
		logger.Printf("Tên file không đúng định dạng 'imageName-tag.tar': %s. Bỏ qua.\n", fileName)
		return
	}

	imageName := matches[1]
	imageTag := matches[2]
	fullImageName := fmt.Sprintf("%s:%s", imageName, imageTag)

	logger.Printf("Đã phân tích: Image Name = %s, Image Tag = %s, Full Image = %s\n", imageName, imageTag, fullImageName)

	// 2. Thực hiện docker load
	logger.Printf("Thực hiện: docker load -i %s\n", imagePath)
	cmd := exec.Command("docker", "load", "-i", imagePath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if err != nil {
		logger.Printf("Lỗi khi thực hiện 'docker load': %v\n", err)
		return
	}
	logger.Println("Docker load hoàn tất.")

	// 3. Cập nhật docker-compose.yml
	err = updateDockerCompose(imageName, imageTag, logger)
	if err != nil {
		logger.Printf("Lỗi khi cập nhật docker-compose.yml: %v\n", err)
		return
	}
	logger.Println("Cập nhật docker-compose.yml hoàn tất.")

	// 4. Thực hiện các lệnh docker-compose
	runDockerComposeCommands(logger)
}

// updateDockerCompose đọc, cập nhật và ghi lại file docker-compose.yml
func updateDockerCompose(newImageName, newImageTag string, logger *log.Logger) error {
	yamlFile, err := ioutil.ReadFile(dockerComposeFile)
	if err != nil {
		return fmt.Errorf("không thể đọc file docker-compose.yml: %v", err)
	}

	var compose DockerCompose
	err = yaml.Unmarshal(yamlFile, &compose)
	if err != nil {
		return fmt.Errorf("không thể parse docker-compose.yml: %v", err)
	}

	updated := false
	for serviceName, service := range compose.Services {
		// Kiểm tra xem tên service có chứa newImageName không (ví dụ: alpine-316 -> alpine)
		// Hoặc bạn có thể sử dụng một mapping rõ ràng hơn
		if strings.HasPrefix(serviceName, newImageName) {
			oldImage := service.Image
			newFullImage := fmt.Sprintf("%s:%s", newImageName, newImageTag)

			if oldImage != newFullImage {
				compose.Services[serviceName] = Service{
					Image:         newFullImage,
					ContainerName: service.ContainerName,
					Hostname:      service.Hostname,
					Networks:      service.Networks,
					Environment:   service.Environment,
					Volumes:       service.Volumes,
					Command:       service.Command,
					Restart:       service.Restart,
				}
				logger.Printf("Cập nhật service '%s': image từ '%s' sang '%s'\n", serviceName, oldImage, newFullImage)
				updated = true
			}
		}
	}

	if !updated {
		logger.Println("Không có service nào cần cập nhật trong docker-compose.yml.")
		return nil
	}

	// Ghi lại file YAML đã cập nhật
	updatedYaml, err := yaml.Marshal(&compose)
	if err != nil {
		return fmt.Errorf("không thể marshal docker-compose.yml: %v", err)
	}

	// Ghi vào một file tạm thời trước rồi mới đổi tên để tránh mất dữ liệu nếu có lỗi
	tempFile := dockerComposeFile + ".tmp"
	err = ioutil.WriteFile(tempFile, updatedYaml, 0644)
	if err != nil {
		return fmt.Errorf("không thể ghi file docker-compose.yml tạm thời: %v", err)
	}

	err = os.Rename(tempFile, dockerComposeFile)
	if err != nil {
		return fmt.Errorf("không thể đổi tên file docker-compose.yml tạm thời: %v", err)
	}

	return nil
}

// runDockerComposeCommands thực hiện các lệnh docker-compose
func runDockerComposeCommands(logger *log.Logger) {
	commands := [][]string{
		{"docker-compose", "-f", dockerComposeFile, "pull"},
		{"docker-compose", "-f", dockerComposeFile, "up", "-d", "--force-recreate"},
		{"docker", "image", "prune", "-a", "-f"}, // Thêm -f để không hỏi xác nhận
	}

	for _, cmdArgs := range commands {
		logger.Printf("Thực hiện lệnh: %s\n", strings.Join(cmdArgs, " "))
		cmd := exec.Command(cmdArgs[0], cmdArgs[1:]...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		err := cmd.Run()
		if err != nil {
			logger.Printf("Lỗi khi thực hiện lệnh '%s': %v\n", strings.Join(cmdArgs, " "), err)
			// Tùy chọn: bạn có thể chọn dừng hoặc tiếp tục với các lệnh khác
		} else {
			logger.Printf("Lệnh '%s' hoàn tất.\n", strings.Join(cmdArgs, " "))
		}
	}
}
