# 金融リテラシー学習 — 毎日6時自動実行 & GitHub保存

## Context
- `/finance-study` スキルを毎朝6時に自動実行
- 生成されたコンテンツをMarkdownとしてGitHubリポジトリに保存
- macOS launchdでスケジューリング、SSH認証でpush
- `gh` CLIをインストールしてリポジトリを自動作成

---

## 環境情報（調査済み）
- Claude CLI: `/opt/homebrew/bin/claude` (v2.1.39)
- Git: インストール済み (v2.50.1)
- GitHub CLI (`gh`): 未インストール → Homebrewで導入
- 認証: SSH
- LaunchAgents / crontab: 未設定

---

## 実装ステップ

### Step 1: GitHub CLIのインストールと認証
```bash
brew install gh
gh auth login   # SSH を選択
```

### Step 2: SSHキーの確認・作成
```bash
ls ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "kosei.realmadrid@gmail.com"
# gh auth login 時にキーをGitHubに自動登録
```

### Step 3: ローカルリポジトリとGitHubリポジトリの作成
```bash
mkdir -p ~/finance-study/scripts ~/finance-study/logs
cd ~/finance-study
git init
git branch -M main
gh repo create finance-study-journal \
  --public \
  --description "📚 毎日の金融リテラシー学習ノート" \
  --source=. \
  --remote=origin \
  --push
```

### Step 4: リポジトリのファイル構成
```
~/finance-study/
├── README.md          ← 自動生成
├── .gitignore
├── scripts/
│   └── run-daily.sh  ← 実行スクリプト
├── logs/
│   ├── daily.log
│   └── error.log
└── 2026/
    └── 02/
        └── 2026-02-20.md  ← 毎日追加
```

### Step 5: 実行スクリプト作成
`~/finance-study/scripts/run-daily.sh`

```bash
#!/bin/bash
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)

REPO_DIR="$HOME/finance-study"
OUTPUT_DIR="$REPO_DIR/$YEAR/$MONTH"
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# 出力先ディレクトリ作成
mkdir -p "$OUTPUT_DIR"

echo "[$TODAY 06:00] コンテンツ生成開始"

# Claude CLIでfinance-studyスキルを実行
claude -p "/finance-study" \
  --output-format text \
  --no-session-persistence \
  > "$OUTPUT_FILE"

echo "[$TODAY 06:00] 生成完了 → $OUTPUT_FILE"

# GitHubにpush
cd "$REPO_DIR"
git add .
git commit -m "📚 Daily study: $TODAY"
git push origin main

echo "[$TODAY 06:00] GitHubへのpush完了"
```

### Step 6: launchd plistファイル作成
`~/Library/LaunchAgents/com.ogu.finance-study.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ogu.finance-study</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/ogu/finance-study/scripts/run-daily.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>6</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>/Users/ogu/finance-study/logs/daily.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/ogu/finance-study/logs/error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>/Users/ogu</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>SSH_AUTH_SOCK</key>
    <string>/private/tmp/com.apple.launchd.$(id -u)/Listeners</string>
  </dict>
</dict>
</plist>
```

### Step 7: launchdに登録・有効化
```bash
launchctl load ~/Library/LaunchAgents/com.ogu.finance-study.plist
```

### Step 8: README.md作成
初回コミット用のREADMEを作成してリポジトリをセットアップ

---

## 検証方法

```bash
# 手動テスト実行（すぐに動作確認できる）
bash ~/finance-study/scripts/run-daily.sh

# launchdの登録確認
launchctl list | grep finance-study

# ログ確認
tail -f ~/finance-study/logs/daily.log

# GitHubで確認
open https://github.com/$(gh api user --jq .login)/finance-study-journal
```

---

## 作成するファイル一覧
1. `~/finance-study/scripts/run-daily.sh`
2. `~/finance-study/README.md`
3. `~/finance-study/.gitignore`
4. `~/Library/LaunchAgents/com.ogu.finance-study.plist`

---

## 注意点
- launchd実行時のSSH認証: macOSのKeychain経由で自動解決
- `claude -p "/finance-study"` はスキルを呼び出してコンテンツを生成
- 毎日異なるテーマが自動選択される（日付ベースのローテーション）
