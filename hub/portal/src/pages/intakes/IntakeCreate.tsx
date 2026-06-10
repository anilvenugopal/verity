import { type FormEvent, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, ApiException } from '@/api/client'
import type { Intake } from '@/api/types'
import '../applications/ApplicationWorkspace.css' // shared workspace layout (band/card)
import '../applications/OnboardForm.css'

// Create an intake under an application (FR-024) or edit a revisable one (FR-034). Mirrors OnboardForm's
// dual create/edit shape but minimal: an intake starts as just a title + optional description; the
// assessment/classification come later on the detail page. Route params decide the mode —
// `/applications/:appId/intakes/new` (create) vs `/intakes/:id/edit` (edit, prefilled, PUT).
export function IntakeCreate() {
  const navigate = useNavigate()
  const { appId, id } = useParams<{ appId: string; id: string }>()
  const editing = !!id
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [appName, setAppName] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [attempted, setAttempted] = useState(false)
  const [loaded, setLoaded] = useState(!editing)

  // Create mode: show the parent application's name for context. Edit mode: prefill from the intake.
  useEffect(() => {
    if (editing) return
    if (appId) api.get<{ name: string }>(`/api/applications/${appId}`).then((a) => setAppName(a.name)).catch(() => undefined)
  }, [appId, editing])

  useEffect(() => {
    if (!id) return
    api.get<Intake>(`/api/intakes/${id}`).then((i) => {
      setTitle(i.title); setDescription(i.description ?? ''); setLoaded(true)
      api.get<{ name: string }>(`/api/applications/${i.application_id}`).then((a) => setAppName(a.name)).catch(() => undefined)
    }).catch(() => setError('Could not load the intake.'))
  }, [id])

  const titleOk = title.trim().length > 0
  const dirty = title.trim() !== '' || description.trim() !== ''

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    if (!titleOk) { setAttempted(true); document.getElementById('intake-title')?.focus(); return }
    setBusy(true); setError('')
    const body = { title: title.trim(), description: description.trim() || null }
    try {
      const intake = editing
        ? await api.put<Intake>(`/api/intakes/${id}`, body)
        : await api.post<Intake>(`/api/applications/${appId}/intakes`, body)
      navigate(`/intakes/${intake.intake_id}`)
    } catch (err) {
      setError(err instanceof ApiException ? err.body.detail : 'Save failed.')
      setBusy(false)
    }
  }

  function cancel() {
    if (dirty && !editing && !window.confirm('Discard this intake? Your changes will be lost.')) return
    navigate(editing ? `/intakes/${id}` : appId ? `/applications/${appId}` : '/applications')
  }

  if (!loaded) {
    return <div className="canvas-pad"><div className="card"><div className="empty-state"><div className="empty-state__body">{error || 'Loading…'}</div></div></div></div>
  }

  return (
    <form className="canvas-pad" onSubmit={submit} noValidate>
      <div className="page-head">
        <div>
          <div className="page-head__title">{editing ? 'Edit intake' : 'New intake'}</div>
          <div className="page-head__sub">
            {editing
              ? 'Revise this intake. Risk assessment and approval are on the intake page.'
              : <>A proposed AI use case under {appName ? <strong>{appName}</strong> : 'this application'}. Give it a title — you’ll assess and submit it from its detail page.</>}
          </div>
        </div>
      </div>

      <div className="card">
        <div className="rail-panel__title">Identity</div>
        <div className="field-grid">
          <div className="field field-full">
            <div className="form-field">
              <label className="form-label is-required" htmlFor="intake-title">Title</label>
              <input className={`input${attempted && !titleOk ? ' input--error' : ''}`} id="intake-title" placeholder="Submission triage assistant"
                     value={title} onChange={(e) => setTitle(e.target.value)} />
              <span className="input-hint">A short name for the use case.</span>
              {attempted && !titleOk && <span className="input-error-text">Enter a title.</span>}
            </div>
          </div>
          <div className="field field-full">
            <div className="form-field">
              <label className="form-label" htmlFor="intake-desc">Description</label>
              <textarea className="input" id="intake-desc" placeholder="What the use case does and the decision it supports. Optional."
                        value={description} onChange={(e) => setDescription(e.target.value)} />
              <span className="input-hint">Optional — context for reviewers.</span>
            </div>
          </div>
        </div>

        {error && <div className="field"><span className="input-error-text">{error}</span></div>}

        <div className="field l-cluster">
          <button type="submit" className="btn btn--primary btn--md" disabled={busy}>{busy ? 'Saving…' : editing ? 'Save changes' : 'Create intake'}</button>
          <button type="button" className="btn btn--ghost btn--md" disabled={busy} onClick={cancel}>Cancel</button>
        </div>
      </div>
    </form>
  )
}
