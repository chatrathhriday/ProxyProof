import { useEffect, useState } from 'react'
import { api } from './api.js'
import { date, duration, useTick } from './util.js'

const DEFAULTS = { presencePct: 80, rssiThreshold: -75, expectedMinutes: 50 }

export default function Home({ onOpen, onCourse }) {
  const [courses, setCourses] = useState(null)
  const [sessions, setSessions] = useState([])
  const [error, setError] = useState(null)
  const [newCourse, setNewCourse] = useState({ code: '', name: '' })
  const [adv, setAdv] = useState(DEFAULTS)
  useTick(30000)

  const load = () =>
    Promise.all([api('GET', '/courses'), api('GET', '/sessions')])
      .then(([c, s]) => {
        setCourses(c)
        setSessions(s)
      })
      .catch((e) => setError(e.message))

  useEffect(() => {
    load()
  }, [])

  async function start(course) {
    try {
      const s = await api('POST', '/sessions', { courseId: course.id, ...adv })
      onOpen(s.id)
    } catch (e) {
      setError(e.message)
    }
  }

  async function create(e) {
    e.preventDefault()
    try {
      const c = await api('POST', '/courses', newCourse)
      setNewCourse({ code: '', name: '' })
      onCourse(c.id) // straight to adding students
    } catch (err) {
      setError(err.message)
    }
  }

  if (!courses) return <p className="muted">{error || 'Loading…'}</p>
  const live = sessions.filter((s) => s.status === 'active')
  const past = sessions.filter((s) => s.status !== 'active')
  const num = (k) => (e) => setAdv({ ...adv, [k]: Number(e.target.value) })

  return (
    <>
      {error && <p className="error">{error}</p>}

      {live.length > 0 && (
        <section>
          <h2>Live now</h2>
          <div className="grid">
            {live.map((s) => (
              <button key={s.id} className="card live-card" onClick={() => onOpen(s.id)}>
                <span className="pill live">
                  <span className="dot" /> Live
                </span>
                <strong>{s.course_code}</strong>
                <span className="muted">{s.course_name}</span>
                <span className="big">{s.present} present</span>
                <span className="muted small">Started {duration(s.started_at)} ago</span>
              </button>
            ))}
          </div>
        </section>
      )}

      <section>
        <h2>Your courses</h2>
        <div className="card list">
          {courses.length === 0 && <p className="muted pad">No courses yet — create one below.</p>}
          {courses.map((c) => (
            <div key={c.id} className="row">
              <div>
                <strong>{c.code}</strong>
                <div className="muted small">
                  {c.name} · {c.students} students
                </div>
              </div>
              <div className="actions">
                <button className="btn ghost" onClick={() => onCourse(c.id)}>
                  Students
                </button>
                <button className="btn" onClick={() => start(c)}>
                  Start session
                </button>
              </div>
            </div>
          ))}
          <form className="row" onSubmit={create}>
            <div className="inline-form">
              <input
                placeholder="Code, e.g. CSE2002"
                value={newCourse.code}
                onChange={(e) => setNewCourse({ ...newCourse, code: e.target.value })}
                required
              />
              <input
                placeholder="Course name"
                value={newCourse.name}
                onChange={(e) => setNewCourse({ ...newCourse, name: e.target.value })}
                required
              />
            </div>
            <button className="btn">New course</button>
          </form>
        </div>
        <details className="advanced">
          <summary>Advanced session settings</summary>
          <div className="inline-form">
            <label>
              Present if in range for ≥ (%)
              <input type="number" min="10" max="100" value={adv.presencePct} onChange={num('presencePct')} />
            </label>
            <label>
              Signal threshold (dBm)
              <input type="number" min="-100" max="-30" value={adv.rssiThreshold} onChange={num('rssiThreshold')} />
            </label>
            <label>
              Class length (min, for the spot-check timing)
              <input type="number" min="1" max="240" value={adv.expectedMinutes} onChange={num('expectedMinutes')} />
            </label>
          </div>
          <p className="muted small">
            Defaults suit a normal classroom. −75 dBm ≈ the same room; raise towards −65 for a stricter radius.
          </p>
        </details>
        <p className="muted small">
          Starting here creates the session; open it in the phone app (“Live now”) to broadcast the beacon.
        </p>
      </section>

      <section>
        <h2>Past sessions</h2>
        <div className="card list">
          {past.length === 0 && <p className="muted pad">Nothing yet.</p>}
          {past.slice(0, 20).map((s) => (
            <button key={s.id} className="row clickable" onClick={() => onOpen(s.id)}>
              <div>
                <strong>{s.course_code}</strong>
                <div className="muted small">
                  {date(s.started_at)} · {duration(s.started_at, s.closed_at)}
                </div>
              </div>
              <span className="actions">
                {s.present} present
                {s.review > 0 && !s.finalized_at && <span className="pill warn">{s.review} to review</span>}
              </span>
            </button>
          ))}
        </div>
      </section>
    </>
  )
}
