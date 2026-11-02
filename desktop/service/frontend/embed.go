package frontend

import "embed"

// Assets 包含前端构建后的静态文件
//
//go:embed all:dist
var Assets embed.FS
