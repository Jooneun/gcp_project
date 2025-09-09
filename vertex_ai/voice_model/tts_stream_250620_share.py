import os
from google.cloud import texttospeech
import asyncio
import re
import json
import uuid

def load_json_data(filepath):
    """지정된 경로의 JSON 파일을 로드합니다."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Warning: {filepath} not found. Proceeding without it.")
        return None
    except json.JSONDecodeError:
        print(f"Warning: Could not decode JSON from {filepath}.")
        return None

async def tts(text, output, lang):
    """Google Cloud TTS API를 호출하여 텍스트를 음성으로 변환하고 파일로 저장합니다."""
    try:
        client = texttospeech.TextToSpeechAsyncClient()
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(language_code=lang, name=f"{lang}-Standard-A")
        audio_encoding = texttospeech.AudioEncoding.LINEAR16 if output.lower().endswith(".wav") else texttospeech.AudioEncoding.LINEAR16
        audio_config = texttospeech.AudioConfig(audio_encoding=audio_encoding, sample_rate_hertz=16000)
        
        print("\n--- Sending to Google TTS API ---")
        # print(f"Text: {text}") # 너무 길면 주석 처리
        
        response = await client.synthesize_speech(input=synthesis_input, voice=voice, audio_config=audio_config)
        
        with open(output, "wb") as out:
            out.write(response.audio_content)
        print(f"Success: Audio content written to file '{output}'")

    except Exception as e:
        print(f"An error occurred during TTS synthesis: {e}")

async def process_and_synthesize(text_to_synthesize, output_filename, lexicon_rules, protection_rules):
    """
    텍스트를 전처리하고 TTS를 실행하는 전체 파이프라인입니다. (최종 완성 버전)
    """
    final_text = text_to_synthesize
    protected_parts = {}

    # --- 1. 일반 발음 규칙 적용 (Lexicon) ---
    if lexicon_rules:
        # ★★★ 핵심 수정 1: 규칙을 키의 길이에 따라 내림차순으로 정렬 ★★★
        # 'TV CHOSUN'이 'TV' 또는 'CHOSUN'보다 먼저 처리되도록 보장합니다.
        sorted_lexicon = sorted(lexicon_rules.items(), key=lambda item: len(item[0]), reverse=True)
        
        for word, pronunciation in sorted_lexicon:
            # ★★★ 핵심 수정 2: 'TV CHOSUN의' 같이 조사가 붙어도 처리되도록 패턴 수정 ★★★
            pattern = r'\b' + re.escape(word) + r'(?![A-Za-z0-9_])'
            final_text = re.sub(pattern, pronunciation, final_text, flags=re.IGNORECASE)

    # --- 2. 특수 패턴 보호 (Protection) ---
    all_replacements = []
    if protection_rules:
        for rule in protection_rules:
            if 'pattern' not in rule or not rule['pattern']:
                continue
            
            try:
                pattern = re.compile(rule['pattern'], re.IGNORECASE)
                for match in pattern.finditer(final_text):
                    all_replacements.append((match.start(), match.end(), match.group(0)))
            except re.error as e:
                print(f"Warning: Invalid regex pattern '{rule['pattern']}' skipped. Error: {e}")

    # (이하 로직은 이전과 동일하게 안정적으로 동작합니다)
    sorted_replacements = sorted(all_replacements, key=lambda x: (x[0], -len(x[2])))
    final_replacements = []
    last_match_end = -1
    for start, end, text in sorted_replacements:
        if start >= last_match_end:
            final_replacements.append((start, end, text))
            last_match_end = end
    
    for start, end, original_text in sorted(final_replacements, key=lambda x: x[0], reverse=True):
        placeholder = f"PLACEHOLDER{uuid.uuid4().hex}"
        protected_parts[placeholder] = original_text
        final_text = final_text[:start] + placeholder + final_text[end:]
        
    # --- 3. 마크다운 및 일반 텍스트 정리 (Cleanup) ---
    # final_text = re.sub(r'\[([^\]]+?)\]\(([^)]*?)\)', r'\2', final_text)
    final_text = re.sub(r'\[([^\]]+?)\]\(([^)]*?)\)', r'\1 \2', final_text)
    final_text = re.sub(r'^\s*#+\s+', '', final_text, flags=re.MULTILINE)
    final_text = re.sub(r'\s*>\s*', ' ', final_text)
    final_text = re.sub(r'^\s*[\*\-\+]\s+', '', final_text, flags=re.MULTILINE)
    final_text = re.sub(r'^\s*\d+\.\s+', '', final_text, flags=re.MULTILINE)
    final_text = re.sub(r'(\*{1,3})(.+?)\1', r'\2', final_text)
    final_text = re.sub(r'[~～]{2}(.+?)[~～]{2}', r'\1', final_text)
    final_text = re.sub(r'\b_([^_]+)_\b', r'\1', final_text)
    final_text = re.sub(r'[\'"]', '', final_text)
    final_text = re.sub(r'\$([^$]+?)\$', r'\1', final_text)
    final_text = re.sub(r'[{}]', ' ', final_text)
    final_text = re.sub(r'\s*\^+\s*', '의 ', final_text)
    final_text = re.sub(r'([A-Za-z])\/([A-Za-z])', r'\1 \2', final_text)

    # --- 4. 보호된 패턴 복원 (Restoration) ---
    if protected_parts:
        for placeholder, original_text in protected_parts.items():
            cleaned_original = re.sub(r'^`|`$', '', original_text)
            final_text = final_text.replace(placeholder, cleaned_original)

    # 최종 공백 정리
    final_text = re.sub(r'\s+', ' ', final_text).strip()
    
    print("--- Final Text for TTS ---")
    print(final_text)
    
    # TTS 실행
    await tts(final_text, output_filename, "ko-KR")

async def main():
    # JSON 파일 로드
    lexicon_rules = load_json_data("lexicon_general.json") or {}
    protection_rules = load_json_data("protection_patterns.json") or []

    # 테스트할 텍스트 딕셔너리
    test_cases = {
        "1_solo": """
