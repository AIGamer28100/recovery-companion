# Prompt Wars - Chennai

Boilerplate for [PromptWars: In-Person](https://promptwars.in/promptwars.html) — a solo, one-day
AI build sprint. The real problem statement is announced on-site at 10:00 AM; you get
~11:30 AM–2:30 PM to build and a 5-7 min live pitch at the end.

## Event cheat sheet

| Time | Activity |
|---|---|
| 9:00–10:00 | Check-in |
| 10:00–10:30 | Kickoff (problem statement revealed) |
| 10:30–11:30 | Warm-up challenge |
| 11:30–2:30 | **Main build window** |
| 1:00–2:00 | Lunch & leaderboard freeze |
| 2:30–3:00 | Top 10 announced |
| 3:00–5:30 | Pitching |

Judged on: (1) how well the solution solves the problem, (2) quality/architecture of your
AI prompts, (3) live pitch. No teams — solo only.

## Why this shape

The problem is unknown until doors open, so this skips anything problem-specific and just
removes setup friction: one process, no build step, one place to write agent logic.

- **`backend/`** — FastAPI app. Serves the frontend as static files AND exposes `/api/chat`,
  so there's only one process to run.
- **`backend/agent/core.py`** — the one file you actually rewrite once the problem drops.
  Everything else stays untouched.
- **`frontend/`** — plain HTML/JS/CSS, no bundler. Edit and refresh — nothing to rebuild.
- Gemini wired by default (matches Antigravity/Google's stack) but swapping providers is
  a one-function change in `backend/agent/core.py`.

## Quick start

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # add your GEMINI_API_KEY
uvicorn main:app --reload --port 8000
```

Open http://localhost:8000 — chat UI is already wired to `/api/chat`.

## During the sprint

1. Kickoff ends, you know the problem. Write your logic in `backend/agent/core.py::Agent.run`.
2. Adjust `frontend/index.html` copy/labels to match the problem framing (helps pitching later).
3. Keep it demoable over clever: a working demo beats an ambitious broken one at 2:30.
4. Save pitch talking points as you go — you won't have time to write them at 2:30.
