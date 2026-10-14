import { useCallback, useEffect, useState } from 'react'
import { api } from './api.js'

/** Students of one course: add by email (one per line or comma-separated), remove, see attendance %. */
export default function CourseView({ id, onBack }) {
  const [data, setData] = useState(null)
  const [emails, setEmails] = useState('')
  const [msg, setMsg] = useState(null)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(() => api('GET', `/courses/${id}/students`).then(setData).catch((e) => setError(e.message)), [id])
  useEffect(() => {
    load()
  }, [load])

  async function add(e) {
    e.preventDefault()
    const list = emails.split(/[\s,;]+/).filter(Boolean)
    if (!list.length) return
    setBusy(true)
    setError(null)
    try {
      const r = await api('POST', `/courses/${id}/enroll`, { emails: list })
      setMsg(
        `Added ${r.enrolled.length}.` +
          (r.notFound.length ? ` Not registered yet (ask them to sign up in the app first): ${r.notFound.join(', ')}` : ''),
      )
      setEmails(r.notFound.join('\n'))
      await load()
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  async function remove(s) {
    if (!confirm(`Remove ${s.name} from this course?`)) return
    try {
      await api('POST', `/courses/${id}/unenroll`, { studentId: s.id })
      await load()
    } catch (err) {
      setError(err.message)
    }
  }

  if (!data) return <p className="muted">{error || 'Loading…'}</p>
  const { course, held, students } = data

  return (
    <>
      <button className="btn ghost back" onClick={onBack}>
        ← Back
      </button>
      <h1>{course.code}</h1>
      <p className="muted">
        {course.name} · {students.length} students · {held} classes held
      </p>
      {error && <p className="error">{error}</p>}

      <form className="card pad-form" onSubmit={add}>
        <label>
          Add students by email
          <textarea
            rows="3"
            placeholder={'student1@college.edu\nstudent2@college.edu'}
            value={emails}
            onChange={(e) => setEmails(e.target.value)}
          />
        </label>
        <div className="actions">
          <button className="btn primary" disabled={busy}>
            Add
          </button>
          {msg && <span className="muted small">{msg}</span>}
        </div>
      </form>

      <div className="card list">
        {students.length === 0 && <p className="muted pad">No students yet.</p>}
        {students.map((s) => {
          const pct = held ? Math.round((s.present / held) * 100) : null
          return (
            <div key={s.id} className="row">
              <div>
                <strong>{s.name}</strong> <span className="muted small">{s.email}</span>
                <div className="small">
                  {pct == null ? 'No classes yet' : `${s.present}/${held} classes · `}
                  {pct != null && <span className={pct >= 75 ? 'ok-text' : 'bad-text'}>{pct}%</span>}
                  {!s.has_device && <span className="muted"> · phone not linked yet</span>}
                </div>
              </div>
              <button className="btn small ghost" onClick={() => remove(s)}>
                Remove
              </button>
            </div>
          )
        })}
      </div>
    </>
  )
}
