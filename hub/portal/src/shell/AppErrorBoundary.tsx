import { Component, type ErrorInfo, type ReactNode } from 'react'

interface Props { children: ReactNode }
interface State { error: Error | null; errorId: string | null }

let _idCounter = 0

export class AppErrorBoundary extends Component<Props, State> {
  state: State = { error: null, errorId: null }

  static getDerivedStateFromError(error: Error): State {
    return { error, errorId: `ERR-${++_idCounter}` }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[AppErrorBoundary]', error, info.componentStack)
  }

  render() {
    if (this.state.error) {
      return (
        <div className="page-takeover">
          <div className="page-takeover__body">
            <h1 className="page-takeover__title">Something went wrong</h1>
            <p className="page-takeover__detail">
              An unexpected error occurred. Reload to try again.
            </p>
            {this.state.errorId && (
              <p className="page-takeover__id">Error ID: <code>{this.state.errorId}</code></p>
            )}
            <button
              className="btn btn--primary"
              onClick={() => { this.setState({ error: null, errorId: null }); window.location.reload() }}
            >
              Reload
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
