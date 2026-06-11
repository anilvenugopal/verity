import { describe, it, expect } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ToastProvider } from '../ToastContext'
import { Toast } from '../Toast'
import { useToast } from '../useToast'

function Trigger({ message }: { message: string }) {
  const { success } = useToast()
  return <button onClick={() => success(message)}>fire</button>
}

function Fixture({ message }: { message: string }) {
  return (
    <ToastProvider>
      <Trigger message={message} />
      <Toast />
    </ToastProvider>
  )
}

describe('Toast', () => {
  it('shows the toast message after firing', () => {
    render(<Fixture message="Hello toast" />)
    expect(screen.queryByText('Hello toast')).toBeNull()
    fireEvent.click(screen.getByText('fire'))
    expect(screen.getByText('Hello toast')).toBeDefined()
  })

  it('removes the toast when dismiss is clicked', () => {
    render(<Fixture message="Dismissible" />)
    fireEvent.click(screen.getByText('fire'))
    expect(screen.getByText('Dismissible')).toBeDefined()
    fireEvent.click(screen.getByLabelText('Dismiss'))
    expect(screen.queryByText('Dismissible')).toBeNull()
  })

  it('can fire multiple toasts', () => {
    render(<Fixture message="multi" />)
    fireEvent.click(screen.getByText('fire'))
    fireEvent.click(screen.getByText('fire'))
    expect(screen.getAllByText('multi').length).toBe(2)
  })
})
