import { createContext, useContext, useState, type ReactNode } from 'react'

interface RegistryScope {
  appId: string | null
  appName: string | null
  appCode: string | null
  setScope: (id: string | null, name: string | null, code?: string | null) => void
}

const Ctx = createContext<RegistryScope>({ appId: null, appName: null, appCode: null, setScope: () => {} })

export function RegistryProvider({ children }: { children: ReactNode }) {
  const [appId, setAppId] = useState<string | null>(() => localStorage.getItem('verity.registry.appId'))
  const [appName, setAppName] = useState<string | null>(() => localStorage.getItem('verity.registry.appName'))
  const [appCode, setAppCode] = useState<string | null>(() => localStorage.getItem('verity.registry.appCode'))

  const setScope = (id: string | null, name: string | null, code?: string | null) => {
    setAppId(id)
    setAppName(name)
    setAppCode(code ?? null)
    if (id) {
      localStorage.setItem('verity.registry.appId', id)
      localStorage.setItem('verity.registry.appName', name ?? '')
      localStorage.setItem('verity.registry.appCode', code ?? '')
    } else {
      localStorage.removeItem('verity.registry.appId')
      localStorage.removeItem('verity.registry.appName')
      localStorage.removeItem('verity.registry.appCode')
    }
  }

  return <Ctx.Provider value={{ appId, appName, appCode, setScope }}>{children}</Ctx.Provider>
}

export const useRegistryScope = () => useContext(Ctx)
