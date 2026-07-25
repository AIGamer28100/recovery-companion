# Prompt Wars - Chennai

Boilerplate for [PromptWars: In-Person](https://promptwars.in/promptwars.html) — a solo,
one-day AI build sprint with **two separate challenges**, each with its own problem
statement revealed on-site:

- **[`warmup/`](warmup/)** — 10:30–11:30 AM warm-up challenge
- **[`main/`](main/)** — 11:30 AM–2:30 PM main challenge (this is the one that's judged)

Each folder is a standalone copy of the same FastAPI + vanilla-JS boilerplate — see
`warmup/README.md` / `main/README.md` for quick start. They don't share code, so working
in one never breaks the other.

## Event cheat sheet

| Time | Activity |
|---|---|
| 9:00–10:00 | Check-in |
| 10:00–10:30 | Kickoff (problem statements revealed) |
| 10:30–11:30 | Warm-up challenge |
| 11:30–2:30 | **Main challenge** |
| 1:00–2:00 | Lunch & leaderboard freeze |
| 2:30–3:00 | Top 10 announced |
| 3:00–5:30 | Pitching |

## How we win this

Per the rules, judging is on: (1) how well the solution solves the problem, (2) quality/
architecture of the AI prompts, (3) live pitch. Two things this repo is built around:

1. **Must use a real GenAI feature, not just call an LLM as a chatbot.** Each challenge's
   `backend/agent/core.py` is Gemini-wired by default — the win condition is making the
   *use* of the model central to the solution (reasoning, generation, tool use), not
   bolted on.
2. **We're scoring our own output with an AI evaluator before we pitch it**, to catch weak
   spots ahead of the judges. Metrics/rubric TBD — will be added once shared, likely as a
   small `eval/` harness per challenge that scores a run of `Agent.run` against the rubric
   so we can iterate against a number, not a guess.

## Why this shape

The problems are unknown until doors open, so each challenge folder skips anything
problem-specific and just removes setup friction: one process, no build step, one place
to write agent logic.

- **`<challenge>/backend/`** — FastAPI app. Serves the frontend as static files AND
  exposes `/api/chat`, so there's only one process to run.
- **`<challenge>/backend/agent/core.py`** — the one file you actually rewrite once the
  problem drops. Everything else stays untouched.
- **`<challenge>/frontend/`** — plain HTML/JS/CSS, no bundler. Edit and refresh.

## During the sprint

1. Kickoff ends, you know the problems. Write your logic in each challenge's
   `backend/agent/core.py::Agent.run`.
2. Adjust each `frontend/index.html` copy/labels to match the problem framing (helps
   pitching later).
3. Keep it demoable over clever: a working demo beats an ambitious broken one at 2:30.
4. Run the AI evaluator (once wired) against your `main/` solution before the leaderboard
   freeze at 1:00, and use the score to decide what to fix in the last hour.
5. Save pitch talking points as you go — you won't have time to write them at 2:30.
