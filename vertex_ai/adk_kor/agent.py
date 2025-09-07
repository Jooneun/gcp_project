import os
import logging
import requests
logging.basicConfig(level=logging.INFO)
from typing import Optional
from google.adk.agents import Agent
from google.genai import types
from google.adk.agents import LlmAgent
from google.adk.tools import agent_tool
from google.adk.tools import google_search
from google.adk.code_executors import BuiltInCodeExecutor
from google.adk.tools.mcp_tool.mcp_toolset import MCPToolset, StdioServerParameters
from dotenv import load_dotenv
from google.adk.agents import LlmAgent
from .prompt import instruction
from .tools import find_products_tool

GEMINI_MODEL='gemini-2.5-pro' # Gemini 2.5 Pro

####################################################################################
####################################################################################
####################################################################################

image_analysis_agent = LlmAgent(
    name='ImageAnalysisAgent',
    model='gemini-2.5-flash',
    description='An agent that analyzes refrigerator images and recommends recipes.',
    instruction="""
    You are an expert recipe recommender. Your task is to analyze an image of a refrigerator and provide recipe recommendations in Korean.

    **Follow these steps precisely:**

    1.  **Analyze the image:** Carefully identify every visible ingredient in the refrigerator. Note their approximate quantity and freshness.
    2.  **Recommend 1-2 Korean recipes:** Based *only* on the identified ingredients.
    3.  **Format the output STRICTLY as follows for EACH recipe:** Use Markdown for clarity.

        ### [추천 레시피 이름]

        **✅ 내가 가진 재료 (냉장고 분석 결과):**
        - [재료 1] (예: 파프리카 2개)
        - [재료 2] (예: 양상추 1/2통)
        - ...

        **🛒 구매가 필요한 재료:**
        - [필요한 재료 1] (예: 돼지고기 목살 300g)
        - [필요한 재료 2] (예: 굴소스)
        - *가진 재료로만 만들 수 있다면 "추가로 필요한 재료가 없습니다." 라고 명시*

        **📋 간단 조리법:**
        1. [조리 과정 1]
        2. [조리 과정 2]
        3. ...

    4.  **Provide organization tips:** After the recipes, give one or two simple tips for organizing the food items seen in the fridge.

    **IMPORTANT:** The image is provided directly. Analyze it immediately. Do not ask for file paths.
    """,
    tools=[],  # 도구 없이 직접 이미지 처리
)
####################################################################################
####################################################################################
####################################################################################
def get_current_location():
    """Get current location using IP geolocation (approximate)."""
    try:
        response = requests.get('https://ipapi.co/json/')
        data = response.json()
        return {
            'latitude': data['latitude'],
            'longitude': data['longitude'],
            'city': data['city'],
            'country': data['country']
        }
    except:
        return None

def find_nearby_restaurants(location: Optional[str] = None, cuisine: Optional[str] = None, radius: int = 1000):
    """
    Find nearby restaurants.
    
    Args:
        location (Optional[str]): Address or location (e.g., "Seoul, South Korea")
        cuisine (Optional[str]): Type of cuisine (e.g., "Korean", "Italian", "Japanese")
        radius (int): Search radius in meters (default: 1000)
    
    Returns:
        dict: Restaurant information
    """
    google_maps_api_key = os.environ.get("GOOGLE_MAPS_API_KEY")
    if not google_maps_api_key:
        return {"error": "GOOGLE_MAPS_API_KEY not set"}
    
    # Google Places API 사용
    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    
    # 위치 정보 처리
    if location:
        # 주소를 좌표로 변환
        geocode_url = "https://maps.googleapis.com/maps/api/geocode/json"
        geocode_params = {
            'address': location,
            'key': google_maps_api_key
        }
        geocode_response = requests.get(geocode_url, params=geocode_params)
        geocode_data = geocode_response.json()
        
        if geocode_data['results']:
            lat = geocode_data['results'][0]['geometry']['location']['lat']
            lng = geocode_data['results'][0]['geometry']['location']['lng']
        else:
            return {"error": "Location not found"}
    else:
        # 현재 위치 사용 (IP 기반)
        current_loc = get_current_location()
        if current_loc:
            lat = current_loc['latitude']
            lng = current_loc['longitude']
        else:
            return {"error": "Could not determine location"}
    
    # 음식점 검색
    params = {
        'location': f"{lat},{lng}",
        'radius': radius,
        'type': 'restaurant',
        'key': google_maps_api_key
    }
    
    if cuisine:
        params['keyword'] = cuisine
    
    response = requests.get(url, params=params)
    return response.json()

# 음식점 추천 전용 Agent
restaurant_agent = LlmAgent(
    model='gemini-2.5-flash',
    name='RestaurantRecommendationAgent',
    description='An agent that recommends nearby restaurants based on location and preferences.',
    instruction="""
    You are a restaurant recommendation expert. When users ask for restaurant recommendations:
    
    1. If they provide a location, use that location
    2. If they don't provide a location, use their current location (IP-based)
    3. Ask about their cuisine preferences if not specified
    4. Use the find_nearby_restaurants function to get restaurant data
    5. Provide detailed recommendations including:
       - Restaurant names and ratings
       - Cuisine types
       - Approximate distances
       - Price levels (if available)
       - Opening hours (if available)
    6. Suggest the best options based on ratings and user preferences
    7. Provide directions or maps links if requested
    """,
    tools=[find_nearby_restaurants],
)
####################################################################################
####################################################################################
####################################################################################

wine_image_analysis_agent = LlmAgent(
    name='WineImageAnalysisAgent',
    model='gemini-2.5-flash',
    description='An agent that analyzes wine images and recommends food that goes well with the wine in the image.',
    instruction="""
    You are an expert wine analyst and food recommender.
    
    When you receive an image of a wine:
    1. Analyze the wine and explain this in 3 sentences.
    2. Recommend food that goes well with the wine.
    
    IMPORTANT: The image is provided directly to you. Analyze it immediately without asking for file paths.
    """,
    tools=[],  # 도구 없이 직접 이미지 처리
)

load_dotenv()

shopping_agent = LlmAgent(
  model='gemini-2.5-flash',
  name='shopping_assistant_agent',
  description='Helps users find products using Naver Shopping API.',
  instruction=instruction,
  tools=[
    find_products_tool
  ],
)
####################################################################################
####################################################################################
####################################################################################


root_agent = Agent(
    name='RootAgent',
    description='Root Agent with image analysis capabilities',
    model=GEMINI_MODEL,
    tools=[
        agent_tool.AgentTool(agent=image_analysis_agent),  # 이미지 분석 추가
        agent_tool.AgentTool(agent=restaurant_agent), # Google Maps 에이전트 호출
        agent_tool.AgentTool(agent=wine_image_analysis_agent), # Google Maps 에이전트 호출
        agent_tool.AgentTool(agent=shopping_agent), # 네이버 쇼핑 에이전트 호출
    ],
)