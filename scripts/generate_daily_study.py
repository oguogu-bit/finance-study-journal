#!/usr/bin/env python3
"""Generate daily finance study notes for GitHub Actions."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo


THEMES = [
    "家計管理の基本",
    "投資の基礎知識",
    "NISA・iDeCoを活用した節税投資",
    "日本の税金の仕組み",
    "保険の選び方",
    "不動産と住宅ローン",
    "老後のお金",
    "リスク管理と分散投資",
    "経済・マーケットの読み方",
    "資産形成の戦略",
    "株式投資の実践",
    "行動経済学と投資心理",
    "米国株・海外投資",
    "マクロ経済と投資戦略",
    "企業分析の実践",
    "暗号資産・オルタナティブ投資",
    "副業・フリーランスの税務と資産形成",
    "グローバル分散投資",
    "相続・贈与と資産承継",
    "FIREと資産取り崩し戦略",
]

DAILY_REQUIRED_HEADINGS = [
    "## 📅 今日の学習テーマ",
    "## 解説",
    "## キーポイント",
    "## 実践例",
    "## アクションアイテム",
    "## クイズ",
    "## 次のステップ",
    "## 注意書き",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", help="Target date in YYYY-MM-DD. Defaults to today in Asia/Tokyo.")
    parser.add_argument("--repo", default=".", help="Repository root.")
    return parser.parse_args()


def target_date(value: str | None) -> dt.date:
    if value:
        return dt.date.fromisoformat(value)
    return dt.datetime.now(ZoneInfo("Asia/Tokyo")).date()


def theme_for(date: dt.date) -> tuple[int, int, str]:
    day_of_year = int(date.strftime("%j"))
    theme_num = (day_of_year - 1) % len(THEMES) + 1
    subtopic_idx = (day_of_year - 1) // len(THEMES) + 1
    return theme_num, subtopic_idx, THEMES[theme_num - 1]


def read_recent_performance(repo: Path, year: int) -> str:
    perf_file = repo / str(year) / "performance-log.md"
    if not perf_file.exists():
        return ""

    rows = [
        line
        for line in perf_file.read_text(encoding="utf-8").splitlines()
        if line.startswith("|") and "日付" not in line and "---" not in line
    ][-7:]
    if not rows:
        return ""

    return "\n".join(
        [
            "【直近パフォーマンスデータ】",
            "以下の最近のクイズ結果を参考に、苦手分野は少し丁寧に説明してください。",
            *rows,
        ]
    )


def openai_response(prompt: str) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set.")

    model = os.environ.get("OPENAI_MODEL", "gpt-5-mini")
    payload = {
        "model": model,
        "input": prompt,
        "instructions": (
            "You are a Japanese personal finance education content generator. "
            "Output only Markdown. Do not provide investment advice. "
            "Avoid definitive claims about tax, pension, insurance, or legal rules without a date note."
        ),
        "text": {"format": {"type": "text"}, "verbosity": "medium"},
        "max_output_tokens": 5000,
        "store": False,
    }

    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI API request failed: {exc.code} {body}") from exc

    text = data.get("output_text")
    if text:
        return text.strip()

    chunks: list[str] = []
    for item in data.get("output", []):
        if item.get("type") == "message":
            for content in item.get("content", []):
                if content.get("type") == "output_text":
                    chunks.append(content.get("text", ""))
    result = "".join(chunks).strip()
    if not result:
        raise RuntimeError("OpenAI API returned no text output.")
    return result


def build_daily_prompt(date: dt.date, performance: str) -> str:
    theme_num, subtopic_idx, theme_name = theme_for(date)
    return f"""次の日付の初心者向け金融リテラシー学習ノートをMarkdownで作成してください。

【指定情報】
- 日付: {date.isoformat()}
- 年の通算日数: {int(date.strftime('%j'))}日目
- テーマ番号: テーマ{theme_num}「{theme_name}」
- サブトピック番号: 第{subtopic_idx}回目
- 対象読者: 日本在住の金融初心者
- 目的: 今後の家計改善に役立つ知識を毎日少しずつ身につける

{performance}

【必須ルール】
- 先頭は必ず「## 📅 今日の学習テーマ」で開始する
- 必ず次の見出しをこの順番で含める:
  - ## 📅 今日の学習テーマ
  - ## 解説
  - ## キーポイント
  - ## 実践例
  - ## アクションアイテム
  - ## クイズ
  - ## 次のステップ
  - ## 注意書き
