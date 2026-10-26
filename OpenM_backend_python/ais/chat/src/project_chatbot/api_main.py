"""Entry point used by the backend chat endpoint to run the ProjectChatbot
crew out-of-process (this project has its own dependency set, separate
from the main FastAPI app's virtualenv).

Usage: python api_main.py <input_json_path> <output_json_path>

Reads the crew kickoff inputs from input_json_path, runs the crew, and
writes {"response": "<final text>"} (or {"error": "..."}) to
output_json_path. Using files instead of stdout avoids crewai's verbose
console logging polluting the result.
"""
import json
import sys

from project_chatbot.crew import ProjectChatbotCrew


def run_from_inputs(inputs: dict) -> str:
    result = ProjectChatbotCrew().crew().kickoff(inputs=inputs)
    return str(result.raw) if hasattr(result, "raw") else str(result)


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: api_main.py <input_json_path> <output_json_path>", file=sys.stderr)
        sys.exit(1)

    input_path, output_path = sys.argv[1], sys.argv[2]

    with open(input_path, "r", encoding="utf-8") as handle:
        inputs = json.load(handle)

    try:
        response_text = run_from_inputs(inputs)
        output = {"response": response_text}
    except Exception as exc:  # noqa: BLE001 - surface any crew failure to the caller
        output = {"error": str(exc)}

    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(output, handle)


if __name__ == "__main__":
    main()
