--------------------------------------------------------------------------------------------------
-- Practice --------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
-- How much staked ETH has been withdrawn per day over the last 14 days? 
WITH withdrawals AS (
SELECT
w.amount_lossless AS amount,
DATE(b.block_timestamp) AS block_date
FROM
bigquery-public-data.goog_blockchain_ethereum_mainnet_us.blocks b
CROSS JOIN
UNNEST(withdrawals) AS w
WHERE DATE(b.block_timestamp) BETWEEN CURRENT_DATE() - 14 AND CURRENT_DATE())
SELECT
block_date,
bqutil.fn.bignumber_div(bqutil.fn.bignumber_sum(ARRAY_AGG(amount)),
"1000000000") AS eth_withdrawn
FROM
withdrawals
GROUP BY 1 ORDER BY 1 DESC;

-- What was the daily change in market cap of USDC over the last 14 days?
CREATE TEMP FUNCTION IFMINT(input STRING, ifTrue ANY TYPE, ifFalse ANY TYPE) AS (
    CASE
      WHEN input LIKE "0x40c10f19%" THEN ifTrue
    ELSE
    ifFalse
  END
);

CREATE TEMP FUNCTION
  USD(input FLOAT64) AS ( 
    CAST(input AS STRING FORMAT "$999,999,999,999") 
);


SELECT
  DATE(block_timestamp) AS `Date`,
  USD(SUM(IFMINT(input,
        1,
        -1) * CAST(CONCAT("0x", LTRIM(SUBSTRING(input, IFMINT(input,
                75,
                11), 64), "0")) AS FLOAT64) / 1000000)) AS `Δ Total Market Value`,
FROM
  `bigquery-public-data.goog_blockchain_ethereum_mainnet_us.transactions`
WHERE
  DATE(block_timestamp) BETWEEN CURRENT_DATE() - 14
  AND CURRENT_DATE()
  AND to_address = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" -- USDC Token
  AND (input LIKE "0x42966c68%" -- Burn
    OR input LIKE "0x40c10f19%" -- Mint
    )
GROUP BY
  `Date`
ORDER BY
  `Date` DESC;

------------------------------------------------------------------------------------------------
-- 
SELECT * FROM bigquery-public-data.blockchain_analytics_ethereum_mainnet_us.decoded_events LIMIT 1000;
-- 
SELECT * FROM bigquery-public-data.blockchain_analytics_ethereum_mainnet_us.accounts_state LIMIT 1000;



--------------------------------------------------------------------------------------------------
-- 이더리움(ETH) 부의 분포도 분석 (Wealth Distribution) ------------------------------------------------
-- 최신 block_timestamp (이더리움의 가장 최근 스냅샷)를 기준으로 각 address의 balance를 집계합니다.
-- balance를 구간별로 나누어(e.g., 1 ETH 미만, 1-10 ETH, 10-100 ETH, 100+ ETH 등) 각 구간에 해당하는 지갑의 수 count
-- 이를 통해 이더리움 생태계 내 부의 집중도를 파악하고, 시간에 따른 변화를 추적할 수 있습니다.
--------------------------------------------------------------------------------------------------

WITH latest_states AS (
    SELECT
        address,
        balance / 1e18 AS eth_balance -- Wei to ETH
    FROM
        `bigquery-public-data.goog_blockchain_ethereum_mainnet_us.accounts_state`
    WHERE
        block_timestamp = (SELECT MAX(block_timestamp) FROM `bigquery-public-data.goog_blockchain_ethereum_mainnet_us.accounts_state`)
)
SELECT
    CASE
        WHEN eth_balance < 1 THEN 'Less than 1 ETH'
        WHEN eth_balance >= 1 AND eth_balance < 10 THEN '1-10 ETH'
        WHEN eth_balance >= 10 AND eth_balance < 100 THEN '10-100 ETH'
        WHEN eth_balance >= 100 AND eth_balance < 1000 THEN '100-1,000 ETH'
        ELSE '1,000+ ETH (Whales)'
    END AS wealth_bracket,
    COUNT(address) AS number_of_accounts,
    SUM(eth_balance) AS total_eth_in_bracket
FROM
    latest_states