- 毎日違う切り口にする
- 初心者にわかる言葉を使う
- 実践例は日本の家計に寄せる
- アクションアイテムは今日10分以内にできる内容にする
- クイズは3問、各問に答えと短い解説をつける
- 投資助言ではなく教育目的として書く
- 税制、年金、制度、給付、控除、保険条件に触れる場合は「{date.isoformat()}時点」の注記を入れる
- 個別銘柄の売買推奨はしない
"""


def build_weekly_prompt(date: dt.date, repo: Path) -> str:
    output_lines = [
        f"{date.isoformat()} の週次まとめテストをMarkdownで作成してください。",
        "",
        "【必須ルール】",
        "- 先頭は必ず「## 📋 週次まとめテスト」で開始する",
        "- 今週の重要ポイント",
        "- 10問テスト",
        "- 答えと解説",
        "- 苦手分野の復習",
        "- 来週の学習方針",
        "- 注意書き",
        "",
        "【今週の学習ファイル】",
    ]

    found = 0
    for offset in range(1, 7):
        prev = date - dt.timedelta(days=offset)
        path = repo / f"{prev:%Y}" / f"{prev:%m}" / f"{prev:%Y-%m-%d}.md"
        if path.exists():
            found += 1
            output_lines.extend(
                [
                    f"",
                    f"=== {prev.isoformat()} ===",
                    path.read_text(encoding="utf-8")[:6000],
                ]
            )

    if found == 0:
        raise RuntimeError("No daily files found for weekly summary.")
    return "\n".join(output_lines)


def validate_daily(markdown: str) -> None:
    if not markdown.startswith("## 📅 今日の学習テーマ"):
        raise RuntimeError("Daily note must start with ## 📅 今日の学習テーマ.")
    missing = [heading for heading in DAILY_REQUIRED_HEADINGS if heading not in markdown]
    if missing:
        raise RuntimeError(f"Daily note is missing headings: {', '.join(missing)}")


def write_text(path: Path, text: str) -> bool:
    if path.exists():
        print(f"Skip existing file: {path}")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")
    print(f"Wrote {path}")
    return True


def extract_daily_title(markdown: str, fallback: str) -> str:
    for line in markdown.splitlines():
        if "今日の学習テーマ" in line:
            title = re.sub(r"^#+\s*📅?\s*今日の学習テーマ[:：]?\s*", "", line).strip()
            if title:
                return title
    return fallback


def append_readme(repo: Path, date: dt.date, title: str, weekly: bool = False) -> None:
    readme = repo / "README.md"
    if not readme.exists():
        return

    rel = f"{date:%Y}/{date:%m}/{date:%Y-%m-%d}{'-weekly' if weekly else ''}.md"
    if weekly:
        row = f"| [{date.isoformat()} 週次テスト]({rel}) | 📋 週次まとめテスト |"
    else:
        row = f"| [{date.isoformat()}]({rel}) | {title} |"

    content = readme.read_text(encoding="utf-8")
    if row not in content:
        readme.write_text(content.rstrip() + "\n" + row + "\n", encoding="utf-8")
        print(f"Updated {readme}")


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()
    date = target_date(args.date)
    out_dir = repo / f"{date:%Y}" / f"{date:%m}"
    daily_file = out_dir / f"{date:%Y-%m-%d}.md"
    weekly_file = out_dir / f"{date:%Y-%m-%d}-weekly.md"

    wrote_any = False
    if not daily_file.exists():
        performance = read_recent_performance(repo, date.year)
        daily = openai_response(build_daily_prompt(date, performance))
        validate_daily(daily)
        wrote_any |= write_text(daily_file, daily)
        append_readme(repo, date, extract_daily_title(daily, theme_for(date)[2]))

    if date.weekday() == 6 and not weekly_file.exists():
        weekly = openai_response(build_weekly_prompt(date, repo))
        if not weekly.startswith("## 📋 週次まとめテスト"):
            raise RuntimeError("Weekly test must start with ## 📋 週次まとめテスト.")
        wrote_any |= write_text(weekly_file, weekly)
        append_readme(repo, date, "週次まとめテスト", weekly=True)

    if not wrote_any:
        print("No files changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
