"""
This is the file you rewrite once the problem statement drops at kickoff.
Everything in backend/main.py and frontend/ stays as-is and just calls Agent.run().
"""

import os
from google import genai

SYSTEM_PROMPT = """\
You are a helpful assistant.
TODO: replace this with the persona/instructions for the actual challenge.
"""


class Agent:
    def __init__(self) -> None:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise RuntimeError("GEMINI_API_KEY not set — copy backend/.env.example to .env")
        self._client = genai.Client(api_key=api_key)
        self._model = "gemini-2.0-flash"

    def run(self, message: str, history: list[dict[str, str]] | None = None) -> str:
        """
        Single-turn entry point used by /api/chat.

        TODO once the problem is known: this is where the real solution lives —
        prompt design, tool/function calls, multi-step chains, retrieval, whatever
        the challenge needs. Keep it a plain (message, history) -> str function so
        the frontend never has to change.
        """
        contents = SYSTEM_PROMPT + "\n\n" + message
        response = self._client.models.generate_content(
            model=self._model,
            contents=contents,
        )
        return response.text
