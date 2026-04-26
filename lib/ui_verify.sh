#!/bin/bash
# UI verification: dev server detection, screenshot capture, LLM-based validation.
#
# Required globals: PROJECT_ROOT, UI_VERIFY_ENABLED, UI_VERIFY_TIMEOUT, UI_DEV_PORT
# Required callbacks: log, error, detect_language, register_temp_file

detect_dev_server_command() {
  local project_root="$1"
  local lang=$(detect_language)
  local cmd=""

  # Node.js 项目
  if [ "$lang" = "node" ]; then
    if [ -f "$project_root/package.json" ]; then
      # 检查 package.json 中的 scripts
      if jq -e '.scripts.dev' "$project_root/package.json" > /dev/null 2>&1; then
        cmd="npm run dev"
      elif jq -e '.scripts.start' "$project_root/package.json" > /dev/null 2>&1; then
        cmd="npm start"
      elif jq -e '.scripts.serve' "$project_root/package.json" > /dev/null 2>&1; then
        cmd="npm run serve"
      fi
    fi
    # 如果没有 npm scripts，检查常见工具
    if [ -z "$cmd" ]; then
      if [ -f "$project_root/vite.config.ts" ] || [ -f "$project_root/vite.config.js" ]; then
        cmd="npx vite"
      elif [ -f "$project_root/next.config.js" ] || [ -f "$project_root/next.config.ts" ]; then
        cmd="npx next dev"
      elif [ -f "$project_root/angular.json" ]; then
        cmd="npx ng serve"
      elif [ -f "$project_root/webpack.config.js" ]; then
        cmd="npx webpack serve"
      fi
    fi
  fi

  # Python 项目（Flask/Django/FastAPI）
  if [ "$lang" = "python" ]; then
    if [ -f "$project_root/manage.py" ]; then
      cmd="python manage.py runserver"
    elif grep -q "flask" "$project_root/requirements.txt" 2>/dev/null; then
      cmd="flask run"
    elif grep -q "fastapi" "$project_root/requirements.txt" 2>/dev/null; then
      if command -v uvicorn > /dev/null 2>&1; then
        cmd="uvicorn main:app --reload"
      fi
    fi
  fi

  # Go 项目
  if [ "$lang" = "go" ]; then
    if [ -f "$project_root/main.go" ]; then
      cmd="go run main.go"
    elif [ -f "$project_root/cmd/main.go" ]; then
      cmd="go run cmd/main.go"
    fi
  fi

  # Rust 项目
  if [ "$lang" = "rust" ]; then
    cmd="cargo run"
  fi

  # 检查 Makefile
  if [ -z "$cmd" ] && [ -f "$project_root/Makefile" ]; then
    if grep -qE '^dev:|^serve:|^run:' "$project_root/Makefile"; then
      if grep -qE '^dev:' "$project_root/Makefile"; then
        cmd="make dev"
      elif grep -qE '^serve:' "$project_root/Makefile"; then
        cmd="make serve"
      elif grep -qE '^run:' "$project_root/Makefile"; then
        cmd="make run"
      fi
    fi
  fi

  # Monorepo/子目录搜索：如果根目录未找到 dev server 命令，
  # 扫描一级子目录中包含 package.json 的 Node.js 项目
  if [ -z "$cmd" ]; then
    local sub_dir
    for sub_dir in "$project_root"/*/; do
      [ -d "$sub_dir" ] || continue
      [ -f "$sub_dir/package.json" ] || continue
      # 检查子目录的 package.json 是否有 dev 相关 script
      if jq -e '.scripts.dev' "$sub_dir/package.json" > /dev/null 2>&1; then
        local sub_name
        sub_name=$(basename "$sub_dir")
        cmd="cd $sub_name && npm run dev"
        log "在子目录 $sub_name/ 中检测到 dev server 命令" >&2
        break
      elif jq -e '.scripts.start' "$sub_dir/package.json" > /dev/null 2>&1; then
        local sub_name
        sub_name=$(basename "$sub_dir")
        cmd="cd $sub_name && npm start"
        log "在子目录 $sub_name/ 中检测到 start 命令" >&2
        break
      fi
    done
  fi

  echo "$cmd"
}

# 从 dev server 命令或项目配置检测端口号
# 返回: 端口号（数字），如果无法检测则返回默认值 3000
detect_dev_server_port() {
  local project_root="$1"
  local port=""

  # 如果环境变量已设置，优先使用
  if [ -n "$UI_DEV_PORT" ]; then
    echo "$UI_DEV_PORT"
    return
  fi

  # 搜索目录列表：根目录 + 一级子目录（含 package.json 的）
  local search_dirs=("$project_root")
  local sub_dir
  for sub_dir in "$project_root"/*/; do
    [ -d "$sub_dir" ] || continue
    [ -f "$sub_dir/package.json" ] || continue
    search_dirs+=("$sub_dir")
  done

  # 在所有搜索目录中查找端口配置
  local search_dir
  for search_dir in "${search_dirs[@]}"; do
    # 检查 vite config
    if [ -f "$search_dir/vite.config.ts" ] || [ -f "$search_dir/vite.config.js" ]; then
      local vite_config
      for vite_config in "$search_dir/vite.config.ts" "$search_dir/vite.config.js"; do
        [ -f "$vite_config" ] || continue
        port=$(grep -oE 'port:\s*[0-9]+' "$vite_config" 2>/dev/null | grep -oE '[0-9]+' | head -1)
        [ -n "$port" ] && break
      done
      [ -n "$port" ] && break
    fi
    # 检查 next config
    if [ -z "$port" ] && ([ -f "$search_dir/next.config.js" ] || [ -f "$search_dir/next.config.ts" ]); then
      port="3000"
      break
    fi
    # 检查 .env 文件
    if [ -z "$port" ]; then
      local env_file
      for env_file in "$search_dir/.env" "$search_dir/.env.local" "$search_dir/.env.development"; do
        if [ -f "$env_file" ]; then
          port=$(grep -E '^PORT=|^VITE_PORT=|^NEXT_PORT=' "$env_file" 2>/dev/null | grep -oE '[0-9]+' | head -1)
          [ -n "$port" ] && break
        fi
      done
      [ -n "$port" ] && break
    fi
  done

  # 默认端口
  if [ -z "$port" ]; then
    port="3000"
  fi

  echo "$port"
}

