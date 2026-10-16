import { useCallback, useEffect, useState } from 'react'
import { api } from './api.js'
import { date } from './util.js'

const TABS = ['Overview', 'Approvals', 'People', 'Audit log', 'Policy']

export default function AdminConsole() {
  const [tab, setTab] = useState('Overview')
  return (
    <>
      <div className="tabs">
        {TABS.map((t) => (
          <button key={t} className={`tab ${tab === t ? 'on' : ''}`} onClick={() => setTab(t)}>
            {t}
          </button>
        ))}
      </div>
      {tab === 'Overview' && <Overview />}
      {tab === 'Approvals' && <Approvals />}
      {tab === 'People' && <People />}
      {tab === 'Audit log' && <Audit />}
      {tab === 'Policy' && <Policy />}
    </>
  )
}

function useLoad(path) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const load = useCallback(() => api('GET', path).then(setData).catch((e) => setError(e.message)), [path])
  useEffect(() => {
    load()
  }, [load])
  return { data, error, load, setError }
}

function Overview() {
  const { data: o, error } = useLoad('/admin/overview')
  if (!o) return <p className="muted">{error || 'Loading…'}</p>
  const t = o.totals
  return (
    <section>
      <div className="stats four">
        {[
          [o.live.length, 'live now'],
          [t.students, 'students'],
          [t.teachers, 'teachers'],
          [t.courses, 'courses'],
        ].map(([v, l]) => (
          <div key={l} className="card stat">
            <span className="big">{v}</span>
            <span className="muted">{l}</span>
          </div>
        ))}
      </div>
      {t.pending_faculty + t.pending_devices > 0 && (
        <p className="banner">
          Waiting for you: {t.pending_faculty} new faculty · {t.pending_devices} phone changes (Approvals tab).
        </p>
      )}
      {o.live.length > 0 && (
        <>
          <h2>Live classes</h2>
          <div className="card list">
            {o.live.map((s) => (
              <div key={s.id} className="row">
                <div>
                  <span className="pill live">
                    <span className="dot" /> Live
                  </span>{' '}
                  <strong>{s.code}</strong> <span className="muted">· {s.teacher}</span>
                </div>
                <span>
                  {s.present}/{s.enrolled} marked
                </span>
              </div>
            ))}
          </div>
        </>
      )}
      <h2>Courses (minimum {o.policy.minAttendance}%)</h2>
      <div className="card">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Course</th>
                <th>Teacher</th>
                <th>Students</th>
                <th>Classes</th>
                <th>Avg</th>
                <th>Below {o.policy.minAttendance}%</th>
              </tr>
            </thead>
            <tbody>
              {o.courses.map((c) => (
                <tr key={c.id}>
                  <td>
                    <strong>{c.code}</strong>
                    <div className="muted small">{c.name}</div>
                  </td>
                  <td>{c.teacher}</td>
                  <td>{c.students}</td>
                  <td>{c.held}</td>
                  <td className={c.avg_pct == null ? '' : c.avg_pct >= o.policy.minAttendance ? 'ok-text' : 'bad-text'}>
                    {c.avg_pct == null ? '—' : `${c.avg_pct}%`}
                  </td>
                  <td>{c.defaulters > 0 ? <span className="pill bad">{c.defaulters}</span> : <span className="muted">0</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

function Approvals() {
  const faculty = useLoad('/admin/users?role=organiser')
  const devices = useLoad('/devices/pending')
  const allow = useLoad('/admin/faculty-allowlist')
  const [emails, setEmails] = useState('')
  const [error, setError] = useState(null)
  const pending = (faculty.data || []).filter((u) => u.status === 'pending')

  const run = (fn) => async () => {
    setError(null)
    try {
      await fn()
    } catch (e) {
      setError(e.message)
    }
    faculty.load()
    devices.load()
    allow.load()
  }

  return (
    <section>
      {error && <p className="error">{error}</p>}
      <h2>New faculty</h2>
      <p className="muted small">@vit.ac.in accounts that signed in with Google and want teacher access.</p>
      <div className="card list">
        {pending.length === 0 && <p className="muted pad">No faculty waiting.</p>}
        {pending.map((u) => (
          <div key={u.id} className="row">
            <div>
              <strong>{u.name}</strong> <span className="muted small">{u.email}</span>
              <div className="small muted">asked {date(u.created_at)}</div>
            </div>
            <div className="actions">
              <button className="btn ghost" onClick={run(() => api('POST', `/admin/users/${u.id}/status`, { status: 'disabled' }))}>
                Decline
              </button>
              <button className="btn primary" onClick={run(() => api('POST', `/admin/users/${u.id}/status`, { status: 'active' }))}>
                Approve
              </button>
            </div>
          </div>
        ))}
      </div>

      <h2>Phone changes</h2>
      <div className="card list">
        {devices.data?.length === 0 && <p className="muted pad">No phones waiting.</p>}
        {devices.data?.map((d) => (
          <div key={d.id} className="row">
            <div>
              <strong>{d.name}</strong> <span className="muted small">{d.email}</span>
              <div className="small">
                New: <strong>{d.model}</strong> · current: {d.current_model || 'none'} · asked {date(d.created_at)}
              </div>
            </div>
            <div className="actions">
              <button className="btn ghost" onClick={run(() => api('POST', `/devices/${d.id}/reject`))}>
                Reject
              </button>
              <button className="btn primary" onClick={run(() => api('POST', `/devices/${d.id}/approve`))}>
                Approve
              </button>
            </div>
          </div>
        ))}
      </div>

      <h2>Pre-approved faculty</h2>
      <p className="muted small">These emails become teachers instantly on their first Google sign-in.</p>
      <form
        className="card pad-form"
        onSubmit={(e) => {
          e.preventDefault()
          run(() => api('POST', '/admin/faculty-allowlist', { emails: emails.split(/[\s,;]+/).filter(Boolean) }))()
          setEmails('')
        }}
      >
        <textarea rows="2" placeholder="firstname.lastname@vit.ac.in, …" value={emails} onChange={(e) => setEmails(e.target.value)} />
        <div className="actions">
          <button className="btn primary">Add</button>
        </div>
      </form>
      <div className="card list">
        {allow.data?.length === 0 && <p className="muted pad">Nobody pre-approved.</p>}
        {allow.data?.map((a) => (
          <div key={a.email} className="row">
            <span>{a.email}</span>
            <button className="btn small ghost" onClick={run(() => api('POST', '/admin/faculty-allowlist/remove', { email: a.email }))}>
              Remove
            </button>
          </div>
        ))}
      </div>
    </section>
  )
}

function People() {
  const [q, setQ] = useState('')
  const [role, setRole] = useState('')
  const [people, setPeople] = useState(null)
  const [courses, setCourses] = useState([])
  const [error, setError] = useState(null)

  const search = useCallback(
    () =>
      api('GET', `/admin/users?q=${encodeURIComponent(q)}${role ? `&role=${role}` : ''}`)
        .then(setPeople)
        .catch((e) => setError(e.message)),
    [q, role],
  )
  useEffect(() => {
    search()
  }, [role]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    api('GET', '/courses').then(setCourses).catch(() => {})
  }, [])

  const act = (fn, confirmText) => async () => {
    if (confirmText && !confirm(confirmText)) return
    try {
      await fn()
      search()
    } catch (e) {
      setError(e.message)
    }
  }
  const teachers = (people || []).filter((u) => u.role === 'organiser' && u.status === 'active')

  return (
    <section>
      {error && <p className="error">{error}</p>}
      <form
        className="actions"
        style={{ marginBottom: 12 }}
        onSubmit={(e) => {
          e.preventDefault()
          search()
        }}
      >
        <input placeholder="Search name or email" value={q} onChange={(e) => setQ(e.target.value)} style={{ flex: 1, minWidth: 180 }} />
        <select value={role} onChange={(e) => setRole(e.target.value)} className="select">
          <option value="">Everyone</option>
          <option value="student">Students</option>
          <option value="organiser">Faculty</option>
          <option value="admin">Admins</option>
        </select>
        <button className="btn">Search</button>
      </form>
      <div className="card list">
        {people?.length === 0 && <p className="muted pad">Nobody found.</p>}
        {people?.map((u) => (
          <div key={u.id} className="row">
            <div>
              <strong>{u.name}</strong> <span className="muted small">{u.email}</span>{' '}
              {u.status !== 'active' && <span className={`pill ${u.status === 'pending' ? 'warn' : 'bad'}`}>{u.status}</span>}
              <div className="small muted">
                {u.role === 'student'
                  ? `Student · ${u.enrolled} courses · ${u.device || 'no phone linked'}`
                  : u.role === 'organiser'
                    ? `Faculty · teaches ${u.teaching}`
                    : 'Admin'}
              </div>
            </div>
            {u.role !== 'admin' && (
              <div className="actions">
                {u.role === 'student' && u.device && (
                  <button
                    className="btn small ghost"
                    onClick={act(() => api('POST', `/admin/users/${u.id}/reset-device`), `Unlink ${u.name}'s phone? Their next phone links itself.`)}
                  >
                    Reset phone
                  </button>
                )}
                {u.status === 'disabled' ? (
                  <button className="btn small" onClick={act(() => api('POST', `/admin/users/${u.id}/status`, { status: 'active' }))}>
                    Re-enable
                  </button>
                ) : (
                  <button
                    className="btn small danger"
                    onClick={act(() => api('POST', `/admin/users/${u.id}/status`, { status: 'disabled' }), `Disable ${u.name}? They are signed out immediately.`)}
                  >
                    Disable
                  </button>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      <h2>Move a course to another teacher</h2>
      <TransferForm courses={courses} teachers={teachers} onDone={search} onError={setError} />
    </section>
  )
}

function TransferForm({ courses, teachers, onDone, onError }) {
  const [courseId, setCourseId] = useState('')
  const [teacherId, setTeacherId] = useState('')
  return (
    <form
      className="card pad-form"
      onSubmit={async (e) => {
        e.preventDefault()
        try {
          await api('POST', `/admin/courses/${courseId}/transfer`, { teacherId: Number(teacherId) })
          onDone()
          alert('Course moved.')
        } catch (err) {
          onError(err.message)
        }
      }}
    >
      <div className="inline-form">
        <select className="select" required value={courseId} onChange={(e) => setCourseId(e.target.value)}>
          <option value="">Course…</option>
          {courses.map((c) => (
            <option key={c.id} value={c.id}>
              {c.code} · {c.name}
            </option>
          ))}
        </select>
        <select className="select" required value={teacherId} onChange={(e) => setTeacherId(e.target.value)}>
          <option value="">New teacher… (search Faculty above to list)</option>
          {teachers.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name} · {t.email}
            </option>
          ))}
        </select>
      </div>
      <div className="actions">
        <button className="btn primary">Move course</button>
      </div>
    </form>
  )
}

const ACTION_LABEL = {
  'attendance.present': 'marked present',
  'attendance.absent': 'marked absent',
  'attendance.excused': 'marked excused',
  'attendance.approve_all': 'approved all flagged',
  'device.approved': 'approved phone',
  'device.rejected': 'rejected phone',
  'device.reset': 'reset phone',
  'user.disabled': 'disabled account',
  'user.activated': 'activated account',
  'user.created': 'created account',
  'faculty.requested': 'requested faculty access',
  'faculty.joined': 'joined as pre-approved faculty',
  'faculty.allowlisted': 'pre-approved faculty',
  'course.transferred': 'moved course',
  'policy.updated': 'changed college policy',
  'announcement.posted': 'posted announcement',
}

function Audit() {
  const { data, error } = useLoad('/admin/audit?limit=200')
  if (!data) return <p className="muted">{error || 'Loading…'}</p>
  return (
    <section>
      <p className="muted small">Every manual attendance change and approval, newest first. Records can't be edited quietly.</p>
      <div className="card">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>Who</th>
                <th>Did</th>
                <th>To</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              {data.map((a) => (
                <tr key={a.id}>
                  <td className="small">{date(a.at)}</td>
                  <td>
                    {a.actor || '—'} <span className="muted small">{a.actor_role}</span>
                  </td>
                  <td>{ACTION_LABEL[a.action] || a.action}</td>
                  <td className="small">{a.target}</td>
                  <td className="small muted">
                    {Object.entries(a.details || {})
                      .filter(([k]) => !['before', 'after'].includes(k))
                      .map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`)
                      .join(' · ')}
                    {a.details?.after &&
                      Object.keys(a.details.after)
                        .filter((k) => a.details.before?.[k] !== a.details.after[k])
                        .map((k) => `${k}: ${a.details.before?.[k]} → ${a.details.after[k]}`)
                        .join(' · ')}
                  </td>
                </tr>
              ))}
              {data.length === 0 && (
                <tr>
                  <td colSpan="5" className="muted pad">
                    Nothing yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}

function Policy() {
  const { data, error, setError } = useLoad('/admin/settings')
  const [edits, setForm] = useState(null)
  const [saved, setSaved] = useState(false)
  const form = edits ?? data // server values until the admin edits something
  if (!form) return <p className="muted">{error || 'Loading…'}</p>
  const field = (k) => (e) => {
    setSaved(false)
    setForm({ ...form, [k]: Number(e.target.value) })
  }
  return (
    <form
      className="card pad-form"
      onSubmit={async (e) => {
        e.preventDefault()
        try {
          setForm(await api('PUT', '/admin/settings', form))
          setSaved(true)
        } catch (err) {
          setError(err.message)
        }
      }}
    >
      {error && <p className="error">{error}</p>}
      <label>
        Minimum attendance (%) — students below this are defaulters; the app's bunk calculator uses it
        <input type="number" min="50" max="100" value={form.minAttendance} onChange={field('minAttendance')} />
      </label>
      <label>
        Default signal threshold (dBm) — −75 ≈ same room; closer to −60 is stricter
        <input type="number" min="-95" max="-50" value={form.rssiThreshold} onChange={field('rssiThreshold')} />
      </label>
      <label>
        Present if in range for at least (%) of the class
        <input type="number" min="50" max="100" value={form.presencePct} onChange={field('presencePct')} />
      </label>
      <div className="actions">
        <button className="btn primary">Save policy</button>
        {saved && <span className="ok-text">Saved — applies to new sessions.</span>}
      </div>
    </form>
  )
}
