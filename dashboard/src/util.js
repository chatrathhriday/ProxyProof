import { useEffect, useState } from 'react'

/** Re-renders every `ms` so "12 s ago" labels keep moving. */
export function useTick(ms = 1000) {
  const [, set] = useState(0)
  useEffect(() => {
    const t = setInterval(() => set((n) => n + 1), ms)
    return () => clearInterval(t)
  }, [ms])
}

export function ago(iso) {
  if (!iso) return '—'
  const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  return `${Math.floor(s / 3600)}h ago`
}

export const time = (iso) => (iso ? new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '—')

export const date = (iso) =>
  new Date(iso).toLocaleDateString([], { day: 'numeric', month: 'short' }) + ', ' + time(iso)

export function duration(fromIso, toIso) {
  const m = Math.max(0, Math.round(((toIso ? new Date(toIso) : Date.now()) - new Date(fromIso)) / 60000))
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`
}