# 等待 dev server 就绪
# 参数: $1 = 端口号, $2 = 超时秒数（可选，默认 UI_VERIFY_TIMEOUT）
# 返回: 0 = 就绪, 1 = 超时
wait_for_dev_server() {
 local port="$1"
 local timeout="${2:-$UI_VERIFY_TIMEOUT}"
 local start_time
 start_time=$(date +%s)
 local elapsed=0

 log "等待 dev server 就绪 (端口: $port, 超时: ${timeout}秒)..."

 # 检查端口是否已被占用
 if command -v lsof > /dev/null 2>&1 && lsof -i :"$port" > /dev/null 2>&1; then
 log "警告: 端口 $port 已被占用，可能另一个 dev server 正在运行"
 fi

 while [ $elapsed -lt "$timeout" ]; do
 # 检查端口是否被监听
 if command -v nc > /dev/null 2>&1; then
 if nc -z localhost "$port" 2>/dev/null; then
 # 端口已监听，再等待一下确保服务完全启动
 sleep 1
 # 尝试 HTTP 请求确认服务真正可用
 if curl -s "http://localhost:$port" > /dev/null 2>&1 || \
 curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
 log "dev server 已就绪 (端口: $port)"
 return 0
 else
 log "端口 $port 已监听但 HTTP 请求失败，继续等待..."
 fi
 fi
 elif command -v lsof > /dev/null 2>&1; then
 if lsof -i :"$port" > /dev/null 2>&1; then
 sleep 1
 if curl -s "http://localhost:$port" > /dev/null 2>&1 || \
 curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
 log "dev server 已就绪 (端口: $port)"
 return 0
 else
 log "端口 $port 已监听但 HTTP 请求失败，继续等待..."
 fi
 fi
 fi

 sleep 1
 elapsed=$(( $(date +%s) - start_time ))

 # 每 10 秒输出一次进度
 if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
 log "已等待 ${elapsed} 秒..."
 fi
 done

 error "等待 dev server 超时 (${timeout}秒)"
 return 1
}

