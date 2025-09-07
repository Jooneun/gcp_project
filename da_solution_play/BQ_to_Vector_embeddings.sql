# GEMINI 모델 만들기
CREATE MODEL jc_demo_test.bq_gemini_pro
REMOTE WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS(endpoint = 'gemini-pro');

# GEMINI 모델 사용하기
SELECT prompt, ml_generate_text_result.candidates[0].content.parts[0].text
FROM
  ML.GENERATE_TEXT(
    MODEL jc_demo_test.bq_gemini_pro,
    (SELECT '"E-Mart"와 빅쿼리로 분석과제 하고 싶어. 어떤 과제가 좋을지 알려줘.' AS prompt),
    STRUCT(
      0.8 AS temperature,
      1024 AS max_output_tokens,
      0.95 AS top_p,
      40 AS top_k));


# External Table including Image
CREATE OR REPLACE EXTERNAL TABLE `jc-gcp-project.jc_demo_test.shopping_image`
WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS (
    object_metadata="DIRECTORY",
    uris = ['gs://jc-gcp-project-01/shopping_image_sample/*.png'],
    max_staleness=INTERVAL 30 MINUTE, 
    --metadata_cache_mode="AUTOMATIC"
    -- set to Manual for demo
    metadata_cache_mode="MANUAL"
    ); 
##################################################################
# External Table including Image
CREATE OR REPLACE EXTERNAL TABLE `jc-gcp-project.jc_demo_test.card_image`
WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS (
    object_metadata="DIRECTORY",
    uris = ['gs://jc-gcp-project-01/shopping_image_sample/lotte/*.png'],
    max_staleness=INTERVAL 30 MINUTE, 
    --metadata_cache_mode="AUTOMATIC"
    -- set to Manual for demo
    metadata_cache_mode="MANUAL"
    ); 
##################################################################
# Create Gemini Vision Model
CREATE MODEL `jc_demo_test.gemini_pro_vision_model`
REMOTE WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS(endpoint = 'gemini-pro-vision');


# GEMINI Multi-modal 테스트
SELECT
   uri,
   ml_generate_text_llm_result as brand_inf
 FROM
   ML.GENERATE_TEXT(
     MODEL `jc_demo_test.gemini_pro_vision_model`,
     TABLE `jc-gcp-project.jc_demo_test.shopping_image`,
     STRUCT(
       '1. 제품명, 2. 평균가격, 3. 인기있는 정도를 알려줘. ' AS prompt, TRUE AS flatten_json_output));
##################################################################
# GEMINI Multi-modal 테스트
SELECT
   uri,
   ml_generate_text_llm_result as brand_inf
 FROM
   ML.GENERATE_TEXT(
     MODEL `jc_demo_test.gemini_pro_vision_model`,
     TABLE `jc-gcp-project.jc_demo_test.shopping_image`,
     STRUCT(
       '1. 카드명, 2. 대표적 혜택, 3. 연회비 알려줘. ' AS prompt, TRUE AS flatten_json_output));
##################################################################


# 활용하기 위한 전처리
WITH raw_json_result AS ( 
SELECT
   uri,
   ml_generate_text_llm_result as brand_inf
 FROM
   ML.GENERATE_TEXT(
     MODEL `jc_demo_test.gemini_pro_vision_model`,
     TABLE `jc-gcp-project.jc_demo_test.shopping_image`,
     STRUCT(
       '1. 구체적인 제품명, 2. 평균가격, 3. 인기있는 정도 알려줘. 답은 JSON 포맷. 제품명은 STRING, 평균가격은 원화로 integer, 인기도는 5점 Rate로 알려줘.' AS prompt, TRUE AS flatten_json_output)))
SELECT
   uri,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.제품명") AS Name,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.평균가격") AS Price,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.인기도") AS Popularity
FROM raw_json_result

