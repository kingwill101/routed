import FeatureList from '../Components/FeatureList.jsx'
import Hero from '../Components/Hero.jsx'
import StatGrid from '../Components/StatGrid.jsx'

export default function Home({ title = 'Inertia + Vite' }) {
  return (
    <main
      style={{
        padding: '2rem',
        fontFamily: 'system-ui, sans-serif',
        maxWidth: '900px',
        margin: '0 auto',
      }}
    >
      <Hero
        title={title}
        subtitle="Streaming Vite assets with SSR markup."
      />
      <StatGrid />
      <FeatureList />
    </main>
  )
}
