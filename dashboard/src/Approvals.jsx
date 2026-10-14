import { useEffect, useState } from 'react'
import { api } from './api.js'
import { date } from './util.js'

export default function Approvals() {
  const [list, setList] = useState(null)
  const [error, setError] = useState(null)

  const load = () => api('GET', '/devices/pending').then(setList).catch((e) => setError(e.message))
  useEffect(() => {
    load()
  }, [])

  async function decide(d, approve) {
    try {
      await api('POST', `/devices/${d.id}/${approve ? 'approve' : 'reject'}`)
    } catch (e) {
      setError(e.message)
    }
    load()
  }

  return (
    <section>
      <h1>Device approvals</h1>
      <p className="muted">
        A student asking to use a new phone, or whose fingerprints changed. Approving retires their old phone.
      </p>
      {error && <p className="error">{error}</p>}
      <div className="card list">
        {list?.length === 0 && <p className="muted pad">No pending requests.</p>}
        {list?.map((d) => (
          <div key={d.id} className="row">
            <div>
              <strong>{d.name}</strong> <span className="muted small">{d.email}</span>
              <div className="small">
                New: <strong>{d.model}</strong> · current: {d.current_model || 'none'} · asked {date(d.created_at)}
              </div>
            </div>
            <div className="actions">
              <button className="btn ghost" onClick={() => decide(d, false)}>
                Reject
              </button>
              <button className="btn primary" onClick={() => decide(d, true)}>
                Approve
              </button>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
