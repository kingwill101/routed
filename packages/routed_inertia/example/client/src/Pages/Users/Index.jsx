import React from 'react'
import { Link } from '@inertiajs/react'

export default function UsersIndex({ title, users, links }) {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <p style={styles.eyebrow}>Directory</p>
        <h1 style={styles.title}>{title}</h1>
      </header>

      <section style={styles.card}>
        <ul style={styles.userList}>
          {users.map((user) => (
            <li key={user.id} style={styles.userItem}>
              <span style={styles.userAvatar}>{user.name[0]}</span>
              <span>{user.name}</span>
            </li>
          ))}
        </ul>
      </section>

      <nav style={styles.nav}>
        {links.map((link) => (
          <Link key={link.href} style={styles.navLink} href={link.href}>
            {link.label}
          </Link>
        ))}
      </nav>
    </div>
  )
}

const styles = {
  page: {
    minHeight: '100vh',
    padding: '3rem 2.5rem',
    background: 'linear-gradient(140deg, #fff7ed 0%, #fde68a 100%)',
    fontFamily: '"Source Sans 3", "Helvetica Neue", sans-serif',
    color: '#1f2937',
  },
  header: {
    marginBottom: '2rem',
  },
  eyebrow: {
    textTransform: 'uppercase',
    letterSpacing: '0.16em',
    fontSize: '0.75rem',
    color: '#b45309',
  },
  title: {
    fontSize: '2.2rem',
    margin: '0.5rem 0 0',
  },
  card: {
    maxWidth: '520px',
    background: '#ffffff',
    borderRadius: '18px',
    padding: '1.5rem',
    boxShadow: '0 18px 40px rgba(120, 53, 15, 0.16)',
  },
  userList: {
    listStyle: 'none',
    margin: 0,
    padding: 0,
    display: 'grid',
    gap: '0.75rem',
  },
  userItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '0.75rem',
    padding: '0.5rem 0.2rem',
    fontWeight: 600,
  },
  userAvatar: {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: '36px',
    height: '36px',
    borderRadius: '50%',
    background: '#f97316',
    color: '#fff7ed',
    fontWeight: 700,
  },
  nav: {
    marginTop: '2rem',
    display: 'flex',
    gap: '0.75rem',
  },
  navLink: {
    textDecoration: 'none',
    fontWeight: 600,
    color: '#1f2937',
    borderBottom: '2px solid transparent',
  },
}
