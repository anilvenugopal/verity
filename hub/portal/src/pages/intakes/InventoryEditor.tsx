import { type ReactNode } from 'react'

// Generic multi-entry editor (FR-026 / EU Art 10 & 14 / ICO register): a list of bordered item cards
// with add + remove, each item's fields rendered by the caller. Read-only when !canEdit. The .inv*
// classes are page-local (Assessment.css); item fields reuse .field-grid/.form-field/.input.
export function InventoryEditor<T>({
  items, onChange, blank, render, addLabel, emptyText, canEdit, label,
}: {
  items: T[]
  onChange: (next: T[]) => void
  blank: () => T
  render: (item: T, set: (patch: Partial<T>) => void, index: number) => ReactNode
  addLabel: string
  emptyText: string
  canEdit: boolean
  label?: (item: T, index: number) => string
}) {
  const set = (i: number, patch: Partial<T>) => onChange(items.map((it, j) => (j === i ? { ...it, ...patch } : it)))
  const remove = (i: number) => onChange(items.filter((_, j) => j !== i))
  return (
    <div className="inv">
      {items.length === 0 && <p className="inv__empty">{emptyText}</p>}
      {items.map((it, i) => (
        <div className="inv__item" key={i}>
          <div className="inv__item-head">
            <span className="inv__item-head__title">{label ? label(it, i) : `#${i + 1}`}</span>
            {canEdit && (
              <>
                <span className="l-spacer" />
                <button type="button" className="btn btn--ghost btn--sm" onClick={() => remove(i)}>Remove</button>
              </>
            )}
          </div>
          <div className="field-grid">{render(it, (patch) => set(i, patch), i)}</div>
        </div>
      ))}
      {canEdit && (
        <div className="inv__add">
          <button type="button" className="btn btn--secondary btn--sm" onClick={() => onChange([...items, blank()])}>{addLabel}</button>
        </div>
      )}
    </div>
  )
}
