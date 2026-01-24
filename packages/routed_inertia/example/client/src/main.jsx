import { createInertiaApp } from '@inertiajs/react'
import { createRoot } from 'react-dom/client'

const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })

createInertiaApp({
  resolve: (name) => {
    const page = pages[`./Pages/${name}.jsx`]
    return page?.default
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
  progress: {
    color: '#1f2937',
  },
})
