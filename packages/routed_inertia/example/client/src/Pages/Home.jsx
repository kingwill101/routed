import React from 'react'
import { Link } from '@inertiajs/react'

export default function Home({ title, subtitle, links }) {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <p style={styles.eyebrow}>Routed + Inertia</p>
        <h1 style={styles.title}>{title}</h1>
        <p style={styles.subtitle}>{subtitle}</p>
      </header>

      <section style={styles.card}>
        <h2 style={styles.sectionTitle}>Quick Links</h2>
        <ul style={styles.linkList}>
          {links.map((link) => (
            <li key={link.href}>
              <Link style={styles.link} href={link.href}>
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}

const styles = {
  page: {
    minHeight: '100vh',
    padding: '3rem 2.5rem',
    background: 'linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%)',
    fontFamily: '"Source Sans 3", "Helvetica Neue", sans-serif',
    color: '#0f172a',
  },
  header: {
    maxWidth: '640px',
    marginBottom: '2.5rem',
  },
  eyebrow: {
    textTransform: 'uppercase',
    letterSpacing: '0.18em',
    fontSize: '0.75rem',
    color: '#64748b',
    marginBottom: '0.75rem',
  },
  title: {
    fontSize: '2.5rem',
    marginBottom: '0.5rem',
  },
  subtitle: {
    fontSize: '1.1rem',
    color: '#334155',
  },
  card: {
    maxWidth: '560px',
    padding: '1.5rem',
    borderRadius: '16px',
    background: '#ffffff',
    boxShadow: '0 18px 40px rgba(15, 23, 42, 0.08)',
  },
  sectionTitle: {
    marginBottom: '1rem',
    fontSize: '1.2rem',
  },
  linkList: {
    listStyle: 'none',
    padding: 0,
    margin: 0,
    display: 'grid',
    gap: '0.75rem',
  },
  link: {
    display: 'inline-block',
    padding: '0.6rem 1rem',
    borderRadius: '999px',
    background: '#0f172a',
    color: '#f8fafc',
    textDecoration: 'none',
    fontWeight: 600,
  },
}
