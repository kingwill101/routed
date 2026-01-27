import { createInertiaApp } from '@inertiajs/react'
import { hydrateRoot } from 'react-dom/client'
import './index.css'

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob('./Pages/**/*.jsx', { eager: true })
    return pages[`./Pages/${name}.jsx`]
  },
  setup({ el, App, props }) {
    hydrateRoot(el, <App {...props} />)
  },
})
