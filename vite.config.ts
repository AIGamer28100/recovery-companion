import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rolldownOptions: {
      output: {
        // The Firebase SDK dominates the bundle, but the services aren't all
        // needed at once: the sign-in screen needs only app+auth, and the Live
        // AI SDK isn't needed until someone actually starts a conversation.
        // Splitting by service lets those download in parallel and be cached
        // independently, so a return visit re-fetches only what changed.
        advancedChunks: {
          groups: [
            { name: 'firebase-ai', test: /node_modules\/@firebase\/ai/ },
            { name: 'firebase-firestore', test: /node_modules\/@firebase\/firestore/ },
            { name: 'firebase-auth', test: /node_modules\/@firebase\/auth/ },
            { name: 'react-vendor', test: /node_modules\/(react|react-dom|scheduler)\// },
          ],
        },
      },
    },
  },
})
