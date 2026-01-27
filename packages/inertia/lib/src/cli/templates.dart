/// Provides string templates used for CLI scaffolding.
///
/// These templates are written to disk when creating or installing projects.
///
/// ```dart
/// await configureInertiaProject(dir, InertiaFramework.react);
/// ```
/// Template for the Vite hot file plugin used by Inertia.
const String inertiaHotFilePlugin = """import fs from 'node:fs'
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
  return `\${protocol}://\${host}:\${port}`
}

function trimTrailingSlash(value) {
  return value.endsWith('/') ? value.slice(0, -1) : value
}
""";

/// Vite config template for React + Inertia.
const String inertiaReactConfig = """import { defineConfig } from 'vite'
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
""";

/// Vite config template for Vue + Inertia.
const String inertiaVueConfig = """import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { inertiaHotFile } from './inertia_hot_file.js'

export default defineConfig({
  plugins: [vue(), inertiaHotFile()],
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
""";

/// Vite config template for Svelte + Inertia.
const String inertiaSvelteConfig = """import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { inertiaHotFile } from './inertia_hot_file.js'

export default defineConfig({
  plugins: [svelte(), inertiaHotFile()],
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
""";

/// Main entry template for a React + Inertia app.
const String inertiaReactMain =
    """import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'
import './index.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })
    return pages[`./Pages/\${name}.jsx`]
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
""";

/// SSR entry template for a React + Inertia app.
const String inertiaReactSsr =
    """import { createInertiaApp } from '@inertiajs/react'
import createServer from '@inertiajs/react/server'
import ReactDOMServer from 'react-dom/server'

createServer(page =>
  createInertiaApp({
    page,
    render: ReactDOMServer.renderToString,
    resolve: (name) => {
      const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })
      return pages[`./Pages/\${name}.jsx`]
    },
    setup: ({ App, props }) => <App {...props} />,
  }),
)
""";

/// Main entry template for a Vue + Inertia app.
const String inertiaVueMain = """import { createApp, h } from 'vue'
import { createInertiaApp } from '@inertiajs/vue3'
import './style.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./Pages/**/*.vue', { eager: true })
    return pages[`./Pages/\${name}.vue`]
  },
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) }).use(plugin).mount(el)
  },
})
""";

/// SSR entry template for a Vue + Inertia app.
const String inertiaVueSsr =
    """import { createInertiaApp } from '@inertiajs/vue3'
import createServer from '@inertiajs/vue3/server'
import { renderToString } from '@vue/server-renderer'
import { createSSRApp, h } from 'vue'

createServer(page =>
  createInertiaApp({
    page,
    render: renderToString,
    resolve: (name) => {
      const pages = import.meta.glob('./Pages/**/*.vue', { eager: true })
      return pages[`./Pages/\${name}.vue`]
    },
    setup({ App, props, plugin }) {
      return createSSRApp({ render: () => h(App, props) }).use(plugin)
    },
  }),
)
""";

/// Main entry template for a Svelte + Inertia app.
const String inertiaSvelteMain =
    """import { createInertiaApp } from '@inertiajs/svelte'
import './app.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./Pages/**/*.svelte', { eager: true })
    return pages[`./Pages/\${name}.svelte`]
  },
  setup({ el, App, props }) {
    new App({ target: el, props })
  },
})
""";

/// SSR entry template for a Svelte + Inertia app.
const String inertiaSvelteSsr =
    """import { createInertiaApp } from '@inertiajs/svelte'
import createServer from '@inertiajs/svelte/server'

createServer(page =>
  createInertiaApp({
    page,
    resolve: (name) => {
      const pages = import.meta.glob('./Pages/**/*.svelte', { eager: true })
      return pages[`./Pages/\${name}.svelte`]
    },
    setup({ App, props }) {
      return App.render(props)
    },
  }),
)
""";

/// Starter page template for a React + Inertia app.
const String inertiaReactPage =
    """export default function Home({ title = 'Inertia + Vite' }) {
  return (
    <main style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif' }}>
      <h1>{title}</h1>
      <p>Welcome to your Inertia React client.</p>
    </main>
  )
}
""";

/// Starter page template for a Vue + Inertia app.
const String inertiaVuePage = """<script setup>
const props = defineProps({
  title: {
    type: String,
    default: 'Inertia + Vite',
  },
})
</script>

<template>
  <main style="padding: 2rem; font-family: system-ui, sans-serif;">
    <h1>{{ props.title }}</h1>
    <p>Welcome to your Inertia Vue client.</p>
  </main>
</template>
""";

/// Starter page template for a Svelte + Inertia app.
const String inertiaSveltePage = """<script>
  export let title = 'Inertia + Vite'
</script>

<main style="padding: 2rem; font-family: system-ui, sans-serif;">
  <h1>{title}</h1>
  <p>Welcome to your Inertia Svelte client.</p>
</main>
""";
