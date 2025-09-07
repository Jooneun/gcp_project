# Fridger Agent 🍽️

냉장고 이미지를 분석하여 레시피를 추천하고, 음식점을 찾아주며, 와인과 어울리는 음식을 추천하는 AI 에이전트입니다.

## 주요 기능

### 🔍 냉장고 이미지 분석 및 레시피 추천
- 냉장고 사진을 업로드하면 AI가 재료를 분석
- 보유한 재료를 바탕으로 한국 요리 레시피 추천
- 추가로 필요한 재료 목록 제공
- 냉장고 정리 팁 제공

### 🍷 와인 이미지 분석 및 음식 추천
- 와인 사진을 분석하여 와인 정보 제공
- 해당 와인과 잘 어울리는 음식 추천

### 🏪 음식점 추천
- 현재 위치 또는 지정한 위치 기반 음식점 검색
- 음식 종류별 필터링 가능
- 평점, 거리, 가격대 정보 제공

### 🛒 식재료 쇼핑 도우미
- 네이버 쇼핑 API를 통한 신선한 식재료 검색
- 가격 비교 및 품질 정보 제공
- 유기농, 무농약 등 품질 지표 강조

## 설치 및 설정

### 1. 필요한 패키지 설치

```bash
pip install google-adk
pip install python-dotenv
pip install requests
```

### 2. 환경 변수 설정

`.env` 파일을 생성하고 다음 API 키들을 설정하세요:

```env
# 네이버 쇼핑 API (식재료 검색용)
NAVER_CLIENT_ID=your_naver_client_id
NAVER_CLIENT_SECRET=your_naver_client_secret

# Google Maps API (음식점 검색용)
GOOGLE_MAPS_API_KEY=your_google_maps_api_key

# Google AI API (Gemini 모델용)
GOOGLE_API_KEY=your_google_api_key
```

### 3. API 키 발급 방법

#### 네이버 쇼핑 API
1. [네이버 개발자 센터](https://developers.naver.com/main/)에 접속
2. 애플리케이션 등록 후 쇼핑 API 사용 설정
3. Client ID와 Client Secret 발급

#### Google Maps API
1. [Google Cloud Console](https://console.cloud.google.com/)에 접속
2. Places API 활성화
3. API 키 생성

#### Google AI API
1. [Google AI Studio](https://aistudio.google.com/)에 접속
2. API 키 생성

## 사용 방법

### 기본 사용법

```python
from agent import root_agent

# 에이전트 실행
response = root_agent.run("냉장고 사진을 분석해서 레시피를 추천해주세요")
print(response)
```

### 주요 사용 예시

#### 1. 냉장고 이미지 분석
```python
# 이미지와 함께 요청
response = root_agent.run(
    "이 냉장고 사진을 보고 만들 수 있는 한국 요리를 추천해주세요",
    image_path="refrigerator.jpg"
)
```

#### 2. 음식점 추천
```python
response = root_agent.run("강남역 근처 한식당을 추천해주세요")
```

#### 3. 와인 페어링
```python
response = root_agent.run(
    "이 와인과 어울리는 음식을 추천해주세요",
    image_path="wine.jpg"
)
```

#### 4. 식재료 쇼핑
```python
response = root_agent.run("신선한 송이버섯을 찾아주세요")
```

## 프로젝트 구조

```
fridger-agent-github/
├── README.md           # 프로젝트 설명서
├── agent.py           # 메인 에이전트 코드
├── tools.py           # 도구 함수들 (네이버 쇼핑 API 등)
├── prompt.py          # 프롬프트 템플릿
├── __init__.py        # 패키지 초기화
└── requirements.txt   # 의존성 패키지 목록
```

## 에이전트 구조

### Root Agent
- 전체 시스템을 관리하는 메인 에이전트
- 사용자 요청을 분석하여 적절한 하위 에이전트에게 전달

### Sub Agents
1. **ImageAnalysisAgent**: 냉장고 이미지 분석 및 레시피 추천
2. **RestaurantRecommendationAgent**: 음식점 추천
3. **WineImageAnalysisAgent**: 와인 이미지 분석 및 음식 추천
4. **ShoppingAgent**: 식재료 쇼핑 도우미

## 기술 스택

- **AI 모델**: Google Gemini 2.5 Pro/Flash
- **프레임워크**: Google ADK (Agent Development Kit)
- **API**: 네이버 쇼핑 API, Google Maps API
- **언어**: Python 3.8+

## 주의사항

- API 키는 반드시 `.env` 파일에 안전하게 보관하세요
- 네이버 쇼핑 API와 Google Maps API는 사용량 제한이 있습니다
- 이미지 분석 기능은 Gemini 모델의 비전 기능을 사용합니다

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 기여하기

버그 리포트나 기능 제안은 GitHub Issues를 통해 제출해주세요.

---

**Made with ❤️ using Google ADK**
