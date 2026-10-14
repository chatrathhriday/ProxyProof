import { useCallback, useEffect, useMemo, useState } from 'react'
import { io } from 'socket.io-client'
import { api, download, getAuth } from './api.js'
import { ago, date, duration, time, useTick } from './util.js'

const STATUS = {
  present: { label: 'Present', cls: 'ok' },
  review: { label: 'Needs review', cls: 'warn' },
  absent: { label: 'Absent', cls: 'bad' },
}

export default function SessionView({ id, onBack }) {
  const [s, setS] = useState(null)
  const [error, setError] = useState(null)
  const [filter, setFilter] = useState('')
  const [connected, setConnected] = useState(false)
  useTick(1000)

  const load = useCallback(() => api('GET', `/sessions/${id}`).then(setS).catch((e) => setError(e.message)), [id])

  // Live updates: "roster" = statuses changed -> refetch; "seen" = patch one row in place.
  useEffect(() => {
    load()
    const socket = io({ auth: { token: getAuth()?.token } })
    socket.on('connect', () => {
      setConnected(true)
      socket.emit('watch', id)
      load() // catch up on anything missed while disconnected
    })
    socket.on('disconnect', () => setConnected(false))
    socket.on('roster', load)
    socket.on('seen', ({ studentId, at, rssi }) =>
      setS((cur) =>
        cur && {
          ...cur,
          attendance: cur.attendance.map((a) =>
            a.student_id === studentId ? { ...a, last_seen: at, last_rssi: rssi, sightings: a.sightings + 1 } : a,
          ),
        },
      ),
    )
    return () => socket.disconnect()
  }, [id, load])

  const rows = useMemo(() => {
    const q = filter.trim().toLowerCase()
    return (s?.attendance || []).filter((a) => !q || a.name.toLowerCase().includes(q) || a.email.includes(q))
  }, [s, filter])

  if (!s) return <p className="muted">{error || 'Loading…'}</p>

  const live = s.status === 'active'
  const present = s.attendance.filter((a) => a.status === 'present').length
  const total = s.attendance.length

  async function mark(student, status) {
    try {
      await api('POST', `/sessions/${id}/attendance`, { studentId: student.student_id, status })
      await load()
    } catch (e) {
      setError(e.message)
    }
  }

  async function close() {
    if (!confirm('Close this session? Students can no longer be marked.')) return
    try {
      await api('POST', `/sessions/${id}/close`)
      await load()
    } catch (e) {
      setError(e.message)
    }
  }

  return (
    <>
      <button className="btn ghost back" onClick={onBack}>
        ← All sessions
      </button>

      <div className="session-head">
        <div>
          <div className="title-line">
            <h1>{s.course?.code}</h1>
            {live ? (
              <span className="pill live">
                <span className="dot" /> Live
              </span>
            ) : (
              <span className="pill">Closed</span>
            )}
          </div>
          <p className="muted">
            {s.course?.name} · started {date(s.started_at)} · {duration(s.started_at, s.closed_at)}
            {live && !connected && ' · reconnecting…'}
          </p>
        </div>
        <div className="actions">
          <button className="btn" onClick={() => download(`/sessions/${id}/export.csv`).catch((e) => setError(e.message))}>
            Export CSV
          </button>
          {live && (
            <button className="btn danger" onClick={close}>
              Close session
            </button>
          )}
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="stats">
        <div className="card stat">
          <span className="big ok-text">{present}</span>
          <span className="muted">present</span>
        </div>
        <div className="card stat">
          <span className="big">{total - present}</span>
          <span className="muted">not marked</span>
        </div>
        <div className="card stat">
          <span className="big">{total ? Math.round((present / total) * 100) : 0}%</span>
          <span className="muted">of {total} enrolled</span>
        </div>
      </div>

      <div className="card">
        <div className="table-tools">
          <input placeholder="Search students…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Status</th>
                <th>Marked</th>
                <th>Last seen</th>
                <th>Signal</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => {
                const st = STATUS[a.status] || { label: 'Not marked', cls: '' }
                const isPresent = a.status === 'present'
                return (
                  <tr key={a.student_id}>
                    <td>
                      <strong>{a.name}</strong>
                      <div className="muted small">{a.email}</div>
                    </td>
                    <td>
                      <span className={`pill ${st.cls}`}>{st.label}</span>
                      {a.source === 'manual' && <span className="muted small"> · manual</span>}
                    </td>
                    <td>{time(a.first_seen)}</td>
                    <td title={a.last_seen || ''}>
                      {ago(a.last_seen)}
                      {a.sightings > 0 && <div className="muted small">{a.sightings} sightings</div>}
                    </td>
                    <td>{a.last_rssi != null ? `${a.last_rssi} dBm` : '—'}</td>
                    <td className="right">
                      <button className={`btn small ${isPresent ? 'ghost' : ''}`} onClick={() => mark(a, isPresent ? 'absent' : 'present')}>
                        {isPresent ? 'Mark absent' : 'Mark present'}
                      </button>
                    </td>
                  </tr>
                )
              })}
              {rows.length === 0 && (
                <tr>
                  <td colSpan="6" className="muted pad">
                    No students match.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </>
  )
}
