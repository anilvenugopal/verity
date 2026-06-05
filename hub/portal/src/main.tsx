import React from 'react'
import ReactDOM from 'react-dom/client'
import './styles/index.css'
import { loadSprite } from './sprite'
import { App } from './App'

// Inline the icon sprite, then mount the app.
void loadSprite()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