GROUP BY
    wealth_bracket
ORDER BY
    MIN(eth_balance);


--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
-- 네트워크의 혼잡도를 나타내는 가스비는 변동성이 매우 큽니다. 과거 데이터를 기반으로 미래의 가스비를 예측 
-- 사용자는 더 저렴한 시점에 트랜잭션을 실행하는 등 비용 최적화가 가능
-- 분석 목표: 미래 특정 기간(예: 향후 7일)의 일일 평균 가스비를 예측
-- 가스비 데이터의 추세(Trend), 계절성(Seasonality), 주기(Cycle)를 ML.ARIMA_PLUS 모델로 학습시켜 미래 값을 예측
-- balance를 구간별로 나누어(e.g., 1 ETH 미만, 1-10 ETH, 10-100 ETH, 100+ ETH 등) 각 구간에 해당하는 지갑의 수를 세어봅니다.
-- 이를 통해 이더리움 생태계 내 부의 집중도를 파악하고, 시간에 따른 변화를 추적할 수 있습니다.
--------------------------------------------------------------------------------------------------

-- Step 1: Create a daily average gas price table to use for training
CREATE OR REPLACE TABLE `jc-gcp-project.jc_demo_test.daily_gas_prices` AS
SELECT
  DATE(block_timestamp) AS day,
  AVG(receipt_effective_gas_price / 1e9) AS avg_gas_price_gwei -- Gwei 단위로 변환
FROM
  `bigquery-public-data.crypto_ethereum.transactions`
WHERE
  DATE(block_timestamp) >= '2023-01-01' -- 충분한 과거 데이터로 학습
GROUP BY
  day;

-- Step 2: Create the ARIMA model
CREATE OR REPLACE MODEL `jc-gcp-project.jc_demo_test.gas_price_forecast_model`
OPTIONS(
  MODEL_TYPE='ARIMA_PLUS',
  TIME_SERIES_TIMESTAMP_COL='day',
  TIME_SERIES_DATA_COL='avg_gas_price_gwei'
) AS
SELECT
  day,
  avg_gas_price_gwei
FROM
  `jc-gcp-project.jc_demo_test.daily_gas_prices`;
  
--------------------------------------------------------------------------------------------------
-- Step 3: Forecast the next 7 days
SELECT
  *
FROM
  ML.FORECAST(MODEL `jc-gcp-project.jc_demo_test.gas_price_forecast_model`,
              STRUCT(7 AS horizon, 0.8 AS confidence_level));

-- 결과 해석: 이 쿼리는 향후 7일간의 예측된 평균 가스비(forecast_value)와 신뢰구간(confidence_interval_lower_bound, confidence_interval_upper_bound)을 보여줍니다. 이 예측을 통해 "내일은 가스비가 오를 것 같으니, 오늘 트랜잭션을 보내는 것이 유리하겠다"와 같은 의사결정을 할 수 있음



-- Step 4.1: Evaluate the model's performance
SELECT
  *
FROM
  ML.EVALUATE(MODEL `jc-gcp-project.jc_demo_test.gas_price_forecast_model`);

-- Step 4.2: Understand the components of the forecast
SELECT
  *
FROM
  ML.EXPLAIN_FORECAST(MODEL `jc-gcp-project.jc_demo_test.gas_price_forecast_model`,
                      STRUCT(7 AS horizon, 0.8 AS confidence_level));


--- Challenge
-- Challenge: Retrain the model with a longer data period
CREATE OR REPLACE TABLE `{{your_project_id}}.blockchain_demo.daily_gas_prices_extended` AS
SELECT
  DATE(block_timestamp) AS day,
  AVG(receipt_effective_gas_price / 1e9) AS avg_gas_price_gwei
FROM
  `bigquery-public-data.crypto_ethereum.transactions`
WHERE
  -- Changed the start date from 2023 to 2022 to include more data
  block_timestamp >= TIMESTAMP('2022-01-01')
GROUP BY
  day;


