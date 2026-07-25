# Main challenge (11:30–2:30)

Own copy of the boilerplate — edits here don't touch `warmup/`. Use a different port
if you want both running side by side.

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # add GEMINI_API_KEY
uvicorn main:app --reload --port 8001
```

Write your solution in `backend/agent/core.py::Agent.run`. This is the one judged
live — see root README for the scoring criteria.
