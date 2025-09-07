## 손상된 패키지/제품을 신속하게 식별하고 적절한 응답 생성 --> 빅쿼리로 분석 속도 향상 및 비용이 절감

# GEMINI 모델 만들기
CREATE MODEL `jc_demo_test.gemini_pro_vision_model`
REMOTE WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS(endpoint = 'gemini-pro-vision');

# External Table
CREATE OR REPLACE EXTERNAL TABLE `jc-gcp-project.jc_demo_test.broken_image`
WITH CONNECTION `jc-gcp-project.us.bigframes-rf-conn`
OPTIONS(
object_metadata = 'SIMPLE',
uris = ['gs://jc-gcp-project-01/broken_image/*'],
max_staleness = INTERVAL 1 DAY,
metadata_cache_mode = 'AUTOMATIC');

# Generate text
CREATE OR REPLACE TABLE `jc_demo_test.broken_image_json_result` AS
WITH raw_json_result AS(
SELECT  uri,
       CAST(23050 + ROW_NUMBER() OVER(ORDER BY uri) AS string) AS order_id,
       ml_generate_text_llm_result AS img_analysis
 FROM ML.GENERATE_TEXT(
   MODEL`jc_demo_test.gemini_pro_vision_model`,
   TABLE `jc-gcp-project.jc_demo_test.broken_image`,
   STRUCT(
      'You are part of a customer service team and you are trying to determine wheather the images submitted by customers are of damaged packaging or damaged products or nothing was damaged or if the image was of a package or not. Plaese return the result in the JSON format with three keys: is_package_damaged, is_product_damaged and details' AS PROMPT,
     200 AS max_output_tokens,
     0.5 AS temperature,
     40 AS top_k,
     1.0 AS top_p,
     TRUE AS flatten_json_output
   )))
SELECT
  uri, order_id,
  JSON_QUERY(RTRIM(LTRIM(raw_json_result.img_analysis, " ```json"), "```"), "$.is_package_damaged") AS is_package_damaged,
  JSON_QUERY(RTRIM(LTRIM(raw_json_result.img_analysis, " ```json"), "```"), "$.is_product_damaged") AS is_product_damaged,
  JSON_QUERY(RTRIM(LTRIM(raw_json_result.img_analysis, " ```json"), "```"), "$.details") AS details
FROM raw_json_result;

# Check Result
SELECT * from `jc_demo_test.broken_image_json_result`;

# Drop off table
SELECT order_id, latitude, longitude, ST_GeogPoint(longitude, latitude)  AS WKT, driver_name, time_of_the_day
from `jc-gcp-project.jc_demo_test.dropoff`;



# Join together to check
CREATE OR REPLACE TABLE `jc_demo_test.order_dropoff_insight` AS
SELECT o1.order_id, i1.uri, i1.is_package_damaged, i1.is_product_damaged, i1.details, o1.latitude, o1.longitude, ST_GeogPoint(o1.longitude, o1.latitude)  AS WKT, o1.driver_name, o1.time_of_the_day
FROM `jc-gcp-project.jc_demo_test.dropoff` AS o1
JOIN `jc_demo_test.broken_image_json_result` AS i1
ON o1.order_id = i1.order_id;


select * from `jc_demo_test.order_dropoff_insight`;