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

# 3. 确保 sshd 安装在 2222 端口监听、允许密码登录、设置密码
#    （Codespace 重启后平台 sshd 不保证自动启动，这里自行管理，保证 frpc 转发目标可用）
if ! command -v sshd >/dev/null 2>&1; then
  log "installing openssh-server..."
  sudo apt-get update -qq && sudo apt-get install -y -qq openssh-server
fi
sudo mkdir -p /run/sshd
sudo bash -c 'test -f /etc/ssh/ssh_host_rsa_key || ssh-keygen -A >/dev/null'
sudo bash -c 'cat > /etc/ssh/sshd_config.d/99-codespace-frp.conf <<EOF
Port 2222
PasswordAuthentication yes
PermitRootLogin no
UsePAM yes
EOF'
echo "codespace:123" | sudo chpasswd
if ! pgrep -x sshd >/dev/null; then
  log "starting sshd on 2222"
  sudo /usr/sbin/sshd -E /var/log/sshd.log || true
fi

# 4. 启动 frpc（若未运行）
if ! pgrep -x frpc >/dev/null; then
  log "starting frpc"
  nohup /usr/local/bin/frpc -c "$HOME/frpc.toml" >"$HOME/frpc.log" 2>&1 &
  sleep 1
else
  log "frpc already running"
fi

log "setup done"
