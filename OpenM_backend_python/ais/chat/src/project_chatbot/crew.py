import os
import yaml


from crewai import LLM
from crewai import Agent, Crew, Process, Task
from crewai.project import CrewBase, agent, crew, task
from crewai_tools import (
	URLReadTool
)
from project_chatbot.tools.multipart_file_upload_tool import MultipartFileUploadTool


# This crew's tools (URLReadTool, MultipartFileUploadTool) call our own
# backend API, whose base URL is only known at runtime — crewai-tools'
# path/SSRF validation would otherwise reject it as an untrusted target.
os.environ.setdefault("CREWAI_TOOLS_ALLOW_UNSAFE_PATHS", "true")

# Load AI settings from config file
config_path = os.path.join(os.path.dirname(__file__), "config", "ai_settings.yaml")
with open(config_path, 'r') as config_file:
    ai_config = yaml.safe_load(config_file)

LM_STUDIO_BASE_URL = ai_config['lm_studio']['base_url']
LM_STUDIO_MODEL = ai_config['lm_studio']['model']


def _lm_studio_llm() -> LLM:
    return LLM(
        model=f"lm_studio/{LM_STUDIO_MODEL}",
        base_url=LM_STUDIO_BASE_URL,
        api_key=ai_config['lm_studio']['api_key'],
    )


@CrewBase
class ProjectChatbotCrew:
    """ProjectChatbot crew"""

    
    @agent
    def rest_api_data_fetcher(self) -> Agent:
        
        
        return Agent(
            config=self.agents_config["rest_api_data_fetcher"],
            
            
            tools=[				URLReadTool()],
            
            reasoning=ai_config['llm_defaults']['reasoning'],
            max_reasoning_attempts=ai_config['llm_defaults']['max_reasoning_attempts'],
            inject_date=ai_config['llm_defaults']['inject_date'],
            allow_delegation=ai_config['llm_defaults']['allow_delegation'],
            max_iter=ai_config['llm_defaults']['max_iter'],
            max_rpm=ai_config['llm_defaults']['max_rpm'],
            
            
            max_execution_time=ai_config['llm_defaults']['max_execution_time'],
            llm=_lm_studio_llm(),
            
        )
        
    
    @agent
    def chatbot_responder(self) -> Agent:
        
        
        return Agent(
            config=self.agents_config["chatbot_responder"],
            
            
            tools=[],
            
            reasoning=ai_config['llm_defaults']['reasoning'],
            max_reasoning_attempts=ai_config['llm_defaults']['max_reasoning_attempts'],
            inject_date=ai_config['llm_defaults']['inject_date'],
            allow_delegation=ai_config['llm_defaults']['allow_delegation'],
            max_iter=ai_config['llm_defaults']['max_iter'],
            max_rpm=ai_config['llm_defaults']['max_rpm'],
            
            
            max_execution_time=ai_config['llm_defaults']['max_execution_time'],
            llm=_lm_studio_llm(),
            
        )
        
    
    @agent
    def file_classifier(self) -> Agent:
        
        
        return Agent(
            config=self.agents_config["file_classifier"],
            
            
            tools=[				URLReadTool()],
            
            reasoning=ai_config['llm_defaults']['reasoning'],
            max_reasoning_attempts=ai_config['llm_defaults']['max_reasoning_attempts'],
            inject_date=ai_config['llm_defaults']['inject_date'],
            allow_delegation=ai_config['llm_defaults']['allow_delegation'],
            max_iter=ai_config['llm_defaults']['max_iter'],
            max_rpm=ai_config['llm_defaults']['max_rpm'],
            
            
            max_execution_time=ai_config['llm_defaults']['max_execution_time'],
            llm=_lm_studio_llm(),
            
        )
        
    
    @agent
    def file_uploader(self) -> Agent:
        
        
        return Agent(
            config=self.agents_config["file_uploader"],
            
            
            tools=[				MultipartFileUploadTool()],
            
            reasoning=ai_config['llm_defaults']['reasoning'],
            max_reasoning_attempts=ai_config['llm_defaults']['max_reasoning_attempts'],
            inject_date=ai_config['llm_defaults']['inject_date'],
            allow_delegation=ai_config['llm_defaults']['allow_delegation'],
            max_iter=ai_config['llm_defaults']['max_iter'],
            max_rpm=ai_config['llm_defaults']['max_rpm'],
            
            
            max_execution_time=ai_config['llm_defaults']['max_execution_time'],
            llm=_lm_studio_llm(),
            
        )
        
    

    
    @task
    def classify_file_determine_target(self) -> Task:
        return Task(
            config=self.tasks_config["classify_file_determine_target"],
            markdown=False,
            
            
        )
    
    @task
    def fetch_relevant_api_data(self) -> Task:
        return Task(
            config=self.tasks_config["fetch_relevant_api_data"],
            markdown=False,
            
            
        )
    
    @task
    def upload_file_to_project_folder(self) -> Task:
        return Task(
            config=self.tasks_config["upload_file_to_project_folder"],
            markdown=False,
            
            
        )
    
    @task
    def generate_user_response(self) -> Task:
        return Task(
            config=self.tasks_config["generate_user_response"],
            markdown=False,
            
            
        )
    

    @crew
    def crew(self) -> Crew:
        """Creates the ProjectChatbot crew"""

        return Crew(
            agents=self.agents,  # Automatically created by the @agent decorator
            tasks=self.tasks,  # Automatically created by the @task decorator
            process=Process.sequential,
            verbose=True,

            chat_llm=_lm_studio_llm(),
        )