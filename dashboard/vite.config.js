import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// In dev, forward API + websocket calls to the backend so the page and API share an origin
// (same as production, where Express serves the built dashboard).
const api = 'http://localhost:3000'
const routes = ['/auth', '/courses', '/sessions', '/attendance', '/devices', '/me', '/health']

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      ...Object.fromEntries(routes.map((r) => [r, api])),
      '/socket.io': { target: api, ws: true },
    },
  },
})
