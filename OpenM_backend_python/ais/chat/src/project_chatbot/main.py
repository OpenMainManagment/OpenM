#!/usr/bin/env python
import sys
from project_chatbot.crew import ProjectChatbotCrew

# This main file is intended to be a way for your to run your
# crew locally, so refrain from adding unnecessary logic into this file.
# Replace with inputs you want to test with, it will automatically
# interpolate any tasks and agents information

def run():
    """
    Run the crew.
    """
    inputs = {
        'user_message': 'sample_value',
        'user_id': 'sample_value',
        'user_role': 'sample_value',
        'api_base_url': 'sample_value',
        'session_token': 'sample_value',
        'file_name': 'sample_value',
        'confirmed_project_id': 'sample_value',
        'confirmed_folder_id': 'sample_value',
        'file_base64': 'sample_value',
        'file_url': 'sample_value'
    }
    ProjectChatbotCrew().crew().kickoff(inputs=inputs)


def train():
    """
    Train the crew for a given number of iterations.
    """
    inputs = {
        'user_message': 'sample_value',
        'user_id': 'sample_value',
        'user_role': 'sample_value',
        'api_base_url': 'sample_value',
        'session_token': 'sample_value',
        'file_name': 'sample_value',
        'confirmed_project_id': 'sample_value',
        'confirmed_folder_id': 'sample_value',
        'file_base64': 'sample_value',
        'file_url': 'sample_value'
    }
    try:
        ProjectChatbotCrew().crew().train(n_iterations=int(sys.argv[1]), filename=sys.argv[2], inputs=inputs)

    except Exception as e:
        raise Exception(f"An error occurred while training the crew: {e}")

def replay():
    """
    Replay the crew execution from a specific task.
    """
    try:
        ProjectChatbotCrew().crew().replay(task_id=sys.argv[1])

    except Exception as e:
        raise Exception(f"An error occurred while replaying the crew: {e}")

def test():
    """
    Test the crew execution and returns the results.
    """
    inputs = {
        'user_message': 'sample_value',
        'user_id': 'sample_value',
        'user_role': 'sample_value',
        'api_base_url': 'sample_value',
        'session_token': 'sample_value',
        'file_name': 'sample_value',
        'confirmed_project_id': 'sample_value',
        'confirmed_folder_id': 'sample_value',
        'file_base64': 'sample_value',
        'file_url': 'sample_value'
    }
    try:
        ProjectChatbotCrew().crew().test(n_iterations=int(sys.argv[1]), openai_model_name=sys.argv[2], inputs=inputs)

    except Exception as e:
        raise Exception(f"An error occurred while testing the crew: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: main.py <command> [<args>]")
        sys.exit(1)

    command = sys.argv[1]
    if command == "run":
        run()
    elif command == "train":
        train()
    elif command == "replay":
        replay()
    elif command == "test":
        test()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
