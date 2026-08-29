#!/usr/bin/env bash
# 每次 Codespace 启动时自动执行：安装 frpc、写入配置、开启 SSH 密码登录、启动隧道。
# 由 .devcontainer/devcontainer.json 的 postStartCommand 调用，幂等可重复执行。
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

# 1. 安装 frpc（若未安装）
if [ ! -x /usr/local/bin/frpc ]; then
  log "installing frpc..."
  FRP_VER=0.71.0
  FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VER}/frp_${FRP_VER}_linux_amd64.tar.gz"
  if command -v curl >/dev/null; then
    curl -fsSL -o /tmp/frp.tgz "$FRP_URL"
  else
    wget -q -O /tmp/frp.tgz "$FRP_URL"
  fi
  tar -xzf /tmp/frp.tgz -C /tmp
  sudo install -m 0755 "/tmp/frp_${FRP_VER}_linux_amd64/frpc" /usr/local/bin/frpc
  log "frpc installed: $(/usr/local/bin/frpc --version)"
fi

# 2. 写入 frpc 配置（若不存在）
if [ ! -f "$HOME/frpc.toml" ]; then
  log "writing $HOME/frpc.toml"
  cat > "$HOME/frpc.toml" <<'EOF'
serverAddr = "101.132.159.118"
serverPort = 7300
transport.tcpMux = true
transport.protocol = "tcp"
auth.method = "token"
auth.token = "2467233452536"
user = "82f7b3bfae3f4f58"
loginFailExit = false
dnsServer = "114.114.114.114"

[[proxies]]
name = "codespace"
type = "tcp"
localIP = "127.0.0.1"
localPort = 2222
remotePort = 22011
transport.useEncryption = false
transport.useCompression = false
EOF
fi

# 3. 允许 SSH 密码登录并设置 codespace 用户密码
sudo bash -c 'echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-password.conf'
echo "codespace:123" | sudo chpasswd
sudo pkill -HUP sshd || true

# 4. 启动 frpc（若未运行）
if ! pgrep -x frpc >/dev/null; then
  log "starting frpc"
  nohup /usr/local/bin/frpc -c "$HOME/frpc.toml" >"$HOME/frpc.log" 2>&1 &
  sleep 1
else
  log "frpc already running"
fi

log "setup done"
