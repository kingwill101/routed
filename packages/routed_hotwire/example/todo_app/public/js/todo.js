document.addEventListener('turbo:frame-load', (event) => {
  const frame = event.target;
  if (frame.id === 'todo_form') {
    const input = frame.querySelector('input[name="title"]');
    if (input) {
      input.focus();
      input.select();
    }
  }
});

document.addEventListener('submit', (event) => {
  const form = event.target;
  if (form.matches('[data-confirm-delete]')) {
    if (!confirm('Delete this task?')) {
      event.preventDefault();
    }
  }
});

function connectTurboSocket() {
  if (!window.Turbo) {
    return;
  }

  const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
  const meta = document.querySelector('meta[name="turbo-stream-todos"]');
  const source = document.querySelector('turbo-cable-stream-source[signed-stream-name]');
  const signedTopic =
    (meta && meta.content ? meta.content.trim() : '') ||
    (source && source.getAttribute('signed-stream-name')
      ? source.getAttribute('signed-stream-name').trim()
      : '') ||
    'todos';
  const url = `${protocol}://${window.location.host}/ws/todos?topic=${encodeURIComponent(signedTopic)}`;
  const socket = new WebSocket(url);

  socket.addEventListener('message', (event) => {
    window.Turbo.renderStreamMessage(event.data);
  });

  socket.addEventListener('close', () => {
    setTimeout(connectTurboSocket, 2000);
  });

  socket.addEventListener('error', () => {
    socket.close();
  });
}

connectTurboSocket();
