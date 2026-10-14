// Same-origin JSON client. The JWT lives in localStorage so a refresh keeps you logged in.
const KEY = 'proxyproof.session'

export function getAuth() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || null
  } catch {
    return null
  }
}

export function setAuth(auth) {
  try {
    if (auth) localStorage.setItem(KEY, JSON.stringify(auth))
    else localStorage.removeItem(KEY)
  } catch {
    /* private mode: stay logged in for this tab only */
  }
}

export async function api(method, path, body) {
  const token = getAuth()?.token
  const res = await fetch(path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  })
  if (res.status === 401 && token) {
    setAuth(null)
    location.reload()
  }
  const data = res.headers.get('content-type')?.includes('json') ? await res.json() : null
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`)
  return data
}

/** Downloads a file from an authenticated endpoint (a plain <a href> can't send the JWT). */
export async function download(path) {
  const res = await fetch(path, { headers: { authorization: `Bearer ${getAuth()?.token}` } })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const name = /filename="?([^";]+)"?/.exec(res.headers.get('content-disposition') || '')?.[1] || 'export.csv'
  const url = URL.createObjectURL(await res.blob())
  const a = Object.assign(document.createElement('a'), { href: url, download: name })
  a.click()
  URL.revokeObjectURL(url)
}