'나는 SOLO'는 결혼을 간절히 바라는 솔로 남녀들이 사랑을 찾아가는 과정을 담은 리얼 연애프로그램입니다.
매주 수요일 밤 10시 30분에 ENA와 SBS Plus에서 시청할 수 있으며, SBS 라이브 사이트에서도 실시간 시청이 가능합니다.
출연 신청은 lovematch911@naver.com으로 메일을 보내 지원할 수 있으며, 진정성 있는 결혼관을 가진 솔로를 선호한다고 하니 참고하세요!
시청 가능한 관련 콘텐츠를 찾아 추천해 드릴게요. 나는 SOLO, 나는 SOLO, 그 후 사랑은 계속된다, 빛 나는 SOLO.
나는 solo입니다. 나는 SOLO입니다. Solo, solo, SOLO.
연락은 SOLO@gmail.com 으로 주세요.
공식 홈페이지는 https://www.sbs.co.kr 입니다.
새로운 ID는 MY_COOL_SOLO_ID 입니다.
""",
        "2_codes": """
회원님의 새로운 유저 코드는 USER_LOGIN_TOKEN 입니다.
이번에 개발한 AI 모델의 정식 명칭은 SPECIAL_AI_MODEL_V2 입니다.
저희는 클라우드 서비스로 AWS와 GCP를 모두 사용하고 있습니다.
자세한 내용은 공식 사이트  를 확인하시고, 기술 지원은 support@my-service.com 으로 연락주세요.
# 긴급 공지
> COVID-19 확산 방지를 위해, 재택 근무를 권장합니다. ~~이전 지침은 무시하세요.~~
새로운 ML 파이프라인의 이름은 FAST_ML_PIPELINE으로 정해졌습니다.
2025년도 신규 서버의 관리자 ID는 SRV_ADMIN_2025 입니다.
자세한 내용은 를 참고하세요. 접속 시 필요한 API 키는 API_KEY_FOR_USER 입니다.
A/B 테스트 결과, 플랜 B가 플랜 A보다 더 효과적이었습니다.
""",
        "3_markdown": """
*이것은 이탤릭*, **이것은 볼드**, ***이것은 둘 다 입니다***.
밑줄이 포함된 a_word_with_underscores 단어는 유지되어야 합니다.
`이것은 코드 블록 입니다.`
새로운 아이디는 ANOTHER_ID_CODE 입니다.
나는 _SOLO_ 프로젝트를 좋아합니다.
# 헤더 테스트
> 인용문 테스트
- 리스트 테스트
""",
        "4_original": """
