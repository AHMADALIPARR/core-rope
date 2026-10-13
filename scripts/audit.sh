#!/bin/sh
# Count source lines.
# A line counts as substantive when it is not blank and not a comment-only line.
# BASIC comments start with a quote or REM after whitespace.
# Assembly comments start with a semicolon after whitespace.
# This count is not a proof that the program is finished.
set -eu
cd "$(dirname "$0")/.."
count_lang() {
    lang=$1
    shift
    files=$(find "$@" -type f | sort)
    physical=0
    substantive=0
    for f in $files; do
        while IFS= read -r line || [ -n "$line" ]; do
            physical=$((physical + 1))
            trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
            if [ -z "$trimmed" ]; then
                continue
            fi
            case $lang in
                basic)
                    first=$(printf '%s' "$trimmed" | cut -c1)
                    if [ "$first" = "'" ]; then
                        continue
                    fi
                    word=$(printf '%s' "$trimmed" | cut -d' ' -f1 | tr '[:lower:]' '[:upper:]')
                    if [ "$word" = "REM" ]; then
                        continue
                    fi
                    ;;
                asm)
                    first=$(printf '%s' "$trimmed" | cut -c1)
                    if [ "$first" = ";" ]; then
                        continue
                    fi
                    ;;
            esac
            substantive=$((substantive + 1))
        done < "$f"
    done
    echo "$lang physical=$physical substantive=$substantive"
}
count_lang basic basic
count_lang asm asm