--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
-- 30일 이내에 "파워 유저"(트랜잭션 50회 이상 발생)가 될지 예측 ----------------------------------------------
-- 지갑 생성 후 초기 3일간의 활동 데이터를 특징(Feature)으로 사용하여, 30일 후의 최종 활동량(레이블)을 예측하도록 모델을 학습
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
-- Step 1: 모델 생성 쿼리
CREATE OR REPLACE MODEL `jc-gcp-project.jc_demo_test.wallet_power_user_classifier`
OPTIONS(
  MODEL_TYPE='BOOSTED_TREE_CLASSIFIER',
  INPUT_LABEL_COLS=['is_power_user'],
  -- 데이터 불균형을 처리하기 위한 옵션 (파워 유저는 소수일 가능성이 높음)
  AUTO_CLASS_WEIGHTS=TRUE
) AS

-- 학습에 사용할 데이터를 구성하는 과정
WITH
  -- 1. 분석 대상 지갑(주소)과 생성일 정의 (2024년에 생성된 지갑 대상)
  wallet_creation_dates AS (
    SELECT
      from_address AS address,
      MIN(block_timestamp) AS creation_timestamp
    FROM
      `bigquery-public-data.crypto_ethereum.transactions`
    WHERE
      EXTRACT(YEAR FROM block_timestamp) = 2024
    GROUP BY
      address
    LIMIT 50000 # 실제 여기 삭제하면 데이터 커짐
  ),

  -- 2. 초기 3일간의 활동 데이터를 '특징(Features)'으로 추출
  early_features AS (
    SELECT
      t.from_address AS address,
      -- 초기 3일간 트랜잭션 수
      COUNT(*) AS early_tx_count,
      -- 초기 3일간 상호작용한 고유 컨트랙트 수
      COUNT(DISTINCT t.to_address) AS early_unique_contracts,
      -- 초기 3일간 사용한 총 가스비
      SUM(t.receipt_gas_used) AS early_gas_used,
      -- 초기 3일간 Uniswap(대표 DEX)과 상호작용했는지 여부
      COUNTIF(t.to_address = '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45') > 0 AS interacted_with_uniswap,
      -- 초기 3일간 OpenSea(대표 NFT 마켓)와 상호작용했는지 여부
      COUNTIF(t.to_address = '0x00000000006c3852cbef3e08e8df289169ede581') > 0 AS interacted_with_opensea
    FROM
      `bigquery-public-data.crypto_ethereum.transactions` t
    JOIN
      wallet_creation_dates w ON t.from_address = w.address
    WHERE
      -- 생성 후 3일 내의 트랜잭션만 필터링
      t.block_timestamp BETWEEN w.creation_timestamp AND TIMESTAMP_ADD(w.creation_timestamp, INTERVAL 3 DAY)
    GROUP BY
      t.from_address
  ),

  -- 3. 생성 후 30일간의 활동을 기반으로 '정답(Label)'을 생성
  activity_labels AS (
    SELECT
      t.from_address AS address,
      -- 30일간 트랜잭션 수가 50회를 넘으면 '파워 유저'로 정의
      (COUNT(*) > 50) AS is_power_user
    FROM
      `bigquery-public-data.crypto_ethereum.transactions` t
    JOIN
      wallet_creation_dates w ON t.from_address = w.address
    WHERE
      -- 생성 후 30일 내의 트랜잭션만 필터링
      t.block_timestamp BETWEEN w.creation_timestamp AND TIMESTAMP_ADD(w.creation_timestamp, INTERVAL 30 DAY)
    GROUP BY
      t.from_address
  )

-- 4. 특징(Features)과 정답(Label)을 결합하여 최종 학습 데이터셋 생성
SELECT
  l.is_power_user,
  f.* EXCEPT (address) -- 주소는 학습에 필요 없으므로 제외
FROM
  early_features f
JOIN
  activity_labels l ON f.address = l.address;


--------------------------------------------------------------------------------------------------------------
-- Step 2: 생성된 모델로 예측하기
SELECT
  address,
  predicted_is_power_user,
  predicted_is_power_user_probs[OFFSET(1)].prob AS probability_of_being_power_user
