import '@testing-library/jest-dom/vitest'
import { afterEach } from 'vitest'
import { cleanup } from '@testing-library/react'

// Testing Library's auto-cleanup only self-registers when `afterEach` is a
// global; this project runs Vitest without `globals: true`, so wire it up
// explicitly to unmount components between tests.
afterEach(() => {
  cleanup()
})
