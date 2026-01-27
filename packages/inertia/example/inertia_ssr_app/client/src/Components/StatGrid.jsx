const stats = [
  { label: 'SSR port', value: '13714' },
  { label: 'Client port', value: '5173' },
  { label: 'Server port', value: '8080' },
]

export default function StatGrid() {
  return (
    <section
      style={{
        marginTop: '1.5rem',
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
        gap: '0.75rem',
      }}
    >
      {stats.map((stat) => (
        <div
          key={stat.label}
          style={{
            padding: '1rem',
            borderRadius: '12px',
            border: '1px solid #e5e7eb',
            background: '#ffffff',
          }}
        >
          <p style={{ margin: 0, fontSize: '0.75rem', color: '#6b7280' }}>
            {stat.label}
          </p>
          <p style={{ margin: '0.4rem 0 0', fontSize: '1.25rem' }}>
            {stat.value}
          </p>
        </div>
      ))}
    </section>
  )
}
