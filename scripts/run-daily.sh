#!/bin/bash
# 金融リテラシー毎日学習 — 自動生成スクリプト
# 毎朝6時にlaunchdから実行される

set -euo pipefail

# PATHを明示的に設定（launchd環境用）
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)

REPO_DIR="$HOME/finance-study"
OUTPUT_DIR="$REPO_DIR/$YEAR/$MONTH"
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"

# すでに今日のファイルがあればスキップ
if [ -f "$OUTPUT_FILE" ]; then
  echo "[$TODAY] すでに本日のコンテンツが存在します: $OUTPUT_FILE"
  exit 0
fi

echo "[$TODAY 06:00] コンテンツ生成を開始します..."

# 出力先ディレクトリを作成
mkdir -p "$OUTPUT_DIR"

# Claude CLIで finance-study スキルを実行
claude -p "/finance-study" \
  --output-format text \
  --no-session-persistence \
  > "$OUTPUT_FILE"

echo "[$TODAY 06:00] 生成完了 → $OUTPUT_FILE"

# Gitコミット＆プッシュ
cd "$REPO_DIR"
git add "$OUTPUT_FILE"
git commit -m "📚 Daily study: $TODAY"
git push origin main

echo "[$TODAY 06:00] GitHubへのpushが完了しました"
