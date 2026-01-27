import fs from 'node:fs'
import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function inertiaHotFile() {
  const hotFile = path.resolve(process.cwd(), 'public/hot')

  return {
    name: 'inertia-hot-file',
    configureServer(server) {
      const writeHotFile = () => {
        const resolved = server.resolvedUrls?.local?.[0]
        const origin = resolved ?? resolveOrigin(server)
        if (!origin) return
        fs.mkdirSync(path.dirname(hotFile), { recursive: true })
        fs.writeFileSync(hotFile, origin)
      }

      const cleanup = () => {
        if (fs.existsSync(hotFile)) {
          fs.unlinkSync(hotFile)
        }
      }

      server.httpServer?.once('listening', writeHotFile)
      server.httpServer?.once('close', cleanup)
    },
  }
}

function resolveOrigin(server) {
  const { server: config } = server.config
  if (config.origin) return config.origin
  const port = config.port ?? 5173
  const hostValue = config.host
  const host = hostValue === true ? 'localhost' : hostValue || 'localhost'
  const protocol = config.https ? 'https' : 'http'
  return `${protocol}://${host}:${port}`
}

export default defineConfig({
  plugins: [react(), inertiaHotFile()],
  server: {
    port: 5173,
    strictPort: true,
    hmr: {
      host: 'localhost',
    },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    manifest: true,
  },
})
