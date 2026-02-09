import { Link } from '@inertiajs/react'

export default function Home({ title, subtitle }) {
  return (
    <div style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif' }}>
      <h1>{title}</h1>
      <p>{subtitle}</p>
      <Link href="/contacts">View contacts &rarr;</Link>
    </div>
  )
}
