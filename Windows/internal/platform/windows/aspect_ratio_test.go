package windows

import (
	"math"
	"testing"
)

func TestAdjustRectForAspectRatio(t *testing.T) {
	aspect := 16.0 / 9.0
	minW := int32(1280)
	minH := int32(720)

	tests := []struct {
		name     string
		initial  rect
		edge     uintptr
		expected rect
	}{
		{
			name:    "拖拽右边缘拉宽至 1600",
			initial: rect{Left: 100, Top: 100, Right: 1700, Bottom: 820}, // w=1600
			edge:    wmszRight,
			// w=1600, newH = round(1600 / (16/9)) = round(900) = 900 -> Bottom = 100 + 900 = 1000
			expected: rect{Left: 100, Top: 100, Right: 1700, Bottom: 1000},
		},
		{
			name:    "拖拽下边缘拉高至 900",
			initial: rect{Left: 100, Top: 100, Right: 1380, Bottom: 1000}, // h=900
			edge:    wmszBottom,
			// h=900, newW = round(900 * 16/9) = 1600 -> Right = 100 + 1600 = 1700
			expected: rect{Left: 100, Top: 100, Right: 1700, Bottom: 1000},
		},
		{
			name:    "拖拽小于最小值限制",
			initial: rect{Left: 100, Top: 100, Right: 900, Bottom: 500}, // w=800, h=400
			edge:    wmszRight,
			// minW=1280, minH=720 -> Right=100+1280=1380, Bottom=100+720=820
			expected: rect{Left: 100, Top: 100, Right: 1380, Bottom: 820},
		},
		{
			name:    "拖拽右下角拉伸至 900 高度",
			initial: rect{Left: 100, Top: 100, Right: 1500, Bottom: 1000}, // h=900
			edge:    wmszBottomRight,
			// h=900, newW=1600 -> Right=1700, Bottom=1000
			expected: rect{Left: 100, Top: 100, Right: 1700, Bottom: 1000},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := tt.initial
			AdjustRectForAspectRatio(&r, tt.edge, aspect, minW, minH)

			w := r.Right - r.Left
			h := r.Bottom - r.Top
			ratio := float64(w) / float64(h)

			if math.Abs(ratio-aspect) > 0.01 {
				t.Errorf("纵横比不匹配: got %.4f, want %.4f", ratio, aspect)
			}

			if r != tt.expected {
				t.Errorf("调整坐标不符合预期: got %+v, want %+v", r, tt.expected)
			}
		})
	}
}
