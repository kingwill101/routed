import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { inertiaHotFile } from './inertia_hot_file.js'

export default defineConfig({
  plugins: [react(), inertiaHotFile()],
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
