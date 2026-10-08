import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import pkg from './package.json'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    vue({
      template: {
        compilerOptions: {
          isCustomElement: (tag) => tag.startsWith('md-'),
        },
      },
    }),
    tailwindcss(),
  ],
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
})

