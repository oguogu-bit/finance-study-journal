#!/bin/bash
# 金融リテラシー毎日学習 — 自動生成スクリプト
# 毎朝6時にlaunchdから実行される
# 日曜日は週次まとめテストも追加生成（YYYY-MM-DD-weekly.md）

set -euo pipefail

# PATHを明示的に設定（launchd環境用）
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY_OF_WEEK=$(date +%w)  # 0=日曜, 1=月曜 ... 6=土曜
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# スクリプト配置場所からリポジトリルートを特定する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_DIR/$YEAR/$MONTH"
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"
WEEKLY_FILE="$OUTPUT_DIR/${TODAY}-weekly.md"

mkdir -p "$OUTPUT_DIR"

if ! command -v claude >/dev/null 2>&1; then
  echo "claude コマンドが見つかりません。PATHを確認してください。"
  exit 1
fi

# Git認証設定（共通）
setup_git_auth() {
  cd "$REPO_DIR"
  GITHUB_TOKEN=$(gh auth token)
  git remote set-url origin "https://oguogu-bit:${GITHUB_TOKEN}@github.com/oguogu-bit/finance-study-journal.git"
}

# ── 1. 日次コンテンツ生成 ───────────────────────────────

if [ -f "$OUTPUT_FILE" ]; then
  echo "[$TODAY] 日次コンテンツは既に存在します: $OUTPUT_FILE"
else
  echo "[$NOW] 日次コンテンツ生成を開始..."

  SKILL_PROMPT=$(cat "$HOME/.claude/commands/finance-study.md")
  claude -p "$SKILL_PROMPT" \
    --output-format text \
    --no-session-persistence \
    > "$OUTPUT_FILE"

  echo "[$NOW] 日次コンテンツ生成完了 → $OUTPUT_FILE"

  setup_git_auth
  cd "$REPO_DIR"

  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "origin リモートが未設定のため、pushをスキップします。"
  else
    git add "$OUTPUT_FILE"
    if git diff --cached --quiet; then
      echo "追加された差分がないため、commit/pushをスキップします。"
    else
      git commit -m "📚 Daily study: $TODAY"
      git push origin main
      echo "[$NOW] 日次コンテンツをGitHubにpushしました"
    fi
  fi
fi

# ── 2. 週次まとめテスト（日曜日のみ）────────────────────

if [ "$DAY_OF_WEEK" = "0" ]; then
  if [ -f "$WEEKLY_FILE" ]; then
    echo "[$TODAY] 週次テストは既に存在します: $WEEKLY_FILE"
  else
    echo "[$NOW] 週次まとめテスト生成を開始..."

    # 一時ファイル（スクリプト終了時に自動削除）
    CONTEXT_FILE=$(mktemp /tmp/finance-weekly-XXXXX.txt)
    trap 'rm -f "$CONTEXT_FILE"' EXIT INT TERM

    # 週次テストスキルの内容 + 今週のファイル内容を結合
    cat "$HOME/.claude/commands/finance-study-weekly.md" > "$CONTEXT_FILE"
    printf '\n\n---\n\n今週の学習ファイル（月〜土）：\n\n' >> "$CONTEXT_FILE"

    FOUND_FILES=0
    for i in 1 2 3 4 5 6; do
      PREV_DATE=$(date -v-${i}d +%Y-%m-%d)
      PREV_YEAR=$(date -v-${i}d +%Y)
      PREV_MONTH=$(date -v-${i}d +%m)
      PREV_FILE="$REPO_DIR/$PREV_YEAR/$PREV_MONTH/$PREV_DATE.md"

      if [ -f "$PREV_FILE" ]; then
        # 月をまたぐ場合の相対パスを計算
        if [ "$PREV_MONTH" = "$MONTH" ]; then
          REL_PATH="${PREV_DATE}.md"
        else
          REL_PATH="../${PREV_MONTH}/${PREV_DATE}.md"
        fi

        printf '=== ファイル: %s (マークダウンリンク: [%s](%s)) ===\n\n' \
          "$PREV_DATE" "${PREV_DATE}.md" "$REL_PATH" >> "$CONTEXT_FILE"
        cat "$PREV_FILE" >> "$CONTEXT_FILE"
        printf '\n\n' >> "$CONTEXT_FILE"
        FOUND_FILES=$((FOUND_FILES + 1))
      fi
    done

    if [ "$FOUND_FILES" -gt 0 ]; then
      claude -p "$(cat "$CONTEXT_FILE")" \
        --output-format text \
        --no-session-persistence \
        > "$WEEKLY_FILE"

      echo "[$NOW] 週次テスト生成完了 → $WEEKLY_FILE（${FOUND_FILES}ファイルを参照）"

      setup_git_auth
      cd "$REPO_DIR"
      git add "$WEEKLY_FILE"
      git commit -m "📝 Weekly test: $TODAY"
      git push origin main
      echo "[$NOW] 週次テストをGitHubにpushしました"
    else
      echo "[$TODAY] 参照できる学習ファイルが見つかりませんでした（週次テストをスキップ）"
    fi
  fi
fi

echo "[$NOW] すべての処理が完了しました"
