// Fetch the icon sprite once and inline it at the top of <body> so `<use href="#i-…">`
// references resolve (mirrors the kit's js/app.js data-sprite loader). Idempotent.
export async function loadSprite(url = '/sprite.svg'): Promise<void> {
  if (document.getElementById('verity-sprite')) return
  try {
    const res = await fetch(url)
    if (!res.ok) return
    const svg = await res.text()
    const holder = document.createElement('div')
    holder.id = 'verity-sprite'
    holder.setAttribute('aria-hidden', 'true')
    holder.style.position = 'absolute'
    holder.style.width = '0'
    holder.style.height = '0'
    holder.style.overflow = 'hidden'
    holder.innerHTML = svg
    document.body.prepend(holder)
  } catch {
    /* non-fatal: icons degrade to empty <use> references */
  }
}
