/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_VERITY_ENV: string
  readonly VITE_AUTH_MODE: string
  readonly VITE_API_BASE: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
