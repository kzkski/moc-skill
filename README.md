# moc-skill — FIWARE Orion 読み取り専用クエリ OpenCode スキル

[FIWARE Orion Context Broker](https://fiware-orion.readthedocs.io/) (NGSIv2) に対して、生成 AI エージェントから**認証不要の GET のみ**でエンティティ情報を取得するための [OpenCode](https://opencode.ai/) スキルです。

- Entity の Read のみ（書き込み・Subscription・Registration は非対応）
- `endpoints.json` カタログに登録された基盤だけアクセス可能
- エージェントは `scripts/orion.sh` 経由でのみ Orion に問い合わせる

## リポジトリ構成

```
moc-skill/
├── README.md
├── LICENSE
├── .github/workflows/ci.yml
├── skills/fiware-orion-query/
│   ├── SKILL.md
│   ├── endpoints.json
│   └── scripts/orion.sh
└── tests/orion.bats
```

## インストール

スキルディレクトリ `skills/fiware-orion-query/` を、利用環境のスキル配置先にコピーまたはシンボリックリンクします。

### OpenCode（プロジェクトローカル）

```bash
mkdir -p .opencode/skills
cp -R skills/fiware-orion-query .opencode/skills/
```

### OpenCode（グローバル）

```bash
mkdir -p ~/.config/opencode/skills
cp -R skills/fiware-orion-query ~/.config/opencode/skills/
```

### Claude Code 互換

Claude Code でも同じ SKILL.md 形式を利用できます。

```bash
mkdir -p .claude/skills
cp -R skills/fiware-orion-query .claude/skills/
```

## 依存

- [curl](https://curl.se/)
- [jq](https://jqlang.github.io/jq/)

macOS (Homebrew) の例:

```bash
brew install curl jq
```

## endpoints.json の編集

`skills/fiware-orion-query/endpoints.json` に Orion エンドポイントを登録します。

```json
{
  "endpoints": {
    "my-city": {
      "base_url": "https://orion.example.jp",
      "service": "city",
      "service_path": "/prod",
      "note": "本番都市OS基盤"
    }
  }
}
```

| フィールド | 説明 |
|------------|------|
| `base_url` | Orion のベース URL（`http://` または `https://` のみ） |
| `service` | `Fiware-Service` ヘッダー（不要なら `""`） |
| `service_path` | `Fiware-ServicePath` ヘッダー（不要なら `""`） |
| `note` | 人間向けの説明 |

別ファイルを使う場合は環境変数で指定します。

```bash
export ORION_ENDPOINTS_FILE=/path/to/my-endpoints.json
```

## 使用例（エージェントへの依頼文）

スキル配置後、OpenCode エージェントに自然言語で依頼できます。

- 「登録されている Orion 基盤を一覧して」
- 「仙台の基盤（sendai）にどんなデータ型があるか調べて」
- 「sendai の AirQualityObserved 型のエンティティを 10 件取得して」
- 「local 基盤で type=Device のエンティティ件数を教えて」
- 「demo 基盤の sensor-001 エンティティの location 属性だけ見せて」

エージェントは `skills/fiware-orion-query/scripts/orion.sh` を実行して結果を解釈します。

## CLI 直接実行

```bash
ORION=skills/fiware-orion-query/scripts/orion.sh

"$ORION" endpoints
"$ORION" types sendai
"$ORION" entities sendai type=AirQualityObserved limit=5
"$ORION" count sendai type=Device
"$ORION" entity local Room1 attrs=temperature

# デバッグ（curl コマンドのみ表示）
ORION_DRY_RUN=1 "$ORION" entities local
```

## テスト

[bats](https://github.com/bats-core/bats-core) でドライラン検証します（実 Orion への疎通は不要）。

```bash
bats tests/
shellcheck skills/fiware-orion-query/scripts/orion.sh
```

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。
