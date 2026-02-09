import { Link, useForm, router } from '@inertiajs/react'

export default function Contacts({ title, contacts }) {
  const { data, setData, post, processing } = useForm({ name: '', email: '' })

  function submit(e) {
    e.preventDefault()
    post('/contacts', { onSuccess: () => setData({ name: '', email: '' }) })
  }

  function destroy(id) {
    if (confirm('Delete this contact?')) {
      router.delete(`/contacts/${id}`)
    }
  }

  return (
    <div style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif' }}>
      <h1>{title}</h1>
      <Link href="/">&larr; Home</Link>

      <form onSubmit={submit} style={{ margin: '1.5rem 0' }}>
        <input
          placeholder="Name"
          value={data.name}
          onChange={e => setData('name', e.target.value)}
          style={{ marginRight: '0.5rem', padding: '0.4rem' }}
        />
        <input
          placeholder="Email"
          value={data.email}
          onChange={e => setData('email', e.target.value)}
          style={{ marginRight: '0.5rem', padding: '0.4rem' }}
        />
        <button type="submit" disabled={processing} style={{ padding: '0.4rem 1rem' }}>
          Add
        </button>
      </form>

      <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: '600px' }}>
        <thead>
          <tr>
            <th style={th}>Name</th>
            <th style={th}>Email</th>
            <th style={th}></th>
          </tr>
        </thead>
        <tbody>
          {contacts.map(c => (
            <tr key={c.id}>
              <td style={td}>{c.name}</td>
              <td style={td}>{c.email}</td>
              <td style={td}>
                <button onClick={() => destroy(c.id)} style={{ color: 'red', cursor: 'pointer', background: 'none', border: 'none' }}>
                  Delete
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

const th = { textAlign: 'left', borderBottom: '2px solid #ccc', padding: '0.5rem' }
const td = { borderBottom: '1px solid #eee', padding: '0.5rem' }
