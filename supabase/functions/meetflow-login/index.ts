// MeetFlow — login Edge Function
// POST { svc_no, password } → { user, token }
// Verifies staff credentials using the service-role key (bypasses RLS),
// then returns a signed JWT that PostgREST will validate for all subsequent
// API calls from the browser.
//
// Required secret (set once via Supabase dashboard → Edge Functions → Secrets):
//   Name: MF_JWT_SECRET
//   Value: your project's JWT secret (Settings → API → JWT Keys → JWT Secret)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 204 })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  let svc_no: string, password: string
  try {
    ;({ svc_no, password } = await req.json())
    if (!svc_no || !password) throw new Error('missing fields')
  } catch {
    return json({ error: 'svc_no and password are required' }, 400)
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  const { data: users, error } = await sb
    .from('staff')
    .select('*,sections!staff_section_id_fkey(id,name)')
    .ilike('svc_no', svc_no.trim())
    .eq('active', true)
    .limit(1)

  if (error || !users?.length) return json({ error: 'Account not found or inactive' }, 401)
  const user = users[0]

  if (!(await verifyPwd(password, user.password))) return json({ error: 'Incorrect password' }, 401)

  // Silently upgrade SHA-256 / plaintext hash to PBKDF2 on successful login
  if (!user.password.startsWith('pbkdf2:')) {
    const h = await hashPwd(password)
    await sb.from('staff').update({ password: h }).eq('id', user.id)
    user.password = h
  }

  const jwtSecret = Deno.env.get('MF_JWT_SECRET')
  if (!jwtSecret) return json({ error: 'Server misconfiguration: MF_JWT_SECRET not set' }, 500)

  const now = Math.floor(Date.now() / 1000)
  const token = await signJWT(
    {
      iss: 'supabase',
      sub: String(user.id),
      role: 'authenticated',   // PostgREST uses this to select the Postgres role
      staff_id: user.id,
      staff_role: user.role,   // 'admin' | 'staff' — used in RLS policies
      iat: now,
      exp: now + 28800,        // 8 hours
    },
    jwtSecret,
  )

  const { password: _pw, ...safeUser } = user
  return json({ user: safeUser, token })
})

// ── helpers ───────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  })
}

function b64url(data: string | ArrayBuffer | Uint8Array): string {
  const bytes = typeof data === 'string'
    ? new TextEncoder().encode(data)
    : data instanceof Uint8Array ? data : new Uint8Array(data)
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function signJWT(payload: Record<string, unknown>, secret: string): Promise<string> {
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const p = b64url(JSON.stringify(payload))
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${h}.${p}`))
  return `${h}.${p}.${b64url(sig)}`
}

function h2b(hex: string): Uint8Array {
  const b = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) b[i / 2] = parseInt(hex.slice(i, i + 2), 16)
  return b
}

function b2h(buf: Uint8Array | ArrayBuffer): string {
  return Array.from(buf instanceof Uint8Array ? buf : new Uint8Array(buf))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

async function hashPwd(p: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16))
  const km = await crypto.subtle.importKey('raw', new TextEncoder().encode(p), 'PBKDF2', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 },
    km,
    256,
  )
  return `pbkdf2:${b2h(salt)}:${b2h(new Uint8Array(bits))}`
}

async function verifyPwd(plain: string, stored: string): Promise<boolean> {
  if (!stored) return false
  if (stored.startsWith('pbkdf2:')) {
    const [, saltHex, hashHex] = stored.split(':')
    const km = await crypto.subtle.importKey('raw', new TextEncoder().encode(plain), 'PBKDF2', false, ['deriveBits'])
    const bits = await crypto.subtle.deriveBits(
      { name: 'PBKDF2', hash: 'SHA-256', salt: h2b(saltHex), iterations: 100000 },
      km,
      256,
    )
    return b2h(new Uint8Array(bits)) === hashHex
  }
  // Legacy SHA-256 or plaintext fallback
  const sha = b2h(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(plain))))
  return sha === stored || plain === stored
}
