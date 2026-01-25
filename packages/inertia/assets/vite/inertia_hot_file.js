import fs from 'node:fs'
import path from 'node:path'

export function inertiaHotFile(options = {}) {
  const hotFile = options.hotFile ?? 'public/hot'

  return {
    name: 'inertia-hot-file',
    configureServer(server) {
      const resolvedHotFile = path.resolve(
        server.config.root ?? process.cwd(),
        hotFile,
      )

      const writeHotFile = () => {
        const origin = resolveOrigin(server, options)
        if (!origin) return
        fs.mkdirSync(path.dirname(resolvedHotFile), { recursive: true })
        fs.writeFileSync(resolvedHotFile, origin)
      }

      const cleanup = () => {
        if (fs.existsSync(resolvedHotFile)) {
          fs.unlinkSync(resolvedHotFile)
        }
      }

      server.httpServer?.once('listening', writeHotFile)
      server.httpServer?.once('close', cleanup)
    },
  }
}

function resolveOrigin(server, options) {
  const resolved = server.resolvedUrls?.local?.[0]
  if (resolved) return trimTrailingSlash(resolved)

  const config = server.config.server ?? {}
  if (config.origin) {
    return trimTrailingSlash(config.origin)
  }

  if (options.origin) {
    return trimTrailingSlash(options.origin)
  }

  const port = config.port ?? 5173
  const hostValue = config.host
  const host = hostValue === true ? 'localhost' : hostValue || 'localhost'
  const protocol = config.https ? 'https' : 'http'
  return `${protocol}://${host}:${port}`
}

function trimTrailingSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value
}
