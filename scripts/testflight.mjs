#!/usr/bin/env node
/**
 * After the CI upload: waits for Apple to process the build, then gives it the top section of CHANGELOG.md as its
 * TestFlight "What to Test" note. The "Internal" group has every build, so no group is touched. Run on the VPS (no
 * macOS minutes spent waiting):
 *
 *   node scripts/testflight.mjs <build number>
 */
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { asc } from './asc.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const APP_ID = '6829202941'
const LOCALE = 'en-US'

function note () {
  const lines = readFileSync(join(ROOT, 'CHANGELOG.md'), 'utf8').split('\n')
  const start = lines.findIndex((l) => /^## /.test(l))
  if (start === -1) return ''
  const rest = lines.slice(start + 1)
  const end = rest.findIndex((l) => /^## /.test(l))
  return (end === -1 ? rest : rest.slice(0, end)).join('\n').trim().slice(0, 4000)
}

async function waitForBuild (version, minutes = 30) {
  const deadline = Date.now() + minutes * 60e3
  while (Date.now() < deadline) {
    const { data } = await asc(`/v1/builds?filter[app]=${APP_ID}&sort=-uploadedDate&limit=20`)
    const build = data.find((b) => b.attributes.version === String(version))
    const state = build?.attributes.processingState
    if (state === 'VALID') return build
    if (state === 'FAILED' || state === 'INVALID') throw new Error(`build ${version}: ${state}`)
    console.log(`build ${version}: ${state ?? 'not uploaded yet'}`)
    await new Promise((resolve) => setTimeout(resolve, 30000))
  }
  throw new Error(`build ${version} was not processed within ${minutes} minutes`)
}

async function setNote (build, text) {
  const { data } = await asc(`/v1/builds/${build.id}/betaBuildLocalizations`)
  const existing = data.find((l) => l.attributes.locale === LOCALE)
  if (existing) {
    await asc(`/v1/betaBuildLocalizations/${existing.id}`, {
      method: 'PATCH',
      body: JSON.stringify({ data: { type: 'betaBuildLocalizations', id: existing.id, attributes: { whatsNew: text } } })
    })
  } else {
    await asc('/v1/betaBuildLocalizations', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'betaBuildLocalizations',
          attributes: { locale: LOCALE, whatsNew: text },
          relationships: { build: { data: { type: 'builds', id: build.id } } }
        }
      })
    })
  }
}

const version = process.argv[2]
if (!version) {
  console.error('usage: node scripts/testflight.mjs <build number>')
  process.exit(2)
}
try {
  const build = await waitForBuild(version)
  const text = note()
  if (text) await setNote(build, text)
  console.log(`build ${version} is ready in TestFlight${text ? ', with its note' : ''}`)
} catch (err) {
  console.error(err.message)
  process.exit(1)
}
