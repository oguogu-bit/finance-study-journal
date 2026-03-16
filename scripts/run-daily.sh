#!/bin/bash
# 金融リテラシー毎日学習 — 自動生成スクリプト
# 毎朝6時にlaunchdから実行される
# 日曜日は週次まとめテストも追加生成（YYYY-MM-DD-weekly.md）

set -euo pipefail

# PATHを明示的に設定（launchd環境用）
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# launchd環境ではUSER/LOGNAMEが未設定の場合があるので補完
export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-$USER}"
export HOME="${HOME:-/Users/$USER}"

# DATE_OVERRIDE が指定された場合はそちらを使用（バックフィル用）
if [ -n "${DATE_OVERRIDE:-}" ]; then
  TODAY="$DATE_OVERRIDE"
  YEAR="${TODAY:0:4}"
  MONTH="${TODAY:5:2}"
  DAY_OF_WEEK=$(date -j -f "%Y-%m-%d" "$TODAY" +%w 2>/dev/null || date +%w)
else
  TODAY=$(date +%Y-%m-%d)
  YEAR=$(date +%Y)
  MONTH=$(date +%m)
  DAY_OF_WEEK=$(date +%w)  # 0=日曜, 1=月曜 ... 6=土曜
fi
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# テーマ番号をスクリプト側で計算（1〜20のローテーション）
# macOS: date -j -f で任意の日付の通算日数を取得
DAY_OF_YEAR=$(date -j -f "%Y-%m-%d" "$TODAY" +%j 2>/dev/null | sed 's/^0*//' || date +%-j)
THEME_MOD=$((DAY_OF_YEAR % 20))
THEME_NUM=$((THEME_MOD == 0 ? 20 : THEME_MOD))
THEME_NAMES=("" "家計管理の基本" "投資の基礎知識" "NISA・iDeCoを活用した節税投資" "日本の税金の仕組み" "保険の選び方" "不動産と住宅ローン" "老後のお金" "リスク管理と分散投資" "経済・マーケットの読み方" "資産形成の戦略" "株式投資の実践" "行動経済学と投資心理" "米国株・海外投資" "マクロ経済と投資戦略" "企業分析の実践" "暗号資産・オルタナティブ投資" "副業・フリーランスの税務と資産形成" "グローバル分散投資" "相続・贈与と資産承継" "FIREと資産取り崩し戦略")
THEME_NAME="${THEME_NAMES[$THEME_NUM]}"

# スクリプト配置場所からリポジトリルートを特定する
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_DIR/$YEAR/$MONTH"
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"
WEEKLY_FILE="$OUTPUT_DIR/${TODAY}-weekly.md"
LOG_DIR="$REPO_DIR/logs"

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

# エラー発生時にログを記録する trap
trap 'echo "[ERROR $(date +%Y-%m-%d\ %H:%M:%S)] スクリプトがライン $LINENO で失敗 (exit $?)" >> "$LOG_DIR/error.log"' ERR

echo "[$NOW] 起動確認 USER=$USER HOME=$HOME THEME=${THEME_NUM}「${THEME_NAME}」"

if ! command -v claude >/dev/null 2>&1; then
  echo "claude コマンドが見つかりません。PATHを確認してください。"
  exit 1
fi

# Git認証設定（共通）
setup_git_auth() {
  cd "$REPO_DIR"
  GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  if [ -n "$GITHUB_TOKEN" ]; then
    git remote set-url origin "https://oguogu-bit:${GITHUB_TOKEN}@github.com/oguogu-bit/finance-study-journal.git"
  fi
}

# Claude呼び出し用システムプロンプト（ツール使用を禁止し、テキスト直接出力させる）
CLAUDE_SYSTEM="You are a markdown content generator. Output the requested content directly as markdown text. Do NOT use any tools, do NOT write files, do NOT ask for permissions. Just output the markdown text directly to stdout."

