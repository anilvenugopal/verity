// Module-level event bus the API client uses to signal auth-state changes to the SessionProvider
// without a circular import. 401 → session-expired; 403 (route-level) → forbidden.
type AuthEvent = 'session-expired' | 'forbidden'

const bus = new EventTarget()

export function emitAuth(event: AuthEvent, detail?: unknown): void {
  bus.dispatchEvent(new CustomEvent(event, { detail }))
}

export function onAuth(event: AuthEvent, handler: (detail: unknown) => void): () => void {
  const listener = (e: Event) => handler((e as CustomEvent).detail)
  bus.addEventListener(event, listener)
  return () => bus.removeEventListener(event, listener)
}