##################################################################
# 활용하기 위한 전처리
WITH raw_json_result AS ( 
SELECT
   uri,
   ml_generate_text_llm_result as brand_inf
 FROM
   ML.GENERATE_TEXT(
     MODEL `jc_demo_test.gemini_pro_vision_model`,
     TABLE `jc-gcp-project.jc_demo_test.card_image`,
     STRUCT(
       '1. 카드명, 2. 대표적 혜택, 3. 연회비 알려줘. 답은 JSON 포맷. 대표적 혜택은 세가지, 연회비는 카드명 참고해서 상세히 알려줘.' AS prompt, TRUE AS flatten_json_output)))
SELECT
   uri,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.카드명") AS Name,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.대표적 혜택") AS Benefit,
   JSON_QUERY(RTRIM(LTRIM(raw_json_result.brand_inf, " ```json"), "```"), "$.연회비") AS Price
FROM raw_json_result
##################################################################


#### 주소 찾기
SELECT prompt, ml_generate_text_result.candidates[0].content.parts[0].text
FROM
  ML.GENERATE_TEXT(
    MODEL jc_demo_test.bq_gemini_pro,
    (SELECT '"강남파이넨스센터"의 주소 알려줘. "롯데아웃렛 서울역점 : 405 Hangang-daero, Yongsan-gu, Seoul, South Korea"과 같은 형식으로 알려줘' AS prompt),
    STRUCT(
      0.8 AS temperature,
      1024 AS max_output_tokens,
      0.95 AS top_p,
      40 AS top_k));

#################################################################################
#################################################################################
### Text Embedding
CREATE MODEL jc_demo_test.bq_text_embedding_gecko
REMOTE WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS(endpoint = 'textembedding-gecko-multilingual');

CREATE OR REPLACE TABLE jc-gcp-project.jc_demo_test.text_reveiw_only AS
SELECT Review AS review FROM `jc-gcp-project.jc_demo_test.review_text_sample`;

### Generate Embedding
CREATE OR REPLACE TABLE `jc-gcp-project.jc_demo_test.review_text_embedding` AS (
SELECT *
FROM ML.GENERATE_EMBEDDING(
  MODEL `jc-gcp-project.jc_demo_test.bq_text_embedding_gecko`,
  (SELECT Review as content from `jc-gcp-project.jc_demo_test.review_text_sample`),
  STRUCT(TRUE AS flatten_json_output)
));

#### K-means clustering
CREATE OR REPLACE MODEL jc_demo_test.review_embed_clustering
OPTIONS (model_type = 'KMEANS', KMEANS_INIT_METHOD = 'KMEANS++', num_clusters = 10) AS
(SELECT ml_generate_embedding_result FROM jc_demo_test.review_text_embedding WHERE ARRAY_LENGTH(ml_generate_embedding_result)=768);

### Testset -- 여기부터 시작
CREATE OR REPLACE TABLE jc_demo_test.review_testset_embed AS (
SELECT * FROM ML.GENERATE_EMBEDDING(MODEL `jc-gcp-project.jc_demo_test.bq_text_embedding_gecko`,
(SELECT "분위기 개꿀" AS content), STRUCT (TRUE AS flatten_json_output))
);

### Search the testset
SELECT CENTROID_ID, ml_generate_embedding_result
FROM ML.PREDICT(
  MODEL jc_demo_test.review_embed_clustering,
  (SELECT ml_generate_embedding_result FROM jc_demo_test.review_testset_embed)
);

### Cluster 찾기
CREATE OR REPLACE TABLE jc_demo_test.cluster_target_embedding AS (
  SELECT * FROM
             ML.PREDICT(
              MODEL jc_demo_test.review_embed_clustering,
              (SELECT ml_generate_embedding_result, content FROM jc_demo_test.review_text_embedding 
              WHERE ARRAY_LENGTH(ml_generate_embedding_result)=768)
             )
             WHERE centroid_id = 1
  );

### Get Closed values 
SELECT
  test.content AS search_content,
  clustered.content AS db_content,
  ML.DISTANCE(test.ml_generate_embedding_result, clustered.ml_generate_embedding_result, 'COSINE') AS distance
FROM
  jc_demo_test.review_testset_embed AS test,
  jc_demo_test.cluster_target_embedding AS clustered
--where clustered.content not like '%존맛탱%'
ORDER BY distance ASC
;