// The single typed fetch wrapper. Every API call goes through here — never raw fetch in components.
// - always sends the session cookie (credentials: 'include')
// - 401 → emits 'session-expired' (the SessionProvider shows the takeover)
// - 403 → emits 'forbidden' with the parsed ApiError (route-level forbidden takeover)
// - returns typed JSON or throws ApiError
import { emitAuth, emitDataChanged } from './events'
import type { ApiError } from './types'

export class ApiException extends Error {
  constructor(public readonly status: number, public readonly body: ApiError) {
    super(body.detail)
    this.name = 'ApiException'
  }
}

async function parseError(res: Response): Promise<ApiError> {
  try {
    const body = (await res.json()) as Partial<ApiError>
    return {
      code: body.code ?? 'error',
      detail: body.detail ?? res.statusText,
      request_id: body.request_id ?? '',
    }
  } catch {
    return { code: 'error', detail: res.statusText, request_id: '' }
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: 'include',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  if (res.status === 401) {
    emitAuth('session-expired')
    throw new ApiException(401, await parseError(res))
  }
  if (res.status === 403) {
    const err = await parseError(res)
    emitAuth('forbidden', err)
    throw new ApiException(403, err)
  }
  if (!res.ok) {
    throw new ApiException(res.status, await parseError(res))
  }
  // PATCH is only used for actor-scoped writes (preferences) that don't affect shared views.
  if (method !== 'GET' && method !== 'PATCH') emitDataChanged()
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export const api = {
  get:   <T>(path: string) => request<T>('GET', path),
  post:  <T>(path: string, body?: unknown) => request<T>('POST', path, body ?? {}),
  put:   <T>(path: string, body?: unknown) => request<T>('PUT', path, body ?? {}),
  patch: <T>(path: string, body?: unknown) => request<T>('PATCH', path, body ?? {}),
  del:   <T>(path: string) => request<T>('DELETE', path),
}
