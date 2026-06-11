# moc-skill — FIWARE Orion 読み取り専用クエリ OpenCode スキル

[FIWARE Orion Context Broker](https://fiware-orion.readthedocs.io/) (NGSIv2) に対して、生成 AI エージェントから**認証不要の GET のみ**でエンティティ情報を取得するための [Agent Skills](https://agentskills.io/) 互換スキルです。

- Entity の Read のみ（書き込み・Subscription・Registration は非対応）
- `endpoints.json` カタログに登録された基盤だけアクセス可能
- エージェントは `scripts/orion.sh` 経由でのみ Orion に問い合わせる

[![skills.sh](https://skills.sh/b/kzkski/moc-skill)](https://skills.sh/kzkski/moc-skill)

## インストール

[skills CLI](https://github.com/vercel-labs/skills)（`npx skills add`）でのインストールを推奨します。OpenCode、Claude Code、Cursor など 70 以上のエージェントに対応しています。

### プロジェクトにインストール（推奨）

```bash
# 利用可能スキルを確認
npx skills add kzkski/moc-skill --list

# OpenCode 向けにインストール（ツール詳細をデフォルト非表示にする初期設定付き）
npx skills add kzkski/moc-skill -a opencode -y
.agents/skills/moc-skill/scripts/setup-opencode.sh

# 複数エージェント向け
npx skills add kzkski/moc-skill -a opencode -a claude-code -a cursor -y
```

### グローバルにインストール

```bash
npx skills add kzkski/moc-skill -g -a opencode -y
```

### ローカル clone からインストール

```bash
git clone https://github.com/kzkski/moc-skill.git
cd your-project
npx skills add /path/to/moc-skill -a opencode -y
```

インストール後、エージェントを再起動すると `moc-skill` スキルが読み込まれます。

OpenCode では `setup-opencode.sh` を一度実行すると、bash などのツール実行詳細がデフォルトで非表示になります（`~/.local/state/opencode/kv.json` の `tool_details_visibility` を `false` に設定）。詳細を一時的に見るには OpenCode で `/details` を実行してください。

| エージェント | プロジェクト配置先 | グローバル配置先 |
|--------------|-------------------|------------------|
| OpenCode | `.agents/skills/moc-skill/` | `~/.config/opencode/skills/moc-skill/` |
| Claude Code | `.claude/skills/moc-skill/` | `~/.claude/skills/moc-skill/` |
| Cursor | `.agents/skills/moc-skill/` | `~/.cursor/skills/moc-skill/` |

### 手動インストール

`npx skills add` が使えない場合は、スキルディレクトリを直接コピーします。

```bash
mkdir -p .agents/skills
cp -R skills/moc-skill .agents/skills/
```

## リポジトリ構成

```
moc-skill/
├── README.md
├── LICENSE
├── skills.sh.json
├── .github/workflows/ci.yml
├── skills/moc-skill/
│   ├── SKILL.md
│   ├── endpoints.json
│   └── scripts/
│       ├── orion.sh
│       └── setup-opencode.sh
└── tests/orion.bats
```

## 依存

- [curl](https://curl.se/)
- [jq](https://jqlang.github.io/jq/)
- Node.js（`npx skills add` 利用時のみ）

macOS (Homebrew) の例:

```bash
brew install curl jq
```

## endpoints.json の編集

インストール後はスキル配下の `endpoints.json` を編集します（例: `.agents/skills/moc-skill/endpoints.json`）。

```json
{
  "endpoints": {
    "my-city": {
      "base_url": "https://orion.my-city.makeour.city",
      "Fiware-Service": "city",
      "Fiware-ServicePath": "/prod",
      "note": "本番都市OS基盤"
    }
  }
}
```

| フィールド | 説明 |
|------------|------|
| `base_url` | Orion のベース URL（例: `https://orion.<自治体>.makeour.city`、`http://` または `https://` のみ） |
| `Fiware-Service` | NGSIv2 リクエストヘッダー `Fiware-Service` の値（不要なら `""`） |
| `Fiware-ServicePath` | NGSIv2 リクエストヘッダー `Fiware-ServicePath` の値（不要なら `""`） |
| `note` | 人間向けの説明 |

別ファイルを使う場合は環境変数で指定します。

```bash
export ORION_ENDPOINTS_FILE=/path/to/my-endpoints.json
```

## 使用例（エージェントへの依頼文）

スキル配置後、エージェントに自然言語で依頼できます。

- 「登録されている Orion 基盤を一覧して」
- 「仙台の基盤（sendai）にどんなデータ型があるか調べて」
- 「sendai の AirQualityObserved 型のエンティティを 10 件取得して」
- 「local 基盤で type=Device のエンティティ件数を教えて」
- 「demo 基盤の sensor-001 エンティティの location 属性だけ見せて」

## CLI 直接実行

```bash
ORION=.agents/skills/moc-skill/scripts/orion.sh

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
shellcheck skills/moc-skill/scripts/orion.sh
npx skills add . --list
```

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。
