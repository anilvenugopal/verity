import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

// Dev proxy: the portal calls /api/* (rewritten to the hub root), /auth/*, and /me — all
// forwarded to the hub at :8000. In production FastAPI serves the built dist at / and the API
// routes coexist at their native paths (no proxy needed).
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true, rewrite: (p) => p.replace(/^\/api/, '') },
      '/auth': { target: 'http://localhost:8000', changeOrigin: true },
      '/me': { target: 'http://localhost:8000', changeOrigin: true },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
  },
})
