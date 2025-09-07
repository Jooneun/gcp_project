#!/usr/bin/env python3
# -*- encoding: utf-8 -*-
# vim: tabstop=2 shiftwidth=2 softtabstop=2 expandtab

import os
import json
import requests
import logging
from typing import Optional
from google.adk.tools import LongRunningFunctionTool

# 로깅 설정
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_products(query: str, category: Optional[str] = None, max_results: int = 10):
    """
    Find products using Naver Shopping API.
    
    Args:
        query (str): Product search query (e.g., "송이버섯", "팽이버섯")
        category (Optional[str]): Product category
        max_results (int): Maximum number of results to return (default: 10)
    
    Returns:
        dict: Product information
    """
    logger.info(f"=== find_products function called ===")
    logger.info(f"Query: {query}")
    logger.info(f"Category: {category}")
    logger.info(f"Max results: {max_results}")
    
    try:
        # 네이버 쇼핑 API 사용
        naver_client_id = os.environ.get("NAVER_CLIENT_ID")
        naver_client_secret = os.environ.get("NAVER_CLIENT_SECRET")
        
        logger.info(f"NAVER_CLIENT_ID exists: {bool(naver_client_id)}")
        logger.info(f"NAVER_CLIENT_SECRET exists: {bool(naver_client_secret)}")
        
        if not naver_client_id or not naver_client_secret:
            logger.error("NAVER_CLIENT_ID and NAVER_CLIENT_SECRET not set")
            return {"error": "NAVER_CLIENT_ID and NAVER_CLIENT_SECRET not set"}
        
        # 네이버 쇼핑 검색 API
        url = "https://openapi.naver.com/v1/search/shop.json"
        headers = {
            'X-Naver-Client-Id': naver_client_id,
            'X-Naver-Client-Secret': naver_client_secret
        }
        params = {
            'query': query,
            'display': max_results,
            'sort': 'sim'  # 정확도순
        }
        
        logger.info(f"Making request to Naver API")
        logger.info(f"URL: {url}")
        logger.info(f"Headers: {headers}")
        logger.info(f"Params: {params}")
        
        response = requests.get(url, headers=headers, params=params)
        logger.info(f"Naver API response status: {response.status_code}")
        logger.info(f"Naver API response headers: {dict(response.headers)}")
        
        data = response.json()
        logger.info(f"Naver API response data: {json.dumps(data, indent=2, ensure_ascii=False)}")
        
        if response.status_code == 200 and 'items' in data:
            products = []
            for item in data['items']:
                products.append({
                    "name": clean_title(item.get('title', '')),
                    "price": item.get('lprice', 'N/A'),
                    "store": item.get('mallName', 'Unknown'),
                    "link": item.get('link', ''),
                    "image": item.get('image', ''),
                    "rating": item.get('rating', 'N/A')
                })
            
            logger.info(f"Found {len(products)} products")
            logger.info(f"Total results from API: {data.get('total', 0)}")
            result = {"products": products, "total": data.get('total', 0)}
            logger.info(f"Returning result: {json.dumps(result, indent=2, ensure_ascii=False)}")
            return result
        else:
            logger.error(f"Failed to fetch products: {response.status_code}")
            logger.error(f"Response data: {data}")
            
            # 더 친화적인 에러 메시지 제공
            if response.status_code == 401:
                return {"error": "API 인증에 실패했습니다. 잠시 후 다시 시도해 주세요."}
            elif response.status_code == 429:
                return {"error": "API 호출 한도를 초과했습니다. 잠시 후 다시 시도해 주세요."}
            else:
                return {"error": "상품 검색 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요."}
            
    except Exception as e:
        logger.error(f"Exception in find_products: {str(e)}", exc_info=True)
        return {"error": f"An error occurred: {str(e)}"}

def clean_title(title: str) -> str:
    """제목에서 HTML 태그 제거"""
    return title.replace('<b>', '').replace('</b>', '').replace('&amp;', '&')

# ADK 도구로 등록
find_products_tool = LongRunningFunctionTool(func=find_products)