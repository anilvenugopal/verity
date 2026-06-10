import { createContext, useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { api, ApiException } from '@/api/client'
import { onAuth } from '@/api/events'
import type { ApiError, AuthState, Principal } from '@/api/types'

export interface SessionValue {
  principal: Principal | null
  authState: AuthState
  refresh: () => Promise<void>
}

export const SessionContext = createContext<SessionValue | null>(null)

export function SessionProvider({ children }: { children: ReactNode }) {
  const [principal, setPrincipal] = useState<Principal | null>(null)
  const [authState, setAuthState] = useState<AuthState>('loading')

  // Ref mirror so event handlers read the live state without re-subscribing.
  const stateRef = useRef<AuthState>('loading')
  stateRef.current = authState

  const refresh = useCallback(async () => {
    try {
      const me = await api.get<Principal>('/me')
      setPrincipal(me)
      setAuthState('authenticated')
    } catch (err) {
      setPrincipal(null)
      if (err instanceof ApiException && err.status === 403) {
        setAuthState(err.body.code === 'account_disabled' ? 'disabled' : 'forbidden')
      } else {
        // 401 on the initial /me means "not signed in" → sign-in page, not a takeover.
        setAuthState('unauthenticated')
      }
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  useEffect(() => {
    // A 401 mid-session (after we were authenticated) is an expiry → takeover.
    const offExpired = onAuth('session-expired', () => {
      if (stateRef.current === 'authenticated') setAuthState('session_expired')
    })
    const offForbidden = onAuth('forbidden', (detail) => {
      const code = (detail as ApiError | undefined)?.code
      if (code === 'account_disabled') setAuthState('disabled')
      // route-level forbidden is handled by the route boundary; we don't globally
      // hijack the shell on every write-level 403.
    })
    return () => {
      offExpired()
      offForbidden()
    }
  }, [])

  return (
    <SessionContext.Provider value={{ principal, authState, refresh }}>
      {children}
    </SessionContext.Provider>
  )
}
