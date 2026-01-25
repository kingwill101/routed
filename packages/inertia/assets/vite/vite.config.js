import { defineConfig } from 'vite'

import { inertiaHotFile } from './inertia_hot_file.js'

export default defineConfig({
  plugins: [inertiaHotFile()],
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    manifest: true,
  },
})