# Claude呼び出し（リトライあり）
# 引数: $1=出力ファイル, $2=プロンプト文字列
run_claude_with_retry() {
  local out_file="$1"
  local prompt="$2"
  local max_attempts=3
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    echo "[$NOW] Claude呼び出し (試行 ${attempt}/${max_attempts})..." >> "$LOG_DIR/daily.log" 2>&1 || true
    local tmp_out="${out_file}.tmp"
    local tmp_err=$(mktemp /tmp/claude-err-XXXXX.txt)

    if claude -p "$prompt" \
        --output-format text \
        --no-session-persistence \
        --system-prompt "$CLAUDE_SYSTEM" \
        > "$tmp_out" 2>"$tmp_err"; then

      # 出力が空でないか確認
      if [ -s "$tmp_out" ]; then
        mv "$tmp_out" "$out_file"
        rm -f "$tmp_err"
        return 0
      else
        echo "[ERROR $(date +%Y-%m-%d\ %H:%M:%S)] 試行${attempt}: claudeの出力が空でした" >> "$LOG_DIR/error.log"
      fi
    else
      local exit_code=$?
      echo "[ERROR $(date +%Y-%m-%d\ %H:%M:%S)] 試行${attempt}: claude失敗 (exit ${exit_code})" >> "$LOG_DIR/error.log"
      if [ -s "$tmp_err" ]; then
        echo "--- claude stderr ---" >> "$LOG_DIR/error.log"
        cat "$tmp_err" >> "$LOG_DIR/error.log"
        echo "--- end stderr ---" >> "$LOG_DIR/error.log"
      fi
    fi

    rm -f "$tmp_out" "$tmp_err"
    attempt=$((attempt + 1))

    if [ $attempt -le $max_attempts ]; then
      echo "[RETRY $(date +%Y-%m-%d\ %H:%M:%S)] $((attempt-1))回目失敗、30秒後にリトライします..." >> "$LOG_DIR/error.log"
      sleep 30
    fi
  done

  return 1
}

# ── 1. 日次コンテンツ生成 ───────────────────────────────

if [ -f "$OUTPUT_FILE" ]; then
  echo "[$TODAY] 日次コンテンツは既に存在します: $OUTPUT_FILE"
else
  echo "[$NOW] 日次コンテンツ生成を開始... (テーマ${THEME_NUM}「${THEME_NAME}」)"

  SKILL_CONTENT=$(cat "$HOME/.claude/commands/finance-study.md")
  SKILL_PROMPT="【本日の指定情報】
- 今日の日付：$TODAY
- 使用するテーマ番号：テーマ${THEME_NUM}「${THEME_NAME}」
- ※ 上記テーマを必ず使用してください。他のテーマは選ばないでください。

$SKILL_CONTENT"

  if ! run_claude_with_retry "$OUTPUT_FILE" "$SKILL_PROMPT"; then
    echo "[ERROR $NOW] $TODAY の生成が3回全て失敗しました。明日再試行されます。" >> "$LOG_DIR/error.log"
    rm -f "$OUTPUT_FILE"
    exit 1
  fi

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
      git pull --rebase origin main 2>>"$LOG_DIR/error.log" || true
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
    trap 'rm -f "$CONTEXT_FILE"; echo "[ERROR $(date +%Y-%m-%d\ %H:%M:%S)] スクリプトがライン $LINENO で失敗 (exit $?)" >> "$LOG_DIR/error.log"' ERR
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
      if ! run_claude_with_retry "$WEEKLY_FILE" "$(cat "$CONTEXT_FILE")"; then
        echo "[ERROR $NOW] 週次テスト生成が全て失敗しました" >> "$LOG_DIR/error.log"
        rm -f "$WEEKLY_FILE"
        exit 1
      fi

      echo "[$NOW] 週次テスト生成完了 → $WEEKLY_FILE（${FOUND_FILES}ファイルを参照）"

      setup_git_auth
      cd "$REPO_DIR"
      git add "$WEEKLY_FILE"
      git commit -m "📝 Weekly test: $TODAY"
      git pull --rebase origin main 2>>"$LOG_DIR/error.log" || true
      git push origin main
      echo "[$NOW] 週次テストをGitHubにpushしました"
    else
      echo "[$TODAY] 参照できる学習ファイルが見つかりませんでした（週次テストをスキップ）"
    fi
  fi
fi

echo "[$NOW] すべての処理が完了しました"
