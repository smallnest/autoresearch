#!/bin/bash
# Scoring helpers: sentinel detection, score extraction, score threshold check.
#
# Required globals: PASSING_SCORE

# 检测审核输出中的 sentinel 标记
# 三重保护：1) 独特格式 AUTORESEARCH_RESULT:PASS/FAIL 不会巧合出现在普通文本中
# 2) 只检测最后 5 个非空行（trim 后整行精确匹配）
# 3) grep -x 要求整行完全等于 sentinel
# 返回: "pass" 表示检测到 AUTORESEARCH_RESULT:PASS
# "fail" 表示检测到 AUTORESEARCH_RESULT:FAIL
# "none" 表示未检测到 sentinel
check_sentinel() {
    local review_result="$1"
    local last_lines
    last_lines=$(printf '%s' "$review_result" | grep -vE '^\s*$' | tail -5 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if printf '%s' "$last_lines" | grep -qxF 'AUTORESEARCH_RESULT:PASS'; then
        echo "pass"
        return
    fi
    if printf '%s' "$last_lines" | grep -qxF 'AUTORESEARCH_RESULT:FAIL'; then
        echo "fail"
        return
    fi
    echo "none"
}

extract_score() {
    local review_result="$1"
    local score=0
    local score_line

    # 格式1: 明确的百分制 X/100
    score_line=$(echo "$review_result" | grep -Eo '[0-9]+\.?[0-9]*(\s*/\s*100)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 }' 2>/dev/null || echo "0")
        echo "$score"
        return
    fi

    # 格式2: **评分: X/100** 或 **Score: X/100**
    score_line=$(echo "$review_result" | grep -E '\*\*(评分|Score)[^*]*100' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 }' 2>/dev/null || echo "0")
        echo "$score"
        return
    fi

    # 格式3: 总分行
    score_line=$(echo "$review_result" | grep -E '(\*\*)?总分(\*\*)?\s*\|.*\*\*[0-9]' | head -1)
    if [ -z "$score_line" ]; then
        score_line=$(echo "$review_result" | grep -E '总分.*→' | head -1)
    fi
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | tail -1)
        if [ -n "$score" ]; then
            score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 * 10 }' 2>/dev/null || echo "0")
            echo "$score"
            return
        fi
    fi

    # 格式4: X/10
    score_line=$(echo "$review_result" | grep -Eo '[0-9]+\.?[0-9]*(\s*/\s*10)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 * 10 }' 2>/dev/null || echo "0")
            echo "$score"
            return
        fi
    fi

    # 格式5: **评分: X** 或 **Score: X**
    score_line=$(echo "$review_result" | grep -E '\*\*(评分|Score)' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 }' 2>/dev/null || echo "0")
            local num_score="$score"
            if [ "$num_score" = "0" ]; then
                echo "0"
                return
            fi
            if [ "$num_score" -le 10 ] 2>/dev/null; then
                score=$((num_score * 10))
            fi
            echo "$score"
            return
        fi
    fi

    # 格式6: "评分: X" 或 "Score: X"
    score_line=$(echo "$review_result" | grep -E '(评分|Score)\s*:' | grep -v '各维度\|维度' | head -1)
    if [ -n "$score_line" ]; then
        score=$(echo "$score_line" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$score" ]; then
            score=$(printf '%s' "$score" | tr -cd '0-9.' | awk '{ printf "%.0f", 0+$0 }' 2>/dev/null || echo "0")
            local num_score="$score"
            if [ "$num_score" = "0" ]; then
                echo "0"
                return
            fi
            if [ "$num_score" -le 10 ] 2>/dev/null; then
                score=$((num_score * 10))
            fi
            echo "$score"
            return
        fi
    fi

    echo "0"
}

check_score_passed() {
    local score=$1
    local passing=$PASSING_SCORE
    awk -v score="$score" -v passing="$passing" 'BEGIN { exit (score >= passing) ? 0 : 1 }'
}
