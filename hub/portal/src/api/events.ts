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

// Fired by the API client after any successful mutation (POST/PUT/DELETE) so persistent views — the
// sidebar's MY APPLICATIONS / MY APPROVALS / counts — re-fetch instead of going stale until reload.
export function emitDataChanged(): void {
  bus.dispatchEvent(new CustomEvent('data-changed'))
}

export function onDataChanged(handler: () => void): () => void {
  const listener = () => handler()
  bus.addEventListener('data-changed', listener)
  return () => bus.removeEventListener('data-changed', listener)
}
