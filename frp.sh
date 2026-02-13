#!/bin/bash

# ============================================================
#   FRP Load Balancer Script (Multi-Kharej to Single Iran)
#   Version: 4.0
#   Features:
#     - Multi-port:  80,443,8080
#     - Port range:  1000-1010
#     - Mixed:       80,443,8000-8010,9090
#     - Load Balancing via per-port group
#     - Tuned transport for stability
#     - Watchdog systemd timer
#     - Safe binary download (stop → replace → start)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FRP_DIR="/root/frp"
FRPS_BIN="/usr/local/bin/frps"
FRPC_BIN="/usr/local/bin/frpc"
DEFAULT_SERVER_PORT=3090
DEFAULT_TOKEN="tun100"
FRPS_DOWNLOAD="http://81.12.32.210/downloads/frps"
FRPC_DOWNLOAD="https://raw.githubusercontent.com/lostsoul6/frp-file/refs/heads/main/frpc"

# ─────────────────────────────────────────
#   Helpers
# ─────────────────────────────────────────

log_info()    { echo -e "${GREEN}[✔]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✘]${NC} $1"; }
log_section() {
    echo -e "\n${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

# Parse "80,443,1000-1010,9090" → one port per line
parse_ports() {
    local input="$1"
    local result=()
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
            if (( start > end )); then
                log_error "Invalid range: $part"; return 1
            fi
            for (( p=start; p<=end; p++ )); do result+=("$p"); done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            result+=("$part")
        else
            log_error "Invalid port: '$part'"; return 1
        fi
    done
    printf '%s\n' "${result[@]}"
}

# Safe download:
# 1. Stop service  2. Download to tmp  3. Verify ELF  4. Replace  5. Start later
safe_download() {
    local url="$1"
    local dest="$2"
    local svc_pattern="$3"
    local tmp
    tmp=$(mktemp)

    # Stop running instances so the file isn't locked
    for svc in $(systemctl list-units --type=service --all 2>/dev/null \
                 | grep -oP "${svc_pattern}\\S+\\.service" || true); do
        systemctl stop "$svc" 2>/dev/null || true
    done

    log_info "Downloading from $(basename "$url") ..."
    if ! curl -fsSL --retry 3 --retry-delay 2 \
              --connect-timeout 15 --max-time 90 \
              -o "$tmp" "$url"; then
        rm -f "$tmp"
        log_error "Download failed."
        return 1
    fi

    # Verify it's actually a binary
    if ! file "$tmp" 2>/dev/null | grep -q "ELF"; then
        rm -f "$tmp"
        log_error "Downloaded file is not a valid ELF binary. Wrong URL?"
        return 1
    fi

    mv -f "$tmp" "$dest"
    chmod +x "$dest"
    log_info "Binary installed: $dest"
}

show_menu() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    FRP Load Balancer Setup  v4.0     ║"
    echo "  ║  Multi-Port | Range | Comma Support  ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  1)  Install FRP on Iran  (Server / frps)"
    echo "  2)  Install FRP on Kharej (Client / frpc)"
    echo "  3)  Show Status"
    echo "  4)  Restart All Services"
    echo "  5)  Remove FRP"
    echo "  6)  Exit"
    echo ""
    read -rp "  Choose [1-6]: " choice
}

# ─────────────────────────────────────────
#   Systemd unit writers
# ─────────────────────────────────────────

