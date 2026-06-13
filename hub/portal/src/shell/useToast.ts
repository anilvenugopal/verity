import { emitToast, type ToastTone } from './ToastContext'

const ERROR_DISMISS_MS = 10_000

export interface ToastHelper {
  toast: (message: string, tone?: ToastTone, autoDismiss?: boolean, helpId?: string) => void
  success: (message: string, helpId?: string) => void
  error: (message: string, helpId?: string) => void
  warning: (message: string, helpId?: string) => void
  info: (message: string, helpId?: string) => void
}

export function useToast(): ToastHelper {
  return {
    toast: (message, tone = 'info', autoDismiss = true, helpId) => emitToast(message, tone, autoDismiss, helpId),
    success: (message, helpId) => emitToast(message, 'success', true, helpId),
    error: (message, helpId) => emitToast(message, 'error', true, helpId, ERROR_DISMISS_MS),
    warning: (message, helpId) => emitToast(message, 'warning', true, helpId),
    info: (message, helpId) => emitToast(message, 'info', true, helpId),
  }
}
