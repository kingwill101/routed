import { Link, useForm, router } from '@inertiajs/react'

export default function Todos({ title = 'Todos', todos = [] }) {
  const { data, setData, post, processing, reset } = useForm({ text: '' })

  const addTodo = (e) => {
    e.preventDefault()
    if (!data.text.trim()) return
    post('/todos', {
      onSuccess: () => reset('text'),
    })
  }

  const toggleTodo = (id) => {
    router.put(`/todos/${id}`)
  }

  const removeTodo = (id) => {
    router.delete(`/todos/${id}`)
  }

  const remaining = todos.filter((t) => !t.done).length

  return (
    <main style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif', maxWidth: 600, margin: '0 auto' }}>
      <nav style={{ marginBottom: '1.5rem' }}>
        <Link href="/" style={{ marginRight: '1rem' }}>Home</Link>
        <Link href="/todos">Todos</Link>
      </nav>

      <h1>{title}</h1>
      <p style={{ color: '#888' }}>
        {remaining} item{remaining !== 1 ? 's' : ''} remaining
      </p>

      <form onSubmit={addTodo} style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.5rem' }}>
        <input
          type="text"
          value={data.text}
          onChange={(e) => setData('text', e.target.value)}
          placeholder="What needs to be done?"
          disabled={processing}
          style={{
            flex: 1,
            padding: '0.6em 1em',
            borderRadius: 8,
            border: '1px solid #444',
            background: 'transparent',
            color: 'inherit',
            fontSize: '1em',
          }}
        />
        <button type="submit" disabled={processing}>Add</button>
      </form>

      <ul style={{ listStyle: 'none', padding: 0 }}>
        {todos.map((todo) => (
          <li
            key={todo.id}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.75rem',
              padding: '0.5rem 0',
              borderBottom: '1px solid #333',
            }}
          >
            <input
              type="checkbox"
              checked={todo.done}
              onChange={() => toggleTodo(todo.id)}
              style={{ width: 18, height: 18, cursor: 'pointer' }}
            />
            <span
              style={{
                flex: 1,
                textDecoration: todo.done ? 'line-through' : 'none',
                opacity: todo.done ? 0.5 : 1,
              }}
            >
              {todo.text}
            </span>
            <button
              onClick={() => removeTodo(todo.id)}
              style={{ padding: '0.3em 0.6em', fontSize: '0.85em' }}
            >
              Remove
            </button>
          </li>
        ))}
      </ul>

      {todos.length === 0 && (
        <p style={{ textAlign: 'center', color: '#666', marginTop: '2rem' }}>
          No todos yet. Add one above!
        </p>
      )}
    </main>
  )
}
