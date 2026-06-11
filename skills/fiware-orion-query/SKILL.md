---
name: fiware-orion-query
description: >-
  FIWARE Orion Context Broker (NGSIv2) からエンティティ情報を読み取り専用で取得する。
  データ連携基盤・都市OS・スマートシティ基盤・センサーデータ・IoTプラットフォームへの
  GET クエリ、エンティティ一覧・型探索、NGSIv2 API 調査が必要なときに能動的に使う。
  Orion / NGSIv2 / Context Broker / エンティティ取得 / type 一覧 / q クエリ /
  地理空間クエリ / Fiware-Service ヘッダー付き基盤アクセスの依頼で発火する。
---

# FIWARE Orion 読み取り専用クエリ

FIWARE Orion Context Broker (NGSIv2) に対して、**認証不要の GET のみ**でエンティティ情報を取得するスキルです。書き込み・Subscription・Registration は実装していません。

## 重要: アクセス経路

**必ず `scripts/orion.sh` 経由でアクセスすること。** カタログ外 URL へ直接 `curl` しないでください。対象基盤は `endpoints.json` に登録された名前だけを使います。

```bash
SKILL_DIR="skills/fiware-orion-query"   # 配置先に合わせて調整
ORION="${SKILL_DIR}/scripts/orion.sh"
```

環境変数 `ORION_ENDPOINTS_FILE` でカタログパスを上書きできます（未設定時はスキル同梱の `endpoints.json`）。

## 推奨ワークフロー

エージェントは次の順で探索します。

1. **endpoints** — 利用可能な基盤名を確認
2. **types** — 対象基盤に存在する Entity Type 一覧と件数を把握
3. **entities / entity / count** — 型や条件を絞ってエンティティを取得・件数確認

```bash
"${ORION}" endpoints
"${ORION}" types sendai
"${ORION}" entities sendai type=AirQualityObserved limit=10
"${ORION}" count sendai type=AirQualityObserved
"${ORION}" entity sendai "sensor-001" attrs=location,PM25
```

## コマンドリファレンス

| コマンド | 説明 |
|----------|------|
| `endpoints` | カタログに登録された基盤名・URL・説明を表示 |
| `types <ep>` | `GET /v2/types?options=count` |
| `entities <ep> [k=v ...]` | `GET /v2/entities`（未指定時 `options=keyValues` `limit=20` を付与） |
| `entity <ep> <id> [k=v ...]` | `GET /v2/entities/{id}`（同上デフォルト付与） |
| `count <ep> [k=v ...]` | `limit=1&options=count` で `Fiware-Total-Count` ヘッダーのみ返す |
| `raw <ep> <path?query>` | `/v2/` 配下に限定した任意 GET |

`<ep>` は `endpoints.json` のキー名（例: `local`, `sendai`）。

### デバッグ

`ORION_DRY_RUN=1` を設定すると curl コマンドを表示するだけで実行しません。

```bash
ORION_DRY_RUN=1 "${ORION}" entities local type=Device
```

## NGSIv2 クエリパラメータ早見表

`entities` / `entity` / `count` / `raw` の `[k=v ...]` または `raw` のクエリ文字列に指定します。

| パラメータ | 用途 |
|------------|------|
| `type` | Entity Type でフィルタ（例: `type=Device`） |
| `q` | 属性条件（例: `q=temperature>25`） |
| `attrs` | 返却属性の限定（例: `attrs=location,temperature`） |
| `idPattern` | エンティティ ID の正規表現（例: `idPattern=^sensor-.*`） |
| `limit` | 最大取得件数（`entities`/`entity` デフォルト 20） |
| `offset` | ページング開始位置 |
| `orderBy` | ソート（例: `orderBy=!dateObserved`） |
| `georel` + `geometry` + `coords` | 地理空間クエリ（例: `georel=near;maxDistance:1000` `geometry=Point` `coords=-3.7,40.4`） |
| `options` | レスポンス形式（`keyValues`, `count`, `values` など） |

## 注意点

- **読み取り専用**: POST / PATCH / DELETE / Subscription / Registration は行わない
- **カタログ必須**: 未定義のエンドポイント名は拒否される
- **raw は /v2/ のみ**: `/v2/` 以外へのパスはエラー
- **Entity ID**: `[A-Za-z0-9._:~-]+` のみ許可（パストラバーサル対策）
- **Fiware ヘッダー**: `endpoints.json` の `service` / `service_path` が空でなければ自動付与
- **依存**: `curl`, `jq` が PATH に必要

## カタログ形式 (`endpoints.json`)

```json
{
  "endpoints": {
    "<名前>": {
      "base_url": "https://orion.example.jp",
      "service": "Fiware-Serviceヘッダー値(不要なら空文字)",
      "service_path": "Fiware-ServicePath(不要なら空文字)",
      "note": "説明"
    }
  }
}
```

新しい基盤を追加するときは、運用者が提供する Orion URL と Fiware ヘッダー値をこの形式で追記してください。
