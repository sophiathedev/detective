import {Socket} from "phoenix"

export function connectGameSocket(csrfToken) {
  const socket = new Socket("/socket", {
    params: {_csrf_token: csrfToken},
  })

  socket.connect()
  return socket
}
