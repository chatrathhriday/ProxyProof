import { useState } from 'react'
import { getAuth, setAuth } from './api.js'
import Login from './Login.jsx'
import Home from './Home.jsx'
import SessionView from './SessionView.jsx'
import Approvals from './Approvals.jsx'
import CourseView from './CourseView.jsx'

// No router on purpose: three screens, picked from state. Keeps every URL path free
// for the API, which the same server answers.
export default function App() {
  const [auth, setAuthState] = useState(getAuth)
  const [sessionId, setSessionId] = useState(null)
  const [courseId, setCourseId] = useState(null)

  if (!auth) {
    return (
      <Login
        onLogin={(a) => {
          setAuth(a)
          setAuthState(a)
        }}
      />
    )
  }

  const logout = () => {
    setAuth(null)
    setAuthState(null)
    setSessionId(null)
  }

  return (
    <div className="shell">
      <header className="topbar">
        <button
          className="brand"
          onClick={() => {
            setSessionId(null)
            setCourseId(null)
          }}
        >
          <img src="/favicon.svg" alt="" width="24" height="24" />
          ProxyProof
        </button>
        <div className="topbar-right">
          <span className="muted">
            {auth.user.name} · {auth.user.role}
          </span>
          <button className="btn ghost" onClick={logout}>
            Log out
          </button>
        </div>
      </header>
      <main className="content">
        {auth.user.role === 'admin' ? (
          <Approvals />
        ) : sessionId ? (
          <SessionView id={sessionId} onBack={() => setSessionId(null)} />
        ) : courseId ? (
          <CourseView id={courseId} onBack={() => setCourseId(null)} />
        ) : (
          <Home onOpen={setSessionId} onCourse={setCourseId} />
        )}
      </main>
    </div>
  )
}
