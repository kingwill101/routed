const items = [
  'Server-rendered HTML for fast first paint',
  'Hydration-ready React components',
  'Vite dev server assets in development',
]

export default function FeatureList() {
  return (
    <section style={{ marginTop: '2rem' }}>
      <h2 style={{ marginBottom: '0.5rem' }}>What this demo shows</h2>
      <ul style={{ margin: 0, paddingLeft: '1.25rem', color: '#374151' }}>
        {items.map((item) => (
          <li key={item} style={{ marginBottom: '0.35rem' }}>
            {item}
          </li>
        ))}
      </ul>
    </section>
  )
}
