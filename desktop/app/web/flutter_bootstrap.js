{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    // 局域网 Web 控制台必须离线可用：CanvasKit 从服务端本地加载，不再依赖 gstatic CDN。
    // full 变体只需 canvaskit/canvaskit.js + .wasm，构建脚本会裁掉 chromium/webparagraph/skwasm/wimp。
    canvasKitBaseUrl: "canvaskit/",
    canvasKitVariant: "full",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
