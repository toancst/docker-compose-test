package main

import (
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Khai báo biến toàn cục hoặc sử dụng cấu hình
var (
	watchDir   = getEnv("WATCH_DIR", "storage")
	logDir     = getEnv("LOG_DIR", "log")
	historyLog = filepath.Join(logDir, "history.log")
)

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
		// Kiểm tra xem đường dẫn có hợp lệ không
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
			// Nếu là file, không cần watch đệ quy, chỉ thêm chính nó nếu cần
			return nil
		}

		err = watcher.Add(path)
		if err != nil {
			// Log lỗi nhưng không dừng chương trình
			logger.Printf("Không thể thêm watcher cho thư mục %s: %v", path, err)
			return err
		}
		logger.Printf("Đã thêm watcher cho thư mục: %s", path)

		entries, err := os.ReadDir(path)
		if err != nil {
			logger.Printf("Không thể đọc thư mục con của %s: %v", path, err) // Log lỗi
			return nil                                                       // Bỏ qua lỗi khi không đọc được folder
		}
		for _, entry := range entries {
			if entry.IsDir() {
				// Cần kiểm tra lỗi ở đây nếu muốn xử lý chi tiết hơn
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

				switch {
				case event.Op&fsnotify.Create == fsnotify.Create:
					info, err := os.Stat(event.Name)
					if err != nil {
						logger.Printf("[CREATE] %s | Lỗi đọc thông tin: %v\n", event.Name, err)
					} else {
						size := info.Size()
						timestamp := time.Now().Format("2006-01-02 15:04:05")
						logger.Printf("[CREATE] %s | Size: %d bytes | Time: %s\n", event.Name, size, timestamp)
						if info.IsDir() {
							// Thêm watcher cho thư mục mới được tạo
							_ = addWatchRecursive(event.Name)
						}
					}

				case event.Op&fsnotify.Remove == fsnotify.Remove:
					timestamp := time.Now().Format("2006-01-02 15:04:05")
					logger.Printf("[DELETE] %s | Time: %s\n", event.Name, timestamp)
					// fsnotify tự động dừng watch cho các thư mục bị xóa.
					// Nếu có nhu cầu xử lý phức tạp hơn (ví dụ: xóa khỏi danh sách được theo dõi),
					// thì cần lưu trữ state của các watcher.

				case event.Op&fsnotify.Write == fsnotify.Write:
					info, err := os.Stat(event.Name)
					if err != nil {
						logger.Printf("[WRITE] %s | Lỗi đọc thông tin: %v\n", event.Name, err)
					} else {
						size := info.Size()
						timestamp := time.Now().Format("2006-01-02 15:04:05")
						logger.Printf("[WRITE] %s | Size: %d bytes | Time: %s\n", event.Name, size, timestamp)
					}

				case event.Op&fsnotify.Rename == fsnotify.Rename:
					// Xử lý rename phức tạp hơn một chút vì có thể là di chuyển hoặc đổi tên
					// Cần kiểm tra xem đường dẫn cũ còn tồn tại không
					_, err := os.Stat(event.Name)
					if os.IsNotExist(err) {
						timestamp := time.Now().Format("2006-01-02 15:04:05")
						logger.Printf("[RENAME/MOVED_FROM] %s | Time: %s\n", event.Name, timestamp)
					} else {
						timestamp := time.Now().Format("2006-01-02 15:04:05")
						logger.Printf("[RENAME/MOVED_TO] %s | Time: %s\n", event.Name, timestamp)
						info, _ := os.Stat(event.Name)
						if info != nil && info.IsDir() {
							_ = addWatchRecursive(event.Name) // Thêm watcher cho thư mục mới được đổi tên/di chuyển đến
						}
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
