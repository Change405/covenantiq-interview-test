# Frontend (optional)

This is a small React app provided as part of the take-home.

It periodically calls the backends’ `GET /healthz` endpoints and shows status.

## Local run
1. Install deps in `frontend/`
   - `npm install`
2. Start dev server
   - `npm run dev`
3. Open the shown URL (default `http://localhost:5173`)

## Configuration
Set these Vite env vars (or create a `.env` file):
- `VITE_SERVICE_A_URL` (default: `http://localhost:8080`)
- `VITE_SERVICE_B_URL` (default: `http://localhost:8080`)

