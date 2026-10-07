package windows

import (
	"math"
	"syscall"
	"time"
	"unsafe"
)

var (
	modComctl32 = syscall.NewLazyDLL("comctl32.dll")

	procSetWindowSubclass    = modComctl32.NewProc("SetWindowSubclass")
	procDefSubclassProc      = modComctl32.NewProc("DefSubclassProc")
	procRemoveWindowSubclass = modComctl32.NewProc("RemoveWindowSubclass")
)

const (
	wmSizing = 0x0214

	wmszLeft        = 1
	wmszRight       = 2
	wmszTop         = 3
	wmszTopLeft     = 4
	wmszTopRight    = 5
	wmszBottom      = 6
	wmszBottomLeft  = 7
	wmszBottomRight = 8

	aspectSubclassID = 0x444954 // "DIT"
)

// AdjustRectForAspectRatio 根据给定的 16:9 等比例与最小宽高调整拖拽窗口尺寸
func AdjustRectForAspectRatio(r *rect, edge uintptr, aspect float64, minW, minH int32) {
	if aspect <= 0 {
		aspect = 16.0 / 9.0
	}

	w := r.Right - r.Left
	h := r.Bottom - r.Top

	switch edge {
	case wmszLeft, wmszRight:
		// 拖拽左右边缘：依据宽度计算高度
		if w < minW {
			w = minW
		}
		newH := int32(math.Round(float64(w) / aspect))
		if newH < minH {
			newH = minH
			w = int32(math.Round(float64(newH) * aspect))
		}
		if edge == wmszLeft {
			r.Left = r.Right - w
		} else {
			r.Right = r.Left + w
		}
		r.Bottom = r.Top + newH

	case wmszTop, wmszBottom:
		// 拖拽上下边缘：依据高度计算宽度
		if h < minH {
			h = minH
		}
		newW := int32(math.Round(float64(h) * aspect))
		if newW < minW {
			newW = minW
			h = int32(math.Round(float64(newW) / aspect))
		}
		if edge == wmszTop {
			r.Top = r.Bottom - h
		} else {
			r.Bottom = r.Top + h
		}
		r.Right = r.Left + newW

	case wmszTopLeft, wmszTopRight, wmszBottomLeft, wmszBottomRight:
		// 拖拽四角：根据高度主导计算宽度
		if h < minH {
			h = minH
		}
		newW := int32(math.Round(float64(h) * aspect))
		if newW < minW {
			newW = minW
			h = int32(math.Round(float64(newW) / aspect))
		}

		if edge == wmszTopLeft || edge == wmszBottomLeft {
			r.Left = r.Right - newW
		} else {
			r.Right = r.Left + newW
		}

		if edge == wmszTopLeft || edge == wmszTopRight {
			r.Top = r.Bottom - h
		} else {
			r.Bottom = r.Top + h
		}
	}
}

// aspectRatioSubclassProc Win32 窗口子类过程，拦截 WM_SIZING 强制 16:9 纵横比
func aspectRatioSubclassProc(hwnd uintptr, msg uint32, wParam uintptr, lParam uintptr, uIdSubclass uintptr, dwRefData uintptr) uintptr {
	if msg == wmSizing {
		r := (*rect)(unsafe.Pointer(lParam))
		AdjustRectForAspectRatio(r, wParam, 16.0/9.0, 1280, 720)
		return 1
	}

	ret, _, _ := procDefSubclassProc.Call(hwnd, uintptr(msg), wParam, lParam)
	return ret
}

// LockWindowAspectRatio 查找目标标题的窗口并挂载 16:9 比例锁定子类过程
func LockWindowAspectRatio(windowTitle string, aspect float64) bool {
	titlePtr, err := syscall.UTF16PtrFromString(windowTitle)
	if err != nil {
		return false
	}

	var hwnd uintptr
	// 尝试轮询查找窗口（等待 Wails 窗口完全初始化显示）
	for i := 0; i < 30; i++ {
		h, _, _ := procFindWindowW.Call(0, uintptr(unsafe.Pointer(titlePtr)))
		if h != 0 {
			hwnd = h
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if hwnd == 0 {
		return false
	}

	subclassCallback := syscall.NewCallback(aspectRatioSubclassProc)
	ret, _, _ := procSetWindowSubclass.Call(
		hwnd,
		subclassCallback,
		aspectSubclassID,
		0,
	)

	return ret != 0
}
