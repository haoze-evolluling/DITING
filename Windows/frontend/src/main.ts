import { createApp } from 'vue';
import App from './App.vue';
import './style.css';
import './api/screenshot';

// 引入 Material Web Components 全量组件库
import '@material/web/all.js';

// 初始化 M3 Dynamic Color 调色系统
import { themeManager } from './theme/dynamic-color';
themeManager.applyTheme();

createApp(App).mount('#app');