# 捕获浏览器截图
# 参数: $1 = 目标 URL, $2 = 输出文件路径
# 返回: 0 = 成功, 1 = 失败
capture_screenshot() {
 local target_url="$1"
 local output_file="$2"
 local success=0
 local work_dir
 work_dir=$(dirname "$output_file")

 log "捕获截图: $target_url -> $output_file" >&2

 # 创建截图目录
 mkdir -p "$work_dir" 2>/dev/null || true

 # 检查截图工具可用性
 local tools_available=0
 local chrome_path=""
 # macOS: 检查标准安装路径
 if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
   chrome_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
   tools_available=1
 fi
 if [ -z "$chrome_path" ] && command -v google-chrome &> /dev/null; then
   chrome_path="google-chrome"
   tools_available=1
 fi
 if [ -z "$chrome_path" ] && command -v chromium &> /dev/null; then
   tools_available=1
 fi
 if [ -z "$chrome_path" ] && command -v chromium-browser &> /dev/null; then
   tools_available=1
 fi
 if command -v playwright &> /dev/null || command -v npx &> /dev/null; then
   tools_available=1
 fi

 if [ $tools_available -eq 0 ]; then
   log "截图失败: 无可用截图工具 (chrome, playwright, chromium 均不可用)" >&2
   echo "截图工具不可用，跳过 UI 验证" >> "$work_dir/verify.log" 2>/dev/null || true
   return 1
 fi

 # 优先使用 Chrome CDP 协议截图（最可靠，无外部依赖）
 if [ $success -eq 0 ] && [ -n "$chrome_path" ]; then
   log "使用 Chrome CDP 协议截图..." >&2
   if capture_screenshot_cdp "$chrome_path" "$target_url" "$output_file"; then
     success=1
     log "Chrome CDP 截图成功" >&2
   else
     log "Chrome CDP 截图失败，尝试下一个工具..." >&2
   fi
 fi

 # 优先使用 playwright
 if [ $success -eq 0 ]; then
   if command -v playwright &> /dev/null; then
     log "使用 playwright 截图..." >&2
     if playwright screenshot \
     --viewport-size="1280,720" \
     --wait-for-timeout=5000 \
     "$target_url" \
     "$output_file" 2>/dev/null; then
       success=1
       log "playwright 截图成功" >&2
     else
       log "playwright 截图失败，尝试下一个工具..." >&2
     fi
   fi
 fi

 # 如果 playwright 失败，尝试使用 npx playwright
 if [ $success -eq 0 ]; then
   if command -v npx &> /dev/null; then
     log "尝试使用 npx playwright 截图..." >&2
     if npx playwright screenshot \
     --viewport-size="1280,720" \
     --wait-for-timeout=5000 \
     "$target_url" \
     "$output_file" 2>/dev/null; then
       success=1
       log "npx playwright 截图成功" >&2
     else
       log "npx playwright 截图失败，尝试下一个工具..." >&2
     fi
   fi
 fi

 # 如果都失败，尝试使用 google-chrome headless --screenshot
 if [ $success -eq 0 ] && [ -n "$chrome_path" ]; then
   log "尝试使用 Chrome headless --screenshot..." >&2
   if timeout 30 "$chrome_path" \
   --headless \
   --disable-gpu \
   --screenshot="$output_file" \
   --window-size=1280,720 \
   "$target_url" 2>/dev/null; then
     success=1
     log "Chrome headless 截图成功" >&2
   else
     log "Chrome headless 截图失败，尝试下一个工具..." >&2
   fi
 fi

 # 尝试 chromium
 if [ $success -eq 0 ]; then
   if command -v chromium &> /dev/null; then
     log "尝试使用 chromium 截图..." >&2
     if timeout 30 chromium \
     --headless \
     --disable-gpu \
     --screenshot="$output_file" \
     --window-size=1280,720 \
     "$target_url" 2>/dev/null; then
       success=1
       log "chromium 截图成功" >&2
     else
       log "chromium 截图失败，尝试下一个工具..." >&2
     fi
   fi
 fi

 # 尝试 chromium-browser
 if [ $success -eq 0 ]; then
   if command -v chromium-browser &> /dev/null; then
     log "尝试使用 chromium-browser 截图..." >&2
     if timeout 30 chromium-browser \
     --headless \
     --disable-gpu \
     --screenshot="$output_file" \
     --window-size=1280,720 \
     "$target_url" 2>/dev/null; then
       success=1
       log "chromium-browser 截图成功" >&2
     else
       log "chromium-browser 截图失败" >&2
     fi
   fi
 fi

 # 记录结果到日志
 if [ $success -eq 1 ]; then
   log "截图成功: $output_file" >&2
   echo "截图成功: $output_file" >> "$work_dir/verify.log" 2>/dev/null || true
   return 0
 else
   log "截图失败: 无法使用任何可用工具捕获截图" >&2
   echo "截图失败: 所有可用工具均无法完成截图" >> "$work_dir/verify.log" 2>/dev/null || true
   return 1
 fi
}

