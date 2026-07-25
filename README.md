# Prompt Wars - Chennai

Local workspace for [PromptWars: In-Person](https://promptwars.in/promptwars.html) — a
solo, one-day AI build sprint with **two separate challenges**, each with its own problem
statement revealed on-site, and each submitted as its **own standalone public GitHub repo**:

- **[`warmup/`](warmup/)** — 10:30–11:30 AM, one submission attempt
- **[`main/`](main/)** — 11:30 AM–2:30 PM (judged), up to 3 submission attempts —
  only the latest push before the deadline counts

This top-level folder is *not* itself part of either submission — `warmup/` and `main/`
are gitignored here and are independent git repos of their own (see below). This folder
is just local scratch space for notes/planning across both.

## Submission rules (apply to both, separately)

- Public GitHub repo, single branch, **under 10 MB**
- Private/restricted links are not evaluated
- Warmup: 1 submission attempt. Main: up to 3 — latest wins
- README must cover: chosen vertical, approach/logic, how it works, assumptions

## How to actually submit each one

```bash
cd warmup   # or main
gh repo create <your-repo-name> --public --source=. --remote=origin
git push -u origin HEAD
```

(Not run automatically — repo naming and the "go" to make it public is yours to call,
and it's cleanest to do this from inside the AI platform per the official workflow:
create repo → clone in-tool → build → commit/push as you go.)

## Event cheat sheet

| Time | Activity |
|---|---|
| 9:00–10:00 | Check-in |
| 10:00–10:30 | Kickoff (problem statements revealed) |
| 10:30–11:30 | Warm-up challenge (submit by 11:30) |
| 11:30–2:30 | **Main challenge** (submit by 2:30, latest push counts) |
| 1:00–2:00 | Lunch & leaderboard freeze |
| 2:30–3:00 | Top 10 announced |
| 3:00–5:30 | Pitching |

## How we win this

Evaluation focus areas, per the official rules: **Code Quality, Security, Efficiency,
Testing, Accessibility** — each tagged High/Medium/Low impact (High-impact misses hurt
the most; Low-impact is the polish needed only for a perfect score). Judging on stage
adds: (1) how well the solution solves the problem, (2) quality/architecture of the AI
prompts, (3) live pitch.

What this boilerplate is built around:

1. **A real GenAI feature, not just an LLM chat wrapper.** Each challenge's
   `backend/agent/core.py` is Gemini-wired by default — the model's use has to be
   central to the solution (reasoning, generation, tool use), not bolted on.
2. **Self-scoring before the pitch.** Once the impact-tier rubric is confirmed, add an
   `eval/` harness per challenge that scores a run of `Agent.run` against it, so changes
   in the last hour are guided by a number, not a guess.
3. **The 5 focus areas are pre-covered, not left to chance**: `backend/tests/` for
   Testing, Pydantic request validation + `.gitignore`'d secrets for Security, labelled
   inputs + `aria-live` region for Accessibility. Code Quality and Efficiency are on you
   as you write the real logic — keep `Agent.run` readable and avoid redundant model calls.

## Why this shape

The problems are unknown until doors open, so each challenge repo skips anything
problem-specific and just removes setup friction: one process, no build step, one place
to write agent logic.

- **`<challenge>/backend/`** — FastAPI app. Serves the frontend as static files AND
  exposes `/api/chat`, so there's only one process to run.
- **`<challenge>/backend/agent/core.py`** — the one file you actually rewrite once the
  problem drops. Everything else stays untouched.
- **`<challenge>/frontend/`** — plain HTML/JS/CSS, no bundler. Edit and refresh.

## During the sprint

1. Kickoff ends, you know the problems. Write your logic in each challenge's
   `backend/agent/core.py::Agent.run`, and fill in the vertical/approach/assumptions in
   its README.
2. Adjust each `frontend/index.html` copy/labels to match the problem framing (helps
   pitching later).
3. Keep it demoable over clever: a working demo beats an ambitious broken one.
4. For `main/`, commit and push regularly — only the latest push before 2:30 counts, so
   never leave uncommitted work sitting.
5. Save pitch talking points as you go — you won't have time to write them at 2:30.
