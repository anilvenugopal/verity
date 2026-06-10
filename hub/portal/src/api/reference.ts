// Reference-list cache for the badge system. A badge needs a code's label/description/tone/icon
// from a reference table; many badges on a page share the same list, so we fetch each whitelisted
// table once and cache the promise. Components subscribe via useReferenceCodes(table).
import { useEffect, useState } from 'react'
import { api } from './client'

export interface RefCode {
  code: string
  label: string
  description: string | null
  tone: string | null
  icon: string | null
}

export type RefMap = Record<string, RefCode>

const cache = new Map<string, Promise<RefMap>>()

function load(table: string): Promise<RefMap> {
  let p = cache.get(table)
  if (!p) {
    p = api
      .get<RefCode[]>(`/api/reference/codes/${table}`)
      .then((rows) => Object.fromEntries(rows.map((r) => [r.code, r])))
      .catch((err) => {
        cache.delete(table) // let a later mount retry rather than caching the failure
        throw err
      })
    cache.set(table, p)
  }
  return p
}

/** Resolve a reference list to a code→row map (cached). Returns {} until loaded. */
export function useReferenceCodes(table: string): RefMap {
  const [map, setMap] = useState<RefMap>({})
  useEffect(() => {
    let live = true
    load(table).then((m) => live && setMap(m)).catch(() => undefined)
    return () => {
      live = false
    }
  }, [table])
  return map
}
