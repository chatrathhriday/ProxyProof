import { useEffect, useState } from 'react'
import { api } from './api.js'
import { date, duration, useTick } from './util.js'

export default function Home({ onOpen }) {
  const [courses, setCourses] = useState(null)
  const [sessions, setSessions] = useState([])
  const [error, setError] = useState(null)
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
      const s = await api('POST', '/sessions', { courseId: course.id })
      onOpen(s.id)
    } catch (e) {
      setError(e.message)
    }
  }

  if (!courses) return <p className="muted">{error || 'Loading…'}</p>
  const live = sessions.filter((s) => s.status === 'active')
  const past = sessions.filter((s) => s.status !== 'active')

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
          {courses.length === 0 && <p className="muted pad">No courses yet.</p>}
          {courses.map((c) => (
            <div key={c.id} className="row">
              <div>
                <strong>{c.code}</strong>
                <div className="muted small">{c.name}</div>
              </div>
              <button className="btn" onClick={() => start(c)}>
                Start session
              </button>
            </div>
          ))}
        </div>
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
                <div className="muted small">{date(s.started_at)} · {duration(s.started_at, s.closed_at)}</div>
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
