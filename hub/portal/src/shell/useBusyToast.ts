import { useState } from 'react'
import { useToast } from './useToast'
import type { ToastTone } from './ToastContext'

/**
 * Wraps an async operation: tracks busy state, fires a success/error toast on completion.
 * Components can still manage their own optimistic UI — this only adds the feedback layer.
 */
export function useBusyToast() {
  const [busy, setBusy] = useState(false)
  const { success } = useToast()

  async function run<T>(
    fn: () => Promise<T>,
    successMsg: string,
    opts?: { tone?: ToastTone; onSuccess?: (v: T) => void },
  ): Promise<T | undefined> {
    setBusy(true)
    try {
      const result = await fn()
      success(successMsg)
      opts?.onSuccess?.(result)
      return result
    } catch {
      // client.ts already fires the error toast; nothing extra needed here
      return undefined
    } finally {
      setBusy(false)
    }
  }

  return { busy, run }
}
