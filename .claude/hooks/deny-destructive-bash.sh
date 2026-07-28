#!/usr/bin/env bash
# PreToolUse guard for the Bash tool: denies destructive/irreversible commands
# (delete, move, force-push, hard reset, etc.) even when hidden inside a
# chained command (e.g. "git add . && git reset --hard").

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ -z "$cmd" ] && exit 0

blocked_names="rm rmdir shred dd mv truncate"

check_segment() {
  seg="$1"
  seg="$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$seg" ] && return 1

  seg="$(printf '%s' "$seg" | sed -E 's/^sudo[[:space:]]+//')"
  while printf '%s' "$seg" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]'; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//')"
  done

  first_word="$(printf '%s' "$seg" | awk '{print $1}')"

  for name in $blocked_names; do
    if [ "$first_word" = "$name" ]; then
      printf '%s' "$first_word"
      return 0
    fi
  done

  if printf '%s' "$seg" | grep -qE '^find\b.*(-delete\b|-exec[[:space:]]+rm\b)'; then
    printf '%s' "find (-delete / -exec rm)"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+reset\b.*--hard\b'; then
    printf '%s' "git reset --hard"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+push\b.*[[:space:]](-f|--force)([[:space:]]|$)'; then
    printf '%s' "git push --force"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+push[[:space:]].*[[:space:]]\+[^[:space:]]'; then
    printf '%s' "git push +branch (force via refspec)"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+clean\b'; then
    printf '%s' "git clean"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+checkout[[:space:]]+(--([[:space:]]|$)|\.([[:space:]]|$))'; then
    printf '%s' "git checkout -- / git checkout ."; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+restore\b'; then
    printf '%s' "git restore"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+branch[[:space:]]+(-D|--delete[[:space:]]+--force)\b'; then
    printf '%s' "git branch -D"; return 0
  fi
  if printf '%s' "$seg" | grep -qE '^git[[:space:]]+filter-branch\b'; then
    printf '%s' "git filter-branch"; return 0
  fi

  return 1
}

offending=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if result="$(check_segment "$line")"; then
    offending="$result"
    break
  fi
done < <(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')

if [ -n "$offending" ]; then
  reason="プロジェクトのポリシーにより、破壊的で元に戻せないコマンド「${offending}」の実行は許可されていません。"
  jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
fi

exit 0
