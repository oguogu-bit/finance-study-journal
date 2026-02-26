#!/bin/bash
# 金融リテラシー毎日学習 — 自動生成スクリプト
# 毎朝6時にlaunchdから実行される

set -euo pipefail

# PATHを明示的に設定（launchd環境用）
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# スクリプト配置場所からリポジトリルートを特定する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_DIR/$YEAR/$MONTH"
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"
VALIDATOR="$HOME/.codex/skills/finance-study/scripts/validate_note.sh"

if ! command -v claude >/dev/null 2>&1; then
  echo "claude コマンドが見つかりません。PATHを確認してください。"
  exit 1
fi

# すでに今日のファイルがあればスキップ
if [ -f "$OUTPUT_FILE" ]; then
  echo "[$TODAY] すでに本日のコンテンツが存在します: $OUTPUT_FILE"
  exit 0
fi

echo "[$NOW] コンテンツ生成を開始します..."

# 出力先ディレクトリを作成
mkdir -p "$OUTPUT_DIR"

# Claude CLIで finance-study スキルを実行
claude -p "/finance-study" \
  --output-format text \
  --no-session-persistence \
  > "$OUTPUT_FILE"

if [ -x "$VALIDATOR" ]; then
  "$VALIDATOR" "$OUTPUT_FILE"
fi

echo "[$NOW] 生成完了 → $OUTPUT_FILE"

# Gitコミット＆プッシュ
cd "$REPO_DIR"
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "origin リモートが未設定のため、pushをスキップします。"
  exit 0
fi

git add "$OUTPUT_FILE"
if git diff --cached --quiet; then
  echo "追加された差分がないため、commit/pushをスキップします。"
  exit 0
fi

git commit -m "📚 Daily study: $TODAY"
git push origin main

echo "[$NOW] GitHubへのpushが完了しました"
