# Warmup challenge (10:30–11:30)

Own copy of the boilerplate — edits here don't touch `main/`.

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # add GEMINI_API_KEY
uvicorn main:app --reload --port 8000
```

Write your solution in `backend/agent/core.py::Agent.run`. See the root README for
the full rationale and event timeline.
