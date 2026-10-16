import { useEffect, useRef, useState } from 'react'
import { api } from './api.js'

// Same OAuth "Web application" client the phone app uses; the server checks this audience
// and routes by Google's verified domain (@vit.ac.in = faculty). Public id, not a secret.
const GOOGLE_CLIENT_ID = '37429262055-7u3mm2sj9takv871no63dpeikab9rj4m.apps.googleusercontent.com'

export default function Login({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const googleBox = useRef(null)

  const finish = (res) => {
    if (res.user.role === 'student') throw new Error('Students use the ProxyProof phone app.')
    onLogin(res)
  }

  // Google Identity Services button (loaded on demand from Google).
  useEffect(() => {
    const render = () => {
      if (!window.google?.accounts?.id || !googleBox.current) return
      window.google.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: async ({ credential }) => {
          setError(null)
          try {
            finish(await api('POST', '/auth/google', { idToken: credential }))
          } catch (err) {
            setError(err.message)
          }
        },
      })
      window.google.accounts.id.renderButton(googleBox.current, {
        theme: 'filled_blue',
        size: 'large',
        shape: 'pill',
        text: 'signin_with',
        width: 300,
      })
    }
    if (window.google?.accounts?.id) return render()
    const s = Object.assign(document.createElement('script'), { src: 'https://accounts.google.com/gsi/client', async: true })
    s.onload = render
    document.head.appendChild(s)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      finish(await api('POST', '/auth/login', { email, password }))
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-wrap">
      <form className="card login" onSubmit={submit}>
        <img src="/favicon.svg" alt="" width="44" height="44" />
        <h1>ProxyProof</h1>
        <p className="muted">Faculty &amp; admin dashboard</p>
        <div className="google-box">
          <div ref={googleBox} />
          <span className="muted small">Faculty: use your @vit.ac.in Google account</span>
        </div>
        <div className="divider">
          <span>or with a password (admin &amp; demo)</span>
        </div>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="btn primary" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  )
}
