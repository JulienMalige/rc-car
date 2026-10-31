#!/usr/bin/env node
// App Store Connect API helper. Zero dependencies. (A copy of TV Scores' scripts/asc.mjs: the same team and key.)
//
// Credentials come from the environment, or from ~/.config/tvscores/asc.env
// (ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH). In CI the key itself is passed as
// the multi-line ASC_KEY_P8 variable; asc.env holds a path, never the PEM,
// because the file parser here is one line per value.
//
//   node scripts/asc.mjs whoami            team id, bundle ids, apps
//   node scripts/asc.mjs get <path>        raw GET, e.g. /v1/apps
import { createSign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

function loadEnv () {
  const out = { ...process.env }
  const file = process.env.ASC_ENV || join(homedir(), '.config/tvscores/asc.env')
  try {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/)
      if (!m || out[m[1]]) continue
      out[m[1]] = m[2].trim().replace(/^(['"])(.*)\1$/, '$2')
    }
  } catch { /* environment-only is fine (CI) */ }
  return out
}

let creds = null

function credentials () {
  if (creds) return creds
  const env = loadEnv()
  const missing = ['ASC_ISSUER_ID', 'ASC_KEY_ID'].filter((k) => !env[k])
  if (missing.length) throw new Error(`missing ${missing.join(', ')} (set them or put them in asc.env)`)
  let key = env.ASC_KEY_P8
  if (!key && env.ASC_KEY_PATH) {
    try {
      key = readFileSync(env.ASC_KEY_PATH, 'utf8')
    } catch (err) {
      throw new Error(`cannot read ASC_KEY_PATH ${env.ASC_KEY_PATH}: ${err.code || err.message}`)
    }
  }
  if (!key) throw new Error('missing the private key: set ASC_KEY_P8 or ASC_KEY_PATH')
  if (!key.includes('-----END')) {
    throw new Error('the private key looks truncated; asc.env cannot hold a multi-line PEM, use ASC_KEY_PATH')
  }
  creds = { issuer: env.ASC_ISSUER_ID, keyId: env.ASC_KEY_ID, key }
  return creds
}

const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url')

function token () {
  const { issuer, keyId, key } = credentials()
  const now = Math.floor(Date.now() / 1000)
  const head = b64({ alg: 'ES256', kid: keyId, typ: 'JWT' })
  const body = b64({ iss: issuer, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })
  const signer = createSign('SHA256')
  signer.update(`${head}.${body}`)
  const sig = signer.sign({ key, dsaEncoding: 'ieee-p1363' })
  return `${head}.${body}.${sig.toString('base64url')}`
}

export async function asc (path, init = {}) {
  if (!path) throw new Error('asc(path): a path is required, e.g. /v1/apps')
  const url = path.startsWith('http') ? path : `https://api.appstoreconnect.apple.com${path}`
  const res = await fetch(url, {
    ...init,
    headers: { authorization: `Bearer ${token()}`, 'content-type': 'application/json', ...init.headers }
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`${res.status} ${url}\n${text}`)
  return text ? JSON.parse(text) : null
}

// The CLI runs only when this file is the entry point; importing it does nothing.
if (process.argv[1] && process.argv[1].endsWith('asc.mjs')) {
  const [cmd, arg] = process.argv.slice(2)
  const usage = () => {
    console.error('usage: asc.mjs whoami | get <path>')
    process.exit(2)
  }
  try {
    if (cmd === 'get') {
      if (!arg) usage()
      console.log(JSON.stringify(await asc(arg), null, 2))
    } else if (cmd === 'whoami' || !cmd) {
      const bundles = await asc('/v1/bundleIds?limit=200')
      const seeds = [...new Set(bundles.data.map((b) => b.attributes.seedId).filter(Boolean))]
      console.log('team id  ', seeds.join(', ') || '(none)')
      const apps = await asc('/v1/apps?limit=200')
      for (const a of apps.data) {
        console.log('app      ', a.id, a.attributes.bundleId, '|', a.attributes.name, '| sku', a.attributes.sku)
      }
    } else {
      usage()
    }
  } catch (err) {
    console.error(err.message)
    process.exit(1)
  }
}
