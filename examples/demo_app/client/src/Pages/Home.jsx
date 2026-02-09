import { Link } from '@inertiajs/react'

export default function Home({ title = 'Inertia + Vite', subtitle }) {
  return (
    <main style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif', maxWidth: 600, margin: '0 auto' }}>
      <nav style={{ marginBottom: '1.5rem' }}>
        <Link href="/" style={{ marginRight: '1rem' }}>Home</Link>
        <Link href="/todos">Todos</Link>
      </nav>

      <h1>{title}</h1>
      {subtitle && <p>{subtitle}</p>}
      <p>Welcome to your Inertia React client.</p>
    </main>
  )
}