FROM
  ML.PREDICT(
    MODEL `jc-gcp-project.jc_demo_test.wallet_power_user_classifier`,
    (
      -- 여기에 예측하고 싶은 신규 지갑들의 '초기 3일 활동 데이터'를 위와 동일한 형태로 넣어줍니다.
      -- 예시:
      SELECT
        '0xSomeNewWalletAddress' AS address,
        5 AS early_tx_count,
        4 AS early_unique_contracts,
        300000 AS early_gas_used,
        TRUE AS interacted_with_uniswap,
        FALSE AS interacted_with_opensea
    )
  );

-- 예측 결과(probability_of_being_power_user)를 통해 다음과 같은 활동을 할 수 있습니다.
-- 맞춤형 마케팅: 파워 유저가 될 확률이 높은 지갑을 대상으로 새로운 dApp이나 NFT 프로젝트를 홍보하는 에어드랍 이벤트를 진행할 수 있습니다.
-- 사용자 분석: 어떤 초기 활동 패턴(예: 'Uniswap과 상호작용', '높은 가스비 사용')이 파워 유저 전환에 큰 영향을 미치는지 ML.EXPLAIN_PREDICT 함수로 분석하여 서비스 개선에 활용할 수 있습니다.
-- 어뷰징 탐지: 특정 패턴을 보이는 지갑들이 에어드랍만을 노리는 어뷰저인지, 진성 사용자인지 구분하는 데 활용할 수도 있습니다.


CREATE OR REPLACE TABLE `{{your_project_id}}.blockchain_demo.daily_gas_prices` AS
SELECT
  DATE(block_timestamp) AS day,
  AVG(receipt_effective_gas_price / 1e9) AS avg_gas_price_gwei -- Convert to Gwei
FROM
  `bigquery-public-data.crypto_ethereum.transactions`
WHERE
  DATE(block_timestamp) >= '2023-01-01' -- Train with sufficient historical data
GROUP BY
  day;



CREATE OR REPLACE TABLE `jc-gcp-project.blockchain_dataset.daily_gas_prices` AS
SELECT
  DATE(block_timestamp) AS day,
  AVG(receipt_effective_gas_price / 1e9) AS avg_gas_price_gwei -- Convert to Gwei
FROM
  `bigquery-public-data.crypto_ethereum.transactions`
WHERE
  DATE(block_timestamp) >= '2023-01-01' -- Train with sufficient historical data
GROUP BY
  day;


CREATE OR REPLACE TABLE `jc-gcp-project.blockchain_dataset.gas_price_training_data` AS
SELECT
  day,
  avg_gas_price_gwei,
  -- Yesterday's average gas fee
  LAG(avg_gas_price_gwei, 1) OVER (ORDER BY day) AS price_yesterday,
  -- Average gas fee from 7 days ago (same day last week)
  LAG(avg_gas_price_gwei, 7) OVER (ORDER BY day) AS price_last_week
FROM
  `jc-gcp-project.blockchain_dataset.daily_gas_prices`;



CREATE OR REPLACE MODEL `jc-gcp-project.blockchain_dataset.gas_price_boosted_tree_model`
OPTIONS(
  MODEL_TYPE='BOOSTED_TREE_REGRESSOR',
  INPUT_LABEL_COLS=['avg_gas_price_gwei'] -- The value we want to predict (the label)
) AS
SELECT
  avg_gas_price_gwei,
  price_yesterday,
  price_last_week
FROM
  `jc-gcp-project.blockchain_dataset.gas_price_training_data`
WHERE
  price_yesterday IS NOT NULL AND price_last_week IS NOT NULL; -- Exclude initial rows with no feature values




SELECT
  *
FROM
  ML.PREDICT(MODEL `jc-gcp-project.blockchain_dataset.gas_price_boosted_tree_model`,
    (
      -- We need to construct the features for the day we want to predict.
      -- To predict "tomorrow", "price_yesterday" is "today's" price, and "price_last_week" is the price from "6 days ago".
      SELECT
        avg_gas_price_gwei AS price_today,
        LAG(avg_gas_price_gwei, 1) OVER (ORDER BY day) AS price_yesterday,
        LAG(avg_gas_price_gwei, 6) OVER (ORDER BY day) AS price_last_week
      FROM
        `jc-gcp-project.blockchain_dataset.daily_gas_prices`
      ORDER BY
        day DESC
      LIMIT 1 -- Get the most recent day's data to construct the features.
    ));

