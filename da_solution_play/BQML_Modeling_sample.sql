---- BQML Sample Code 입니다.
---- bigquery-public-data.ml_datasets.penguins 데이터셋을 사용하여 펭귄의 체질량을 예측하는 Linear Regression 모델 생성


------------------------------ CHECK DATA ------------------------------
-- 빅쿼리에서 제공하는 Public Dataset중 penguins 데이터셋을 활용합니다.
-- 이 데이터셋은 펭귄의 종, 섬, 부리 길이, 부리 깊이, 날개 길이, 성별, 체질량 등의 정보를 포함하고 있습

## 데이터셋 미리보기
SELECT
    *
  FROM
    `bigquery-public-data.ml_datasets.penguins`
  LIMIT 10;

## 체질량 데이터 분포 확인
SELECT
    min(body_mass_g) AS min_body_mass_g,
    max(body_mass_g) AS max_body_mass_g,
    avg(body_mass_g) AS avg_body_mass_g
  FROM
    `bigquery-public-data.ml_datasets.penguins`;

## 결측치 확인
SELECT
    count(*) AS total_rows,
    count(CASE WHEN species IS NULL THEN 1 END) AS null_species,
    count(CASE WHEN island IS NULL THEN 1 END) AS null_island,
    count(CASE WHEN culmen_length_mm IS NULL THEN 1 END) AS null_culmen_length_mm,
    count(CASE WHEN culmen_depth_mm IS NULL THEN 1 END) AS null_culmen_depth_mm,
    count(CASE WHEN flipper_length_mm IS NULL THEN 1 END) AS null_flipper_length_mm,
    count(CASE WHEN sex IS NULL THEN 1 END) AS null_sex,
    count(CASE WHEN body_mass_g IS NULL THEN 1 END) AS null_body_mass_g
  FROM
    `bigquery-public-data.ml_datasets.penguins`;



------------------------------ DATA SPLIT ------------------------------
-- Project id, dataset 이름 바꿔줘야함
-- 학습 데이터와/테스트 데이터를 분류

## Training 데이터셋 생성 (80%)
CREATE OR REPLACE TABLE `jc-gcp-project.bqmlforecast.penguins_train` AS
SELECT
    *
  FROM
    `bigquery-public-data.ml_datasets.penguins`
  WHERE
    MOD(CAST(farm_fingerprint(to_json_string(struct(species, island, culmen_length_mm, culmen_depth_mm, flipper_length_mm, sex))) AS INT64), 10) < 8
    and body_mass_g is not Null;

## Test 데이터셋 생성 (20%)
CREATE OR REPLACE TABLE `jc-gcp-project.bqmlforecast.penguins_test` AS
SELECT
    *
  FROM
    `bigquery-public-data.ml_datasets.penguins`
  WHERE
    MOD(CAST(farm_fingerprint(to_json_string(struct(species, island, culmen_length_mm, culmen_depth_mm, flipper_length_mm, sex))) AS INT64), 10) >= 8
    and body_mass_g is not Null;


--------------------------------- MODELING ----------------------------------
## BQML로 Linear Regression 모델
CREATE OR REPLACE MODEL `jc-gcp-project.bqmlforecast.penguins_model`
OPTIONS
  (model_type='linear_reg', input_label_cols=['body_mass_g']) AS
SELECT
    *
  FROM
    `jc-gcp-project.bqmlforecast.penguins_train`;


----------------------------- MODEL EVALUATION ---------------------------------
## 모델 성능 평가 (해당 프로젝트, 데이터셋 아래 MODEL에서도 확인 가능 in Console)
SELECT
    *
  FROM
    ML.EVALUATE(MODEL `jc-gcp-project.bqmlforecast.penguins_model`);


--------------------------------- PREDICTION ------------------------------------
## 새로운 데이터셋인 Test 데이터셋으로 예측 수행합니다.
SELECT
    *
  FROM
    ML.PREDICT(MODEL `jc-gcp-project.bqmlforecast.penguins_model`, TABLE `jc-gcp-project.bqmlforecast.penguins_test`);
