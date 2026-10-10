import { createApp } from 'vue';
import App from './App.vue';
import './style.css';
import './api/screenshot';

// 引入 Material Web Components 全量组件库
import '@material/web/all.js';

// 初始化浅色 / 深色主题
import { themeManager } from './theme/theme';
themeManager.applyTheme();

createApp(App).mount('#app');
