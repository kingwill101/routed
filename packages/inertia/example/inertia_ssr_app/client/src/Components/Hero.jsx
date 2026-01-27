export default function Hero({ title, subtitle }) {
  return (
    <section
      style={{
        padding: '2rem',
        borderRadius: '16px',
        background: 'linear-gradient(135deg, #fef3c7, #fee2e2)',
        border: '1px solid #fde68a',
      }}
    >
      <p style={{ margin: 0, textTransform: 'uppercase', letterSpacing: '0.2em' }}>
        SSR Preview
      </p>
      <h1 style={{ margin: '0.5rem 0 0.25rem' }}>{title}</h1>
      <p style={{ margin: 0, color: '#6b7280' }}>{subtitle}</p>
    </section>
  )
}
