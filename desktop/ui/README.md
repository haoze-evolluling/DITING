# DITING 桌面管理端（Web）

React 19 + TypeScript + Vite 实现的 Web 管理界面，由 `diting-service` 内嵌并托管，通过浏览器
访问 `http://127.0.0.1:15353/`。后端为回环地址上的 HTTP/WebSocket 管理 API。

## 开发

```bash
npm install
npm run dev          # Vite :1420，/api 代理到 15353
```

连接测试端口上的服务时：

```bash
DITING_DEV_API=http://127.0.0.1:15355 npm run dev
```

## 构建

```bash
npm run build        # 类型检查并输出 dist
```

`rust/diting-desktop-ipc/build.rs` 会在编译 `diting-service` 时读取 `dist/` 并嵌入为 Web
管理页，因此更新 Web 界面后需要重新编译服务。完整说明见
[`docs/development/desktop-ui.md`](../../docs/development/desktop-ui.md)。
