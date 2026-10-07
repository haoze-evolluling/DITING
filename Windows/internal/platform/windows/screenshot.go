package windows

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

var (
	modUser32 = syscall.NewLazyDLL("user32.dll")
	modGdi32  = syscall.NewLazyDLL("gdi32.dll")

	procFindWindowW             = modUser32.NewProc("FindWindowW")
	procGetWindowRect           = modUser32.NewProc("GetWindowRect")
	procGetWindowDC             = modUser32.NewProc("GetWindowDC")
	procReleaseDC               = modUser32.NewProc("ReleaseDC")
	procPrintWindow             = modUser32.NewProc("PrintWindow")
	procCreateCompatibleDC      = modGdi32.NewProc("CreateCompatibleDC")
	procCreateCompatibleBitmap  = modGdi32.NewProc("CreateCompatibleBitmap")
	procSelectObject            = modGdi32.NewProc("SelectObject")
	procDeleteDC                = modGdi32.NewProc("DeleteDC")
	procDeleteObject            = modGdi32.NewProc("DeleteObject")
	procGetDIBits               = modGdi32.NewProc("GetDIBits")
)

type rect struct {
	Left   int32
	Top    int32
	Right  int32
	Bottom int32
}

type bitmapInfoHeader struct {
	BiSize          uint32
	BiWidth         int32
	BiHeight        int32
	BiPlanes        uint16
	BiBitCount      uint16
	BiCompression   uint32
	BiSizeImage     uint32
	BiXPelsPerMeter int32
	BiYPelsPerMeter int32
	BiClrUsed       uint32
	BiClrImportant  uint32
}

// DefaultWindowTitle 谛听 GUI 客户端窗口默认标题
const DefaultWindowTitle = "谛听 (DITING) DNS 控制台"

// CaptureDitingWindow 截取当前运行的谛听客户端窗口并保存为 PNG 图片
func CaptureDitingWindow(outputPath string) (string, error) {
	return CaptureWindow(DefaultWindowTitle, outputPath)
}

// CaptureWindow 根据窗口标题精确截取目标软件窗口界面并保存为 PNG 图片
func CaptureWindow(windowTitle, outputPath string) (string, error) {
	titlePtr, err := syscall.UTF16PtrFromString(windowTitle)
	if err != nil {
		return "", fmt.Errorf("无效的窗口标题: %w", err)
	}

	hwnd, _, _ := procFindWindowW.Call(0, uintptr(unsafe.Pointer(titlePtr)))
	if hwnd == 0 {
		return "", fmt.Errorf("未找到标题为 '%s' 的运行中窗口", windowTitle)
	}

	var r rect
	ret, _, _ := procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	if ret == 0 {
		return "", fmt.Errorf("获取窗口矩形区域失败")
	}

	width := int(r.Right - r.Left)
	height := int(r.Bottom - r.Top)
	if width <= 0 || height <= 0 {
		return "", fmt.Errorf("无效的窗口尺寸: %dx%d", width, height)
	}

	hdcWin, _, _ := procGetWindowDC.Call(hwnd)
	if hdcWin == 0 {
		return "", fmt.Errorf("获取窗口 DC 失败")
	}
	defer procReleaseDC.Call(hwnd, hdcWin)

	hdcMem, _, _ := procCreateCompatibleDC.Call(hdcWin)
	if hdcMem == 0 {
		return "", fmt.Errorf("创建内存兼容 DC 失败")
	}
	defer procDeleteDC.Call(hdcMem)

	hBmp, _, _ := procCreateCompatibleBitmap.Call(hdcWin, uintptr(width), uintptr(height))
	if hBmp == 0 {
		return "", fmt.Errorf("创建兼容位图失败")
	}
	defer procDeleteObject.Call(hBmp)

	hOldBmp, _, _ := procSelectObject.Call(hdcMem, hBmp)
	defer procSelectObject.Call(hdcMem, hOldBmp)

	// PW_RENDERFULLCONTENT = 2
	printRet, _, _ := procPrintWindow.Call(hwnd, hdcMem, 2)
	if printRet == 0 {
		// 降级使用常规 PrintWindow
		printRet, _, _ = procPrintWindow.Call(hwnd, hdcMem, 0)
		if printRet == 0 {
			return "", fmt.Errorf("PrintWindow 抓取窗口界面失败")
		}
	}

	var bi bitmapInfoHeader
	bi.BiSize = uint32(unsafe.Sizeof(bi))
	bi.BiWidth = int32(width)
	bi.BiHeight = -int32(height) // top-down DIB
	bi.BiPlanes = 1
	bi.BiBitCount = 32
	bi.BiCompression = 0 // BI_RGB

	rawSize := width * height * 4
	rawBytes := make([]byte, rawSize)

	dibRet, _, _ := procGetDIBits.Call(
		hdcMem,
		hBmp,
		0,
		uintptr(height),
		uintptr(unsafe.Pointer(&rawBytes[0])),
		uintptr(unsafe.Pointer(&bi)),
		0, // DIB_RGB_COLORS
	)
	if dibRet == 0 {
		return "", fmt.Errorf("获取位图像素数据失败")
	}

	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			offset := (y*width + x) * 4
			b := rawBytes[offset]
			g := rawBytes[offset+1]
			rVal := rawBytes[offset+2]
			img.SetRGBA(x, y, color.RGBA{R: rVal, G: g, B: b, A: 255})
		}
	}

	if outputPath == "" {
		timestamp := time.Now().Format("20060102_150405")
		outputPath = filepath.Join(os.TempDir(), fmt.Sprintf("diting_screenshot_%s.png", timestamp))
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return "", fmt.Errorf("创建输出目录失败: %w", err)
	}

	file, err := os.Create(outputPath)
	if err != nil {
		return "", fmt.Errorf("创建截图文件失败: %w", err)
	}
	defer file.Close()

	if err := png.Encode(file, img); err != nil {
		return "", fmt.Errorf("编码 PNG 图像失败: %w", err)
	}

	absPath, err := filepath.Abs(outputPath)
	if err != nil {
		return outputPath, nil
	}
	return absPath, nil
}