# 중요 공지
> 이것은 **굵은 글씨**이고, *이것은 기울임 글씨*입니다.
- 목록 1
- ~~이것은 취소선입니다.~~
회원님의 아이디는 `USER_LOGIN_V2`이며, 이것은 _절대로_ 외부에 노출되면 안 됩니다.
파일 이름은 `MY_FILE_NAME.txt` 입니다.
자세한 내용은 공식 사이트 [여기](https://my-service.com/user_guide)를 확인하고,
기술 지원은 `support_team@my-service.com` 으로 연락주세요.
""",
        "5_complex": """
**긴급**: 새로운 API 키 `API_KEY_FOR_**SPECIAL**_USER`를 확인하세요. 자세한 내용은 > 공식문서를 참고하세요.
비용은 $50 이고, 2^10 = 1024 입니다. {중요: 이것은 변수입니다}
""",
        "6_tvn": """
tvN의 인기 예능 프로그램 '유 퀴즈 온 더 블럭'은 MC 유재석과 조세호가 시민들의 일상으로 직접 찾아가 소박한 담소를 나누고 퀴즈를 푸는 프로그램입니다. 매주 수요일 저녁 8시 45분에 tvN에서 방송되며, 티빙(TVING)을 통해 실시간 및 다시보기 시청이 가능합니다. 자기님들의 참여 신청이나 특별한 사연은 공식 홈페이지의 '자기님을 찾습니다' 게시판이나 이메일 uquiz_apply@cj.net으로 보내주세요.
""",
        "7_chosun": """
TV CHOSUN의 초대형 오디션 프로그램 '미스터트롯3'는 대한민국 트로트계의 새로운 스타를 발굴하는 서바이벌입니다. 방송은 매주 목요일 밤 10시에 시작되며, 생방송 중에는 #4560으로 응원하는 참가자에게 유료 문자 투표를 할 수 있습니다. 방청 신청 및 온라인 인기투표는 vote.chosun.com/mr-trot3에서 가능하며, 자세한 공지는 공식 인스타그램 계정 MR_TROT_OFFICIAL을 참고하세요.
""",
        "8_kbs": """
KBS의 대하드라마 '고려 거란 전쟁'은 관용의 리더십으로 고려를 하나로 모아 거란과의 전쟁을 승리로 이끈 현종과 그의 정치 스승 강감찬의 이야기를 다룹니다. 본방송은 종영되었지만, KBS 공식 홈페이지와 OTT 플랫폼 웨이브(Wavve)에서 전 회차 VOD 다시보기가 가능합니다. 드라마 관련 이벤트 문의는 kbsdrama_event@kbs.co.kr로 연락 가능하며, 관련 굿즈는 KBS_GOODS_STORE에서 찾아볼 수 있습니다.
""",
        "9_sbs": """
SBS의 대표 시사 고발 프로그램 '그것이 알고 싶다'는 사회의 미해결 사건이나 의혹을 심도 깊게 추적하고 진실을 파헤칩니다. 매주 토요일 밤 11시 10분에 방송되며, 사건에 대한 제보는 전화 02-2113-5500 또는 이메일 unanswered@sbs.co.kr로 받고 있습니다. 특히 CASE_FILE_23_0815와 같은 미제 사건에 대한 시청자 여러분의 결정적인 제보를 기다립니다. ~~오래된 사건이라도 괜찮습니다.~~
""",
        "10_animation": """
인기 애니메이션 '신비아파트 고스트볼 ZERO'는 하리와 두리 남매가 귀신을 퇴치하며 겪는 오싹한 모험을 그린 투니버스(Tooniverse)의 간판 프로그램입니다. 매주 금요일 저녁 8시에 본방송을 하며, 재방송 편성표는 투니버스 공식 홈페이지에서 확인할 수 있습니다. 현재 '본방사수 인증 이벤트'를 진행 중이며, 참여는 tooniverse_event@cj.net으로 시청 사진을 보내면 됩니다. 새로운 완구 SHINBI_FIGURE_V5도 출시되었습니다.
"""
    }
    
    # --- ★★★ 모든 테스트 케이스를 순회하며 실행 ★★★ ---
    # for 반복문을 사용하여 test_cases 딕셔너리의 모든 항목을 하나씩 처리합니다.
    tasks = []
    for key, text in test_cases.items():
        print(f"\n==================== Processing Test Case: {key} ====================")
        output_file = f"output_{key}.wav"
        
        # 각 처리를 비동기 작업으로 리스트에 추가합니다.
        # 이렇게 하면 나중에 asyncio.gather를 사용하여 병렬 처리가 가능합니다. (효율성 증대)
        tasks.append(
            process_and_synthesize(text, output_file, lexicon_rules, protection_rules)
        )
    
    # 모든 작업을 동시에 실행합니다.
    await asyncio.gather(*tasks)

    print("\n==================== All test cases processed. ====================")
    
    

if __name__ == "__main__":
    # Windows에서 asyncio 실행 시 발생할 수 있는 이벤트 루프 정책 오류 방지
    # if os.name == 'nt':
    #     asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
