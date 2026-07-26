import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import PrimaryCard from './PrimaryCard'

describe('PrimaryCard', () => {
  it('shows the loading state and keeps the log/live-region contract', () => {
    render(
      <PrimaryCard loading={true} error={null} script={null} onSpeakAgain={vi.fn()} />,
    )

    const log = screen.getByRole('log')
    expect(log).toHaveAttribute('aria-live', 'polite')
    expect(screen.getByText(/reaching out to your companion/i)).toBeInTheDocument()
  })

  it('shows an error message and no loading/script content on error', () => {
    render(
      <PrimaryCard
        loading={false}
        error="network down"
        script={null}
        onSpeakAgain={vi.fn()}
      />,
    )

    expect(
      screen.getByText(/couldn.t reach the ai companion right now/i),
    ).toBeInTheDocument()
    expect(screen.queryByText(/reaching out to your companion/i)).not.toBeInTheDocument()
    const log = screen.getByRole('log')
    expect(log).toHaveAttribute('aria-live', 'polite')
  })

  it('renders the script and fires onSpeakAgain when the button is clicked', async () => {
    const user = userEvent.setup()
    const onSpeakAgain = vi.fn()
    render(
      <PrimaryCard
        loading={false}
        error={null}
        script="Take a slow breath in for four counts."
        onSpeakAgain={onSpeakAgain}
      />,
    )

    expect(screen.getByText(/take a slow breath in for four counts/i)).toBeInTheDocument()
    const button = screen.getByRole('button', { name: /speak again/i })

    await user.click(button)
    expect(onSpeakAgain).toHaveBeenCalledTimes(1)

    const log = screen.getByRole('log')
    expect(log).toHaveAttribute('aria-live', 'polite')
  })

  it('shows the empty-state prompt when there is no script, error, or loading', () => {
    render(
      <PrimaryCard loading={false} error={null} script={null} onSpeakAgain={vi.fn()} />,
    )

    expect(
      screen.getByText(/tap a card below whenever you need it/i),
    ).toBeInTheDocument()
    const log = screen.getByRole('log')
    expect(log).toHaveAttribute('aria-live', 'polite')
  })
})
