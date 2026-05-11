# Full-Stack Web App — Project Context
_Example: copy this into your project's CLAUDE.md, or paste the relevant sections_
_into your global ~/.claude/CLAUDE.md to apply it across all your web projects._

---

## CORS and networking (non-negotiable)

These rules apply automatically to every prompt that builds, scaffolds, or extends
any frontend↔backend interaction. Do not wait to be asked. Do not leave any item
as a TODO.

### API calls
- Frontend **must** use relative paths (`/api/…`) — never hardcoded `localhost` URLs.

### Dev server proxy — include in the first response
Configure the proxy for whichever frontend framework is in use:

**Vite** (`vite.config.ts`):
```ts
export default defineConfig({
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true },
    },
  },
})
```

**Next.js** (`next.config.js`):
```js
module.exports = {
  async rewrites() {
    return [{ source: '/api/:path*', destination: 'http://localhost:8000/api/:path*' }]
  },
}
```

**Create React App** (`package.json`):
```json
{ "proxy": "http://localhost:8000" }
```

### Backend CORS — include working code in the first response

**Express / Node**:
```js
import cors from 'cors'
const origins = process.env.ALLOWED_ORIGINS?.split(',') ?? ['http://localhost:5173']
app.use(cors({ origin: origins, credentials: true }))
```

**FastAPI**:
```python
from fastapi.middleware.cors import CORSMiddleware
origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:5173").split(",")
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
```

**Django** (`settings.py` + `django-cors-headers`):
```python
CORS_ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:5173").split(",")
CORS_ALLOW_CREDENTIALS = True
```

**Go** (`net/http` + `rs/cors`):
```go
origins := strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",")
c := cors.New(cors.Options{AllowedOrigins: origins, AllowCredentials: true})
handler = c.Handler(router)
```

### Rules
- **Development**: always allow `http://localhost:<frontend-port>` and
  `http://127.0.0.1:<frontend-port>`. Use the framework's actual default port
  (Vite: 5173, CRA/Next.js: 3000, Angular: 4200).
- **Production**: read origins exclusively from `ALLOWED_ORIGINS` env var. No hardcoding.
- **Credentials / cookies**: never use `Access-Control-Allow-Origin: *`.
  Set `Access-Control-Allow-Credentials: true` and an explicit origin.
- **Environment variables**: define `ALLOWED_ORIGINS` (and any API base-URL vars) in
  `.env.example` with placeholder values. Commit `.env.example`, never `.env`.

### CORS testing checklist — include in every first response
```
Chrome DevTools smoke-test:

  Console tab — paste:
    fetch('/api/health').then(r => r.json()).then(console.log)
  Expected: JSON response with no CORS error in console.

  Network tab — select the /api request → Headers:
    Request  → Origin: http://localhost:<port>
    Response → Access-Control-Allow-Origin: http://localhost:<port>
               Access-Control-Allow-Credentials: true   (if using cookies)
```

---

## Project identity
<!-- Fill in before use -->
App name and one-line description.

## Architecture
- **Frontend**: [React / Vue / Next.js / SvelteKit / …] on port [3000 / 5173 / …]
- **Backend**: [Express / FastAPI / Django / Go / …] on port [8000 / …]
- **Database**: [Postgres / MySQL / MongoDB / …]
- **Auth**: [JWT / session cookies / OAuth / …]
- **Deployment**: [Vercel + Railway / AWS / Fly.io / …]

## Key file paths
```
frontend/          # or src/ — client-side code
backend/           # or server/ — API code
frontend/.env      # VITE_API_URL etc. (never commit)
backend/.env       # DATABASE_URL, ALLOWED_ORIGINS etc. (never commit)
.env.example       # Committed — documents required vars with placeholder values
```

## Environment variables (document all of them here)
| Variable | Where | Purpose |
|----------|-------|---------|
| `ALLOWED_ORIGINS` | backend | Comma-separated allowed CORS origins |
| `DATABASE_URL` | backend | DB connection string |
| `JWT_SECRET` | backend | Token signing key |
| `VITE_API_URL` | frontend | Only set this if you need an absolute URL in a specific deploy |

## Critical rules
- Relative API paths everywhere — no hardcoded ports in frontend source.
- All secrets in `.env` files — `.env.example` documents the shape, `.env` is gitignored.
- Run `npm run lint` and `npm test` before every commit.
- Database migrations must be reviewed before merging to main.

## Token hygiene for full-stack work
- When sharing error output: paste only the relevant stack trace lines, not full logs.
- When referencing API responses: describe the shape, don't paste raw JSON blobs.
- For large schema files: reference by path (`@backend/schema.prisma`), don't paste.

## Useful commands
```bash
# Dev (run in separate terminals or use a process manager)
cd frontend && npm run dev      # starts frontend dev server with proxy
cd backend && npm run dev       # starts backend API

# Or with concurrently:
npm run dev                     # starts both

# Type-check
cd frontend && npm run typecheck
cd backend && npm run typecheck

# Test
npm test                        # unit + integration
npm run test:e2e                # end-to-end (requires both servers running)
```
