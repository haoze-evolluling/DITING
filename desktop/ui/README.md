# DITING 桌面管理端

Tauri + React 19 + TypeScript + Vite 实现的桌面管理界面，同时作为 `diting-service` 的内嵌 Web
管理页。后端通过回环地址上的 HTTP/WebSocket 管理 API 访问，默认 `127.0.0.1:15353`。

## 开发

```bash
npm install
npm run dev          # 浏览器开发模式（Vite :1420，/api 代理到 15353）
npm run tauri:dev    # Tauri 桌面窗口
```

连接测试端口上的服务时：

```bash
DITING_DEV_API=http://127.0.0.1:15355 npm run dev
```

## 构建

```bash
npm run build        # 类型检查并输出 dist
npm run tauri:build  # Tauri 桌面客户端安装包
```

`rust/diting-desktop-ipc/build.rs` 会在编译 `diting-service` 时读取 `dist/` 并嵌入为 Web
管理页，因此更新 Web 界面后需要重新编译服务。完整说明见
[`docs/development/desktop-ui.md`](../../docs/development/desktop-ui.md)。