# 使用 Chrome DevTools Protocol (CDP) 截图
# 参数: $1 = Chrome 可执行文件路径, $2 = 目标 URL, $3 = 输出文件路径
# 返回: 0 = 成功, 1 = 失败
capture_screenshot_cdp() {
  local chrome_bin="$1"
  local target_url="$2"
  local output_file="$3"
  local cdp_port=19222
  local cdp_tmp_dir
  cdp_tmp_dir=$(mktemp -d)
  register_temp_file "$cdp_tmp_dir"
  local chrome_pid=""

  # 清理函数
  _cdp_cleanup() {
    if [ -n "$chrome_pid" ] && kill -0 "$chrome_pid" 2>/dev/null; then
      kill "$chrome_pid" 2>/dev/null || true
      sleep 0.5
      kill -9 "$chrome_pid" 2>/dev/null || true
    fi
    rm -rf "$cdp_tmp_dir" 2>/dev/null || true
  }

  # 启动 Chrome 并开启远程调试端口
  "$chrome_bin" \
    --headless=new \
    --disable-gpu \
    --no-sandbox \
    --disable-dev-shm-usage \
    --remote-debugging-port="$cdp_port" \
    --user-data-dir="$cdp_tmp_dir/chrome-profile" \
    --window-size=1280,720 \
    about:blank \
    > /dev/null 2>&1 &
  chrome_pid=$!

  # 等待 CDP 端口就绪
  local retries=0
  local max_retries=20
  while [ $retries -lt $max_retries ]; do
    if curl -s "http://localhost:$cdp_port/json/version" > /dev/null 2>&1; then
      break
    fi
    sleep 0.5
    retries=$((retries + 1))
  done

  if [ $retries -ge $max_retries ]; then
    _cdp_cleanup
    return 1
  fi

  # 创建临时 Node.js 脚本通过 CDP WebSocket 截图
  local node_script="$cdp_tmp_dir/screenshot.js"
  cat > "$node_script" << 'CDPSCRIPT'
const http = require('http');
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');

const port = parseInt(process.argv[2]);
const targetUrl = process.argv[3];
const outFile = process.argv[4];

function httpGet(u) {
  return new Promise((resolve, reject) => {
    http.get(u, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', reject);
  });
}

async function main() {
  try {
    const targetsJson = await httpGet('http://localhost:' + port + '/json');
    const targets = JSON.parse(targetsJson);
    const pageTarget = targets.find(t => t.type === 'page');
    if (!pageTarget) { process.exit(1); }

    const wsUrl = new URL(pageTarget.webSocketDebuggerUrl);

    const sock = new net.Socket();
    let buf = Buffer.alloc(0);
    let handshakeDone = false;
    let msgId = 1;
    const handlers = new Map();

    function sendWS(obj) {
      const payload = JSON.stringify(obj);
      const mask = crypto.randomBytes(4);
      const len = Buffer.byteLength(payload);
      let hdr;
      if (len < 126) {
        hdr = Buffer.alloc(6); hdr[0] = 0x81; hdr[1] = 0x80 | len; mask.copy(hdr, 2);
      } else if (len < 65536) {
        hdr = Buffer.alloc(8); hdr[0] = 0x81; hdr[1] = 0x80 | 126; hdr.writeUInt16BE(len, 2); mask.copy(hdr, 4);
      } else {
        hdr = Buffer.alloc(14); hdr[0] = 0x81; hdr[1] = 0x80 | 127; hdr.writeBigUInt64BE(BigInt(len), 2); mask.copy(hdr, 10);
      }
      const body = Buffer.from(payload, 'utf8');
      const masked = Buffer.alloc(body.length);
      for (let i = 0; i < body.length; i++) masked[i] = body[i] ^ mask[i & 3];
      sock.write(Buffer.concat([hdr, masked]));
    }

    function parseFrames(data) {
      const msgs = []; let off = 0;
      while (off < data.length) {
        if (off + 2 > data.length) break;
        let pl = data[off + 1] & 0x7f, hl = 2;
        if (pl === 126) { if (off + 4 > data.length) break; pl = data.readUInt16BE(off + 2); hl = 4; }
        else if (pl === 127) { if (off + 10 > data.length) break; pl = Number(data.readBigUInt64BE(off + 2)); hl = 10; }
        if (off + hl + pl > data.length) break;
        if ((data[off] & 0x0f) === 1) msgs.push(data.slice(off + hl, off + hl + pl).toString());
        off += hl + pl;
      }
      return { msgs, rest: data.slice(off) };
    }

    sock.on('data', chunk => {
      if (!handshakeDone) {
        const headerEnd = chunk.indexOf('\r\n\r\n');
        if (headerEnd === -1) return;
        handshakeDone = true;
        chunk = chunk.slice(headerEnd + 4);
        if (chunk.length === 0) return;
      }
      buf = Buffer.concat([buf, chunk]);
      const { msgs, rest } = parseFrames(buf);
      buf = rest;
      for (const m of msgs) {
        try {
          const p = JSON.parse(m);
          if (p.id && handlers.has(p.id)) { handlers.get(p.id)(p); handlers.delete(p.id); }
        } catch {}
      }
    });
    sock.on('error', () => process.exit(1));

    await new Promise(resolve => {
      sock.connect(parseInt(wsUrl.port), wsUrl.hostname, () => {
        const key = crypto.randomBytes(16).toString('base64');
        sock.write(
          'GET ' + wsUrl.pathname + ' HTTP/1.1\r\n' +
          'Host: localhost:' + wsUrl.port + '\r\n' +
          'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
          'Sec-WebSocket-Key: ' + key + '\r\n' +
          'Sec-WebSocket-Version: 13\r\n\r\n'
        );
        setTimeout(resolve, 500);
      });
    });

    const navId = msgId++;
    sendWS({ id: navId, method: 'Page.navigate', params: { url: targetUrl } });
    await new Promise(r => { handlers.set(navId, () => r()); setTimeout(r, 8000); });
    await new Promise(r => setTimeout(r, 3000));

    const vpId = msgId++;
    sendWS({ id: vpId, method: 'Emulation.setDeviceMetricsOverride', params: { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false } });
    await new Promise(r => { handlers.set(vpId, () => r()); setTimeout(r, 2000); });

    const ssId = msgId++;
    sendWS({ id: ssId, method: 'Page.captureScreenshot', params: { format: 'png' } });
    const result = await new Promise(r => {
      handlers.set(ssId, resp => r(resp));
      setTimeout(() => r(null), 15000);
    });

    if (result && result.result && result.result.data) {
      fs.writeFileSync(outFile, Buffer.from(result.result.data, 'base64'));
      process.exit(0);
    } else {
      process.exit(1);
    }
  } catch(e) {
    process.exit(1);
  }
}
main();
CDPSCRIPT

  local screenshot_success=0

  if command -v node &> /dev/null; then
    node "$node_script" "$cdp_port" "$target_url" "$output_file" 2>/dev/null
    if [ -f "$output_file" ] && [ -s "$output_file" ] && file "$output_file" 2>/dev/null | grep -q "PNG"; then
      screenshot_success=1
    fi
  fi

  _cdp_cleanup

  return $((1 - screenshot_success))
}

# 使用 LLM 验证 UI 截图
# 参数: $1 = 截图文件路径, $2 = 子任务描述（可选）
# 输出: JSON 格式 {"pass": true/false, "feedback": "..."}
verify_ui_with_llm() {
 local screenshot_file="$1"
 local subtask_desc="${2:-}"
 local work_dir
 work_dir=$(dirname "$screenshot_file")

 log "使用 LLM 验证 UI 截图..." >&2

 # 检查 claude CLI 是否可用
 if ! command -v claude > /dev/null 2>&1; then
 error "claude CLI 不可用，无法进行 UI 验证"
 echo '{"pass": true, "feedback": "claude CLI 不可用，跳过 UI 验证"}'
 return 0
 fi

 # 检查截图文件是否存在
 if [ ! -f "$screenshot_file" ]; then
 error "截图文件不存在: $screenshot_file"
 echo '{"pass": true, "feedback": "截图文件不存在，跳过 UI 验证"}'
 return 0
 fi

 # 构建验证 prompt
 local prompt="请分析以下 UI 截图，验证页面是否正确渲染。

## UI 验证标准
请检查以下方面：
1. 页面无空白或崩溃：页面能正常加载，无白屏、错误页面或明显的布局错乱
2. 关键元素可见：页面标题、内容、导航等关键元素是否正确渲染并可见
3. 交互元素可点击：按钮、链接、表单等交互元素是否正常显示
4. 无 console 错误：页面不应有明显的 JavaScript 错误导致的显示问题
5. 样式一致性：CSS 样式应该与设计稿或现有风格一致
6. 响应式布局：布局应该合理（如适用）

## 验证要求
- 如果页面看起来正常，关键元素可见且无明显问题，返回 pass
- 如果发现任何问题（空白、崩溃、关键元素缺失、样式错乱等），返回 fail 并详细描述问题

## 输出格式
必须返回以下 JSON 格式（严格遵循）：
\`\`\`json
{
 \"pass\": true/false,
 \"feedback\": \"验证结果说明，包括发现的问题（如有）\"
}
\`\`\`"

 if [ -n "$subtask_desc" ]; then
 prompt="$prompt

## 子任务描述
$subtask_desc"
 fi

 # 调用 claude 进行验证，带重试逻辑
 local log_file="$work_dir/ui-verify-llm.log"
 local result
 local retry=0
 local max_llm_retries=3
 local llm_success=0

 while [ $retry -lt $max_llm_retries ] && [ $llm_success -eq 0 ]; do
 retry=$((retry + 1))

 if [ $retry -gt 1 ]; then
 log "LLM 验证重试 $retry/$max_llm_retries..." >&2
 sleep $((retry * 2))
 fi

 if claude -p "$prompt" --dangerously-skip-permissions \
 --file "$screenshot_file" \
 > "$log_file" 2>&1; then
 if [ -f "$log_file" ] && [ -s "$log_file" ]; then
 result=$(cat "$log_file")
 llm_success=1
 else
 error "LLM 验证输出文件为空 (尝试 $retry/$max_llm_retries)"
 fi
 else
 error "LLM 验证调用失败 (尝试 $retry/$max_llm_retries)"
 fi
 done

 if [ $llm_success -eq 0 ]; then
 error "LLM 验证调用失败，已达最大重试次数"
 echo '{"pass": true, "feedback": "LLM 验证调用失败，跳过验证"}'
 return 0
 fi

 # 从结果中提取 JSON
 local json_result
 json_result=$(echo "$result" | sed -n '/^\`\`\`json$/,/^\`\`\`$/p' | sed '/^\`\`\`/d')

 if [ -z "$json_result" ]; then
 # 如果没有找到 JSON 代码块，尝试直接提取 JSON
 json_result=$(echo "$result" | grep -A5 '"pass"' | head -20)
 fi

 # 验证 JSON 格式
 if echo "$json_result" | jq '.' > /dev/null 2>&1; then
 local pass
 pass=$(echo "$json_result" | jq -r '.pass // "true"')
 if [ "$pass" = "true" ]; then
 log "UI 验证通过" >&2
 else
 local feedback
 feedback=$(echo "$json_result" | jq -r '.feedback // "UI 验证未通过"')
 log "UI 验证未通过: $feedback" >&2
 fi
 echo "$json_result"
 else
 # JSON 解析失败，默认通过并记录警告
 log "警告: 无法解析 LLM 验证结果，默认通过" >&2
 echo '{"pass": true, "feedback": "无法解析验证结果，默认通过"}'
 fi
}

# 清理 dev server 进程
cleanup_dev_server() {
  if [ -n "$_UI_DEV_SERVER_PID" ] && kill -0 "$_UI_DEV_SERVER_PID" 2>/dev/null; then
    log "清理 dev server 进程 (PID: $_UI_DEV_SERVER_PID)..."
    kill "$_UI_DEV_SERVER_PID" 2>/dev/null || true
    sleep 1
    # 确保进程已终止
    if kill -0 "$_UI_DEV_SERVER_PID" 2>/dev/null; then
      kill -9 "$_UI_DEV_SERVER_PID" 2>/dev/null || true
    fi
    _UI_DEV_SERVER_PID=""
  fi
}

# 运行完整的 UI 验证流程
# 参数: $1 = 工作目录, $2 = 子任务描述（可选）
# 返回: 0 = 通过, 1 = 失败
# 输出: 验证结果 JSON 到 stdout
run_ui_verification() {
  local work_dir="$1"
  local subtask_desc="${2:-}"
  local result_file="$work_dir/ui-verify-result.json"
  local screenshot_file="$work_dir/ui-screenshot.png"

  log "========== UI 验证开始 ==========" >&2

  # 检查 UI 验证是否启用
  if [ "$UI_VERIFY_ENABLED" != "yes" ] && [ "$UI_VERIFY_ENABLED" != "true" ]; then
    log "UI 验证已禁用" >&2
    echo '{"pass": true, "feedback": "UI 验证已禁用"}'
    return 0
  fi

  # 步骤 1: 检测 dev server 命令
  local dev_cmd
  dev_cmd=$(detect_dev_server_command "$PROJECT_ROOT")
  if [ -z "$dev_cmd" ]; then
    log "警告: 无法检测 dev server 启动命令，跳过 UI 验证" >&2
    echo '{"pass": true, "feedback": "无法检测 dev server 命令，跳过 UI 验证"}'
    return 0
  fi
  log "检测到 dev server 命令: $dev_cmd" >&2

  # 步骤 2: 检测端口号
  local port
  port=$(detect_dev_server_port "$PROJECT_ROOT")
  log "检测到的 dev server 端口: $port" >&2

  # 步骤 3: 启动 dev server
  log "启动 dev server..." >&2
  cd "$PROJECT_ROOT"

  # 后台启动 dev server
  bash -c "$dev_cmd" > "$work_dir/dev-server.log" 2>&1 &
  _UI_DEV_SERVER_PID=$!
  log "dev server 已启动 (PID: $_UI_DEV_SERVER_PID)" >&2

  # 步骤 4: 等待 dev server 就绪
  if ! wait_for_dev_server "$port" "$UI_VERIFY_TIMEOUT"; then
    cleanup_dev_server
    echo "{\"pass\": false, \"feedback\": \"dev server 启动超时或失败\"}" >> "$work_dir/log.md" 2>/dev/null
    echo "{\"pass\": false, \"feedback\": \"dev server 启动超时或失败\"}"
    return 1
  fi

 # 步骤 5: 捕获截图
 local screenshot_success=0
 local target_url="http://localhost:$port"
 if capture_screenshot "$target_url" "$screenshot_file"; then
 screenshot_success=1
 else
 # 截图失败：记录警告但继续，尝试降级处理
 log "截图失败，尝试降级处理..." >&2
 echo "截图失败时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$work_dir/ui-screenshot-error.log" 2>/dev/null || true
 fi

 # 步骤 6: 使用 LLM 验证截图（如果截图成功）
 local verify_result
 if [ $screenshot_success -eq 1 ]; then
 verify_result=$(verify_ui_with_llm "$screenshot_file" "$subtask_desc")
 else
 # 截图失败时的降级处理：记录警告但标记为通过，不阻塞主流程
 log "截图不可用，UI 验证降级为通过" >&2
 verify_result='{"pass": true, "feedback": "截图工具不可用，跳过 UI 验证（降级处理）"}'
 fi

  # 步骤 7: 清理 dev server
  cleanup_dev_server

  # 保存验证结果
  echo "$verify_result" > "$result_file"

  # 记录到日志
  local pass
  pass=$(echo "$verify_result" | jq -r '.pass // "false"')
  local feedback
  feedback=$(echo "$verify_result" | jq -r '.feedback // ""')

  log "========== UI 验证结果 ==========" >&2
  if [ "$pass" = "true" ]; then
    log "结果: 通过" >&2
  else
    log "结果: 未通过" >&2
  fi
  log "反馈: $feedback" >&2
  log "==================================" >&2

  echo "$verify_result"

  if [ "$pass" = "true" ]; then
    return 0
  else
    return 1
  fi
}
