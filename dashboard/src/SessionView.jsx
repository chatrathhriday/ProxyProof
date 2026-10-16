import { useCallback, useEffect, useMemo, useState } from 'react'
import { io } from 'socket.io-client'
import { api, download, getAuth } from './api.js'
import { ago, date, duration, useTick } from './util.js'

const VERDICT = {
  present: { label: 'Present', cls: 'ok' },
  review: { label: 'Needs review', cls: 'warn' },
  absent: { label: 'Absent', cls: 'bad' },
  excused: { label: 'Excused', cls: '' },
}
const SPOT = {
  passed: { label: 'Passed', cls: 'ok' },
  pending: { label: 'Waiting…', cls: '' },
  failed: { label: 'No answer', cls: 'bad' },
  missed: { label: 'Out of range', cls: 'warn' },
}

export default function SessionView({ id, onBack }) {
  const [s, setS] = useState(null)
  const [error, setError] = useState(null)
  const [filter, setFilter] = useState('')
  const [connected, setConnected] = useState(false)
  const [busy, setBusy] = useState(false)
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

  // "In range %" and the beacon status move with time even without events, so refresh while live.
  const live = s?.status === 'active'
  useEffect(() => {
    if (!live) return
    const t = setInterval(load, 15000)
    return () => clearInterval(t)
  }, [live, load])

  const rows = useMemo(() => {
    const q = filter.trim().toLowerCase()
    const list = (s?.attendance || []).filter((a) => !q || a.name.toLowerCase().includes(q) || a.email.includes(q))
    // After class, unclear cases float to the top: that's all the teacher needs to look at.
    return live ? list : [...list].sort((a, b) => (b.verdict === 'review') - (a.verdict === 'review'))
  }, [s, filter, live])

  if (!s) return <p className="muted">{error || 'Loading…'}</p>

  const act = (fn) => async () => {
    setBusy(true)
    setError(null)
    try {
      await fn()
      await load()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }
  const mark = (student, status) => act(() => api('POST', `/sessions/${id}/attendance`, { studentId: student.student_id, status }))()
  const close = () => confirm('Close this session? Students can no longer be marked.') && act(() => api('POST', `/sessions/${id}/close`))()
  const spotCheck = act(() => api('POST', `/sessions/${id}/spot-check`))
  const approveAll = act(() => api('POST', `/sessions/${id}/approve-all`))
  const { present, review, absent } = s.counts

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
          {live && (
            <button className="btn" onClick={spotCheck} disabled={busy || s.spotChecks.open}>
              {s.spotChecks.open ? 'Spot check running…' : 'Spot check now'}
            </button>
          )}
          <button className="btn" onClick={() => download(`/sessions/${id}/export.csv`).catch((e) => setError(e.message))}>
            Export CSV
          </button>
          {live && (
            <button className="btn danger" onClick={close} disabled={busy}>
              Close session
            </button>
          )}
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      {!live && (
        <div className={`card summary ${review ? 'attention' : ''}`}>
          <div>
            <strong>
              {present} present · {review} need review · {absent} absent
            </strong>
            <div className="muted small">
              {s.finalized_at
                ? `Finalised ${date(s.finalized_at)}.`
                : review
                  ? 'Clear cases were decided automatically. Check the flagged ones below, then approve the rest.'
                  : 'Every case was clear — nothing to review.'}
            </div>
          </div>
          {!s.finalized_at && review > 0 && (
            <button className="btn primary" onClick={approveAll} disabled={busy}>
              Approve all ({review})
            </button>
          )}
        </div>
      )}

      {live &&
        (s.beaconActive ? (
          <p className="muted small">📡 Beacon broadcasting — students' phones can mark themselves.</p>
        ) : (
          <p className="banner">
            ⚠ Not broadcasting yet. A browser can't send Bluetooth, so open this session in the ProxyProof app on the
            teacher's phone (Live now → tap the session). Phones are marked only while a beacon is on.
          </p>
        ))}

      {live && s.spotChecks.open && (
        <p className="banner">Spot check running — each student in range has 20 s to confirm with their fingerprint.</p>
      )}

      <div className="stats">
        <div className="card stat">
          <span className="big ok-text">{present}</span>
          <span className="muted">present{live && ' so far'}</span>
        </div>
        <div className="card stat">
          <span className="big warn-text">{review}</span>
          <span className="muted">need review</span>
        </div>
        <div className="card stat">
          <span className="big">{absent}</span>
          <span className="muted">{live ? 'not here' : 'absent'}</span>
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
                <th>In range</th>
                <th>Spot check</th>
                <th>Last seen</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => {
                const v = VERDICT[a.verdict]
                const spot = SPOT[a.spot]
                const isPresent = a.verdict === 'present'
                return (
                  <tr key={a.student_id} className={a.verdict === 'review' && !live ? 'flagged' : ''}>
                    <td>
                      <strong>{a.name}</strong>
                      <div className="muted small">{a.email}</div>
                    </td>
                    <td>
                      <span className={`pill ${v.cls}`}>{v.label}</span>
                      <div className="muted small">{a.reason}</div>
                    </td>
                    <td>
                      {a.status ? (
                        <div className="meter" title={`${Math.round(a.coverage * 100)}% of the class`}>
                          <span style={{ width: `${Math.round(a.coverage * 100)}%` }} />
                          <em>{Math.round(a.coverage * 100)}%</em>
                        </div>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td>{spot ? <span className={`pill ${spot.cls}`}>{spot.label}</span> : <span className="muted">—</span>}</td>
                    <td title={a.last_seen || ''}>
                      {ago(a.last_seen)}
                      {a.last_rssi != null && <div className="muted small">{a.last_rssi} dBm</div>}
                    </td>
                    <td className="right">
                      {a.verdict === 'review' ? (
                        <span className="actions end">
                          <button className="btn small ghost" onClick={() => mark(a, 'absent')} disabled={busy}>
                            Absent
                          </button>
                          <button className="btn small" onClick={() => mark(a, 'present')} disabled={busy}>
                            Present
                          </button>
                        </span>
                      ) : (
                        <button
                          className={`btn small ${isPresent ? 'ghost' : ''}`}
                          onClick={() => mark(a, isPresent ? 'absent' : 'present')}
                          disabled={busy}
                        >
                          {isPresent ? 'Mark absent' : 'Mark present'}
                        </button>
                      )}
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
      {live && (
        <p className="muted small">
          “Present” needs {s.presence_pct}% of the class in range. One automatic spot check happens at a random time.
        </p>
      )}
    </>
  )
}