write_frps_unit() {
    cat > /etc/systemd/system/frps@.service <<'EOF'
[Unit]
Description=FRP Server (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /root/frp/server/%i.toml
Restart=always
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=5
LimitNOFILE=1000000
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
}

write_frpc_unit() {
    cat > /etc/systemd/system/frpc@.service <<'EOF'
[Unit]
Description=FRP Client (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /root/frp/client/%i.toml
Restart=always
RestartSec=5s
StartLimitIntervalSec=60
StartLimitBurst=10
LimitNOFILE=1000000
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
}

# Watchdog: systemd timer that restarts dead frp services every 2 minutes
write_watchdog() {
    cat > /etc/systemd/system/frp-watchdog.service <<'EOF'
[Unit]
Description=FRP Watchdog — restart dead frp services

[Service]
Type=oneshot
ExecStart=/usr/local/bin/frp-watchdog.sh
EOF

    cat > /etc/systemd/system/frp-watchdog.timer <<'EOF'
[Unit]
Description=FRP Watchdog Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=120
AccuracySec=10

[Install]
WantedBy=timers.target
EOF

    cat > /usr/local/bin/frp-watchdog.sh <<'WDEOF'
#!/bin/bash
for svc in $(systemctl list-units --type=service --all 2>/dev/null \
             | grep -oP 'frp[sc]@\S+\.service'); do
    if ! systemctl is-active --quiet "$svc"; then
        systemctl restart "$svc" 2>/dev/null
        logger -t frp-watchdog "Restarted $svc"
    fi
done
WDEOF

    chmod +x /usr/local/bin/frp-watchdog.sh
    systemctl daemon-reload
    systemctl enable --now frp-watchdog.timer 2>/dev/null
    log_info "Watchdog timer enabled (checks every 2 min)"
}

# ─────────────────────────────────────────
#   Install Server (Iran)
# ─────────────────────────────────────────

install_server() {
    log_section "Installing FRP Server (frps) on Iran"

    safe_download "$FRPS_DOWNLOAD" "$FRPS_BIN" "frps@" || return 1

    read -rp "  Bind port [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then
        log_error "Invalid port: $server_port"; return 1
    fi

    read -rp "  Auth token [default: $DEFAULT_TOKEN]: " token
    token=${token:-$DEFAULT_TOKEN}

    local cfg_name="server-${server_port}"
    local cfg_file="$FRP_DIR/server/${cfg_name}.toml"
    local svc_name="frps@${cfg_name}.service"

    mkdir -p "$FRP_DIR/server"

    cat > "$cfg_file" <<EOF
# FRP Server — Iran
bindAddr = "::"
bindPort = $server_port

# Heartbeat: detect dead clients quickly
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30

# Connection pool
transport.maxPoolCount = 65535
transport.tcpMux = false
transport.tls.enable = false

# Auth
auth.method = "token"
auth.token = "$token"

# Logging (warn only to reduce I/O)
log.level = "warn"
log.maxDays = 3
EOF

    write_frps_unit
    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    sleep 1
    if systemctl is-active --quiet "$svc_name"; then
        log_info "frps running on port $server_port ✔"
        log_info "Config : $cfg_file"
        log_info "Service: $svc_name"
        write_watchdog
    else
        log_error "frps failed to start."
        log_error "Check: journalctl -u $svc_name -n 30 --no-pager"
    fi
}

# ─────────────────────────────────────────
#   Install Client (Kharej)
# ─────────────────────────────────────────

install_client() {
    log_section "Installing FRP Client (Kharej)"

    safe_download "$FRPC_DOWNLOAD" "$FRPC_BIN" "frpc@" || return 1

    read -rp "  Iran server IP/address: " server_addr
    if [[ -z "$server_addr" ]]; then
        log_error "Server address cannot be empty."; return 1
    fi

    read -rp "  Server port [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then
        log_error "Invalid port: $server_port"; return 1
    fi

    read -rp "  Auth token [default: $DEFAULT_TOKEN]: " token
    token=${token:-$DEFAULT_TOKEN}

    echo ""
    echo -e "  ${YELLOW}Port formats:${NC}"
    echo "    Single : 8080"
    echo "    Range  : 1000-1010"
    echo "    Comma  : 80,443,8080"
    echo "    Mixed  : 80,443,8000-8005,9090"
    echo ""
    read -rp "  Enter ports: " ports_raw
    ports_raw=${ports_raw:-8080}

    mapfile -t port_list < <(parse_ports "$ports_raw")
    if [[ ${#port_list[@]} -eq 0 ]]; then
        log_error "No valid ports parsed from: $ports_raw"; return 1
    fi
    log_info "Parsed ${#port_list[@]} port(s): ${port_list[*]}"

    read -rp "  LB group key [default: secret-key]: " lb_key
    lb_key=${lb_key:-secret-key}

    local cfg_name="client-${server_port}"
    local cfg_file="$FRP_DIR/client/${cfg_name}.toml"
    local svc_name="frpc@${cfg_name}.service"

    mkdir -p "$FRP_DIR/client"

    cat > "$cfg_file" <<EOF
# FRP Client — Kharej
serverAddr = "$server_addr"
serverPort = $server_port
loginFailExit = false

# Auth
auth.method = "token"
auth.token = "$token"

# Transport — tuned for stability
transport.protocol = "tcp"
transport.tcpMux = false
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30
transport.poolCount = 5
transport.dialServerTimeout = 10

# Logging (warn only)
log.level = "warn"
log.maxDays = 3

EOF

    # Each port gets its own group (lb-PORT) because FRP requires
    # all proxies in a group to share the exact same remotePort.
    for port in "${port_list[@]}"; do
        cat >> "$cfg_file" <<EOF
[[proxies]]
name = "lb-tcp-${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
loadBalancer.group = "lb-${port}"
loadBalancer.groupKey = "${lb_key}"

EOF
    done

    log_info "Config written: $cfg_file (${#port_list[@]} proxies)"

    write_frpc_unit
    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    sleep 1
    if systemctl is-active --quiet "$svc_name"; then
        log_info "frpc running → $server_addr:$server_port ✔"
        log_info "Service: $svc_name"
        echo ""
        log_warn "Install on ALL Kharej servers with SAME ports & group key."
        write_watchdog
    else
        log_error "frpc failed to start."
        log_error "Check: journalctl -u $svc_name -n 30 --no-pager"
    fi
}

# ─────────────────────────────────────────
#   Status
# ─────────────────────────────────────────

show_status() {
    log_section "FRP Service Status"
    local found=0

    echo -e "\n${CYAN}── frps (Iran/Server) ──${NC}"
    for f in /etc/systemd/system/frps@*.service; do
        [[ -e "$f" ]] || continue
        found=1
        local name state uptime
        name=$(basename "$f" .service | sed 's/frps@//')
        state=$(systemctl is-active "frps@${name}.service" 2>/dev/null || echo "unknown")
        uptime=$(systemctl show "frps@${name}.service" \
                 -p ActiveEnterTimestamp --value 2>/dev/null | sed 's/ [A-Z]*$//' || echo "")
        if [[ "$state" == "active" ]]; then
            echo -e "  ${GREEN}●${NC} frps@${name}  ${GREEN}active${NC}  since $uptime"
        else
            echo -e "  ${RED}●${NC} frps@${name}  ${RED}${state}${NC}"
        fi
    done

    echo -e "\n${CYAN}── frpc (Kharej/Client) ──${NC}"
    for f in /etc/systemd/system/frpc@*.service; do
        [[ -e "$f" ]] || continue
        found=1
        local name state uptime
        name=$(basename "$f" .service | sed 's/frpc@//')
        state=$(systemctl is-active "frpc@${name}.service" 2>/dev/null || echo "unknown")
        uptime=$(systemctl show "frpc@${name}.service" \
                 -p ActiveEnterTimestamp --value 2>/dev/null | sed 's/ [A-Z]*$//' || echo "")
        if [[ "$state" == "active" ]]; then
            echo -e "  ${GREEN}●${NC} frpc@${name}  ${GREEN}active${NC}  since $uptime"
        else
            echo -e "  ${RED}●${NC} frpc@${name}  ${RED}${state}${NC}"
        fi
    done

    (( found == 0 )) && log_warn "No FRP services found."

    echo -e "\n${CYAN}── Watchdog ──${NC}"
    if systemctl is-active --quiet frp-watchdog.timer 2>/dev/null; then
        local next
        next=$(systemctl status frp-watchdog.timer 2>/dev/null | grep "Trigger:" | sed 's/.*Trigger: //')
        echo -e "  ${GREEN}●${NC} frp-watchdog.timer  ${GREEN}active${NC}  next: $next"
    else
        echo -e "  ${YELLOW}○${NC} frp-watchdog.timer  not running"
    fi

    echo -e "\n${CYAN}── Config Files ──${NC}"
    for d in "$FRP_DIR/server" "$FRP_DIR/client"; do
        [[ -d "$d" ]] && for f in "$d"/*.toml; do
            [[ -e "$f" ]] && echo "  $f"
        done
    done
}

# ─────────────────────────────────────────
#   Restart All
# ─────────────────────────────────────────

restart_all() {
    log_section "Restarting All FRP Services"
    local found=0
    for svc in $(systemctl list-units --type=service --all 2>/dev/null \
                 | grep -oP 'frp[sc]@\S+\.service' || true); do
        if systemctl restart "$svc" 2>/dev/null; then
            log_info "Restarted: $svc"
        else
            log_error "Failed: $svc"
        fi
        found=1
    done
    (( found == 0 )) && log_warn "No FRP services found."
}

# ─────────────────────────────────────────
#   Remove FRP
# ─────────────────────────────────────────

remove_frp() {
    log_section "Removing FRP"
    echo -e "${RED}  This will remove all FRP services, binaries, and configs.${NC}"
    read -rp "  Are you sure? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Cancelled."; return; }

    systemctl stop frp-watchdog.timer frp-watchdog.service 2>/dev/null || true
    systemctl disable frp-watchdog.timer 2>/dev/null || true

    for svc in $(systemctl list-units --type=service --all 2>/dev/null \
                 | grep -oP 'frp[sc]@\S+\.service' || true); do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        log_info "Removed: $svc"
    done

    rm -f "$FRPS_BIN" "$FRPC_BIN" /usr/local/bin/frp-watchdog.sh
    rm -f /etc/systemd/system/frps@.service \
          /etc/systemd/system/frpc@.service \
          /etc/systemd/system/frp-watchdog.service \
          /etc/systemd/system/frp-watchdog.timer
    rm -rf "$FRP_DIR"

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    log_info "FRP fully removed."
}

# ─────────────────────────────────────────
#   Main
# ─────────────────────────────────────────

if [[ "$EUID" -ne 0 ]]; then
    log_error "Must be run as root."; exit 1
fi

while true; do
    show_menu
    case "$choice" in
        1) install_server  ;;
        2) install_client  ;;
        3) show_status     ;;
        4) restart_all     ;;
        5) remove_frp      ;;
        6) echo "Bye!"; exit 0 ;;
        *) log_warn "Invalid option." ;;
    esac
    echo ""
    read -rp "  Press Enter to continue..."
done
