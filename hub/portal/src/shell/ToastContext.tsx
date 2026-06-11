import { createContext, useContext, useReducer, type ReactNode } from 'react'

export type ToastTone = 'success' | 'warning' | 'error' | 'info'

export interface ToastItem {
  id: number
  message: string
  tone: ToastTone
  autoDismiss: boolean
  helpId?: string  // optional corpus path — renders "Learn more →" link in the toast
}

type Action =
  | { type: 'ADD'; toast: ToastItem }
  | { type: 'REMOVE'; id: number }

function reducer(state: ToastItem[], action: Action): ToastItem[] {
  switch (action.type) {
    case 'ADD': return [...state, action.toast]
    case 'REMOVE': return state.filter((t) => t.id !== action.id)
  }
}

const ToastStateContext = createContext<ToastItem[]>([])
const ToastDispatchContext = createContext<React.Dispatch<Action>>(() => {})

let _dispatch: React.Dispatch<Action> | null = null
let _counter = 0

/** Module-level fire — usable outside React (e.g. api/client.ts). */
export function emitToast(message: string, tone: ToastTone = 'info', autoDismiss = true, helpId?: string) {
  _dispatch?.({ type: 'ADD', toast: { id: ++_counter, message, tone, autoDismiss, helpId } })
}

export function removeToast(id: number) {
  _dispatch?.({ type: 'REMOVE', id })
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, dispatch] = useReducer(reducer, [])
  _dispatch = dispatch
  return (
    <ToastDispatchContext.Provider value={dispatch}>
      <ToastStateContext.Provider value={toasts}>
        {children}
      </ToastStateContext.Provider>
    </ToastDispatchContext.Provider>
  )
}

export function useToasts() { return useContext(ToastStateContext) }
export function useToastDispatch() { return useContext(ToastDispatchContext) }
