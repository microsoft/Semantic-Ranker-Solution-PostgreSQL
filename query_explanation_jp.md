# semantic_reranker.sqlの解説

この関数は、与えられた検索クエリと候補となる記事群（文字列の配列）をもとに、外部のAzure MLサービスを呼び出して「意味的再ランキング（semantic reranking）」を行い、
その結果として各記事に対応する関連度情報を返すものです。以下、各部分の詳細な解説を示します。

## 関数全体の概要

### 名前と引数
関数名は semantic_reranking で、引数は
* query TEXT：ユーザーの検索クエリ
* vector_search_results TEXT[]：ベクトル検索によって得られた候補記事のリスト

```sql
CREATE OR REPLACE FUNCTION semantic_reranking(query TEXT, vector_search_results TEXT[])
```

### 戻り値
戻り値はテーブル形式で、各行は
* article TEXT：記事の本文（または記事の識別情報）
* relevance jsonb：Azure MLから返された関連度情報（JSON形式）

```sql
RETURNS TABLE (article TEXT, relevance jsonb) AS $$
```

### 言語
PL/pgSQL を用いて記述されています。

```sql
END $$ LANGUAGE plpgsql;
```

## CTE（共通テーブル式）による処理の流れ

関数内部では、複数のCTEを使って段階的に処理を進めています。各CTEの役割は以下の通りです。
1. json_pairs CTE

目的: クエリと各記事をペアにしたJSONオブジェクトを作成する。

処理内容:
* [unnest](https://www.postgresql.jp/docs/9.4/functions-array.html#ARRAY-FUNCTIONS-TABLE)(vector_search_results) により、配列内の各記事を個別の行に展開し、各行の値を article_ として取得します。
* [jsonb_build_array](https://www.postgresql.jp/docs/9.5/functions-json.html#functions-json-creation-table)(query, article_) を用いて、各ペア（検索クエリと記事）をJSON配列に変換。
* [jsonb_agg](https://www.postgresql.jp/docs/9.5/functions-aggregate.html#functions-aggregate-table) により、これらのペアを一つのJSON配列にまとめ、最終的にキー 'pairs' を持つJSONオブジェクトを生成します。

結果: 例として { "pairs": [ [ "検索クエリ", "記事1" ], [ "検索クエリ", "記事2" ], ... ] } のようなJSONデータ。

```sql
json_pairs AS(
  SELECT jsonb_build_object(
    'pairs',
    jsonb_agg(
      jsonb_build_array(query, article_)
    )
  ) AS json_pairs_data
  FROM (
    SELECT a.article as article_
    FROM unnest(vector_search_results) as a(article)
  )
),
```

2. relevance_scores CTE
目的: 作成したJSONを入力として、Azure MLのエンドポイントを呼び出し、各ペアに対する関連度（relevance）の結果を取得する。

処理内容:
* [azure_ml.invoke 関数](https://learn.microsoft.com/ja-jp/azure/postgresql/flexible-server/generative-ai-azure-machine-learning)を呼び出し、先ほどの json_pairs で作成したJSONデータを渡す。
* deployment_name=>'bgev2m3-v1' と timeout_ms => 120000 により、特定のMLモデル（またはエンドポイント）を指定し、タイムアウトを設定しています。
* 返ってくる結果はJSON形式の配列であると想定され、その各要素を [jsonb_array_elements](https://www.postgresql.jp/docs/16/functions-json.html#FUNCTIONS-JSON-PROCESSING-TABLE) で展開して、各行に relevance_results として取り出します。

```sql
relevance_scores AS(
  SELECT jsonb_array_elements(invoke.invoke) as relevance_results
  FROM azure_ml.invoke(
    (SELECT json_pairs_data FROM json_pairs),
    deployment_name=>'bgev2m3-v1', timeout_ms => 120000)
),
```

3. relevance_scores_rn CTE
目的: 取得した関連度結果に対して行番号（ROW_NUMBER）を付与することで、元の配列の順序と対応させるためのインデックスを作成する。

処理内容:
* [ROW_NUMBER()](https://www.postgresql.jp/docs/9.6/functions-window.html#functions-window-table) OVER () を使って、各行に連番（idx）を割り当てています。

```sql
relevance_scores_rn AS (
  SELECT *, ROW_NUMBER() OVER () AS idx
  FROM relevance_scores
)
```

## 最終的な結果の組み立て
unnestとWITH ORDINALITYの利用
* unnest(vector_search_results) WITH ORDINALITY を用いて、元の候補記事配列から各記事とその順番（idx2）を取得しています。
* これにより、元記事の並び順を保持するためのインデックスが得られます。

```sql
FROM
  unnest(vector_search_results) WITH ORDINALITY AS a(article, idx2)
```

JOIN処理
* relevance_scores_rn のインデックス idx と、unnest で得た idx2 をキーに内部結合（JOIN）を行います。
* これにより、各記事とその記事に対するMLによる関連度評価結果を正しくペアリングできます。

```sql
JOIN
  relevance_scores_rn AS r(relevance_results, idx)
ON
  a.idx2 = r.idx;
```

SELECT句
* 結果として、各行に記事 (article) と対応する関連度 (relevance_results、エイリアスとして relevance) を返すようにしています。

```sql
SELECT a.article,
  r.relevance_results
```

## 全体の流れ
1. 入力データの整形:
検索クエリと候補記事をペアにしてJSON形式にまとめる。

2. MLモデルの呼び出し:
整形したJSONをAzure MLの指定デプロイメントに渡し、関連度評価を受け取る。

3. 結果の再整列:
MLからの結果と元の候補記事の順序を、インデックスを用いて一致させる。

4. 出力:
各記事とその評価結果（関連度スコアや詳細情報）が返され、これにより後続の処理で再ランキングされた結果として利用可能になる。

## 注意点
順序の保証:
関数は、元の vector_search_results の順序とAzure MLからの結果の順序が一致していることを前提に行番号を付与し結合しています。これにより、各記事とその評価結果が正しく対応します。

Azure MLの呼び出し:
azure_ml.invoke の部分は、実際にはAzure上にデプロイされたMLモデルとの連携部分となっており、実行環境や設定によっては別途設定が必要になる場合があります。

タイムアウト設定:
タイムアウト（timeout_ms => 120000）は2分間に設定されています。長時間の呼び出しを避けるための工夫です。
