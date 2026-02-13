#!/bin/bash

# ============================================================
#   FRP Load Balancer Script (Multi-Kharej to Single Iran)
#   Version: 4.1
#   - Multi-port: 80,443,8080  |  Range: 1000-1010  |  Mixed
#   - Auto-detects frp version → writes correct config format
#   - Watchdog systemd timer
#   - Safe binary download
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

parse_ports() {
    local input="$1"
    local result=()
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
            if (( start > end )); then log_error "Invalid range: $part"; return 1; fi
            for (( p=start; p<=end; p++ )); do result+=("$p"); done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            result+=("$part")
        else
            log_error "Invalid port: '$part'"; return 1
        fi
    done
    printf '%s\n' "${result[@]}"
}

# Detect frp version → returns major.minor as integer (e.g. 51 for v0.51.x)
# Returns 0 if version can't be detected (assume old)
get_frp_minor_version() {
    local bin="$1"
    local ver
    ver=$("$bin" --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    if [[ -z "$ver" ]]; then echo 0; return; fi
    # Extract minor version (e.g. 0.51.3 → 51)
    echo "$ver" | awk -F. '{print $2}' | tr -d '.'
}

# Safe download: stop service → download to tmp → verify ELF → replace
safe_download() {
    local url="$1"
    local dest="$2"
    local svc_pattern="$3"
    local tmp
    tmp=$(mktemp)

    for svc in $(systemctl list-units --type=service --all 2>/dev/null \
                 | grep -oP "${svc_pattern}\\S+\\.service" || true); do
        systemctl stop "$svc" 2>/dev/null || true
    done

    log_info "Downloading $(basename "$dest") ..."
    if ! curl -fsSL --retry 3 --retry-delay 2 \
              --connect-timeout 15 --max-time 90 \
              -o "$tmp" "$url"; then
        rm -f "$tmp"
        log_error "Download failed."
        return 1
    fi

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
    echo "  ║    FRP Load Balancer Setup  v4.1     ║"
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
#   Systemd units
# ─────────────────────────────────────────

write_frps_unit() {
    cat > /etc/systemd/system/frps@.service <<'EOF'
[Unit]
Description=FRP Server (%i)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /root/frp/server/%i.toml
Restart=always
RestartSec=5s
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
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /root/frp/client/%i.toml
Restart=always
RestartSec=5s
LimitNOFILE=1000000
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF
}

write_watchdog() {
    cat > /etc/systemd/system/frp-watchdog.service <<'EOF'
[Unit]
Description=FRP Watchdog

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
    log_info "Watchdog enabled (checks every 2 min)"
}

# ─────────────────────────────────────────
#   Write frps config (version-aware)
# ─────────────────────────────────────────

write_frps_config() {
    local cfg_file="$1"
    local bind_port="$2"
    local token="$3"
    local minor
    minor=$(get_frp_minor_version "$FRPS_BIN")

    log_info "Detected frps minor version: 0.$minor.x"

    if (( minor >= 50 )); then
        # v0.50+ : TOML with transport.* keys
        cat > "$cfg_file" <<EOF
# FRP Server — Iran  (v0.50+ config)
bindAddr = "::"
bindPort = $bind_port
transport.heartbeatTimeout = 30
transport.maxPoolCount = 65535
transport.tcpMux = false
auth.method = "token"
auth.token = "$token"
log.level = "warn"
log.maxDays = 3
EOF
    else
        # v0.49 and older: flat keys, ini-like TOML (no transport.* namespace)
        cat > "$cfg_file" <<EOF
# FRP Server — Iran  (legacy config)
bind_addr = "0.0.0.0"
bind_port = $bind_port
heartbeat_timeout = 30
max_pool_count = 65535
tcp_mux = false
token = "$token"
log_level = "warn"
log_max_days = 3
EOF
    fi
}

# ─────────────────────────────────────────
#   Write frpc config (version-aware)
# ─────────────────────────────────────────

write_frpc_config() {
    local cfg_file="$1"
    local server_addr="$2"
    local server_port="$3"
    local token="$4"
    local lb_key="$5"
    shift 5
    local port_list=("$@")
    local minor
    minor=$(get_frp_minor_version "$FRPC_BIN")

    log_info "Detected frpc minor version: 0.$minor.x"

    if (( minor >= 50 )); then
        # ── v0.50+ TOML format ──────────────────────────────────
        cat > "$cfg_file" <<EOF
# FRP Client — Kharej  (v0.50+ config)
serverAddr = "$server_addr"
serverPort = $server_port
loginFailExit = false
auth.method = "token"
auth.token = "$token"
transport.protocol = "tcp"
transport.tcpMux = false
transport.heartbeatInterval = 10
transport.heartbeatTimeout = 30
transport.poolCount = 5
transport.dialServerTimeout = 10
log.level = "warn"
log.maxDays = 3

EOF
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

    else
        # ── v0.49 and older INI format ──────────────────────────
        cat > "$cfg_file" <<EOF
# FRP Client — Kharej  (legacy config)
[common]
server_addr = $server_addr
server_port = $server_port
login_fail_exit = false
token = $token
tcp_mux = false
heartbeat_interval = 10
heartbeat_timeout = 30
pool_count = 5
log_level = warn
log_max_days = 3

EOF
        for port in "${port_list[@]}"; do
            cat >> "$cfg_file" <<EOF
[lb-tcp-${port}]
type = tcp
local_ip = 127.0.0.1
local_port = ${port}
remote_port = ${port}
group = lb-${port}
group_key = ${lb_key}

EOF
        done
    fi
}

# ─────────────────────────────────────────
#   Install Server (Iran)
# ─────────────────────────────────────────

install_server() {
    log_section "Installing FRP Server (frps) on Iran"

    safe_download "$FRPS_DOWNLOAD" "$FRPS_BIN" "frps@" || return 1

    read -rp "  Bind port [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then log_error "Invalid port: $server_port"; return 1; fi

    read -rp "  Auth token [default: $DEFAULT_TOKEN]: " token
    token=${token:-$DEFAULT_TOKEN}

    local cfg_name="server-${server_port}"
    local cfg_file="$FRP_DIR/server/${cfg_name}.toml"
    local svc_name="frps@${cfg_name}.service"

    mkdir -p "$FRP_DIR/server"
    write_frps_config "$cfg_file" "$server_port" "$token"
    log_info "Config: $cfg_file"

    write_frps_unit
    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    sleep 1
    if systemctl is-active --quiet "$svc_name"; then
        log_info "frps running on port $server_port ✔"
        write_watchdog
    else
        log_error "frps failed to start."
        log_error "Run: journalctl -u $svc_name -n 20 --no-pager"
    fi
}

# ─────────────────────────────────────────
#   Install Client (Kharej)
# ─────────────────────────────────────────

install_client() {
    log_section "Installing FRP Client (Kharej)"

    safe_download "$FRPC_DOWNLOAD" "$FRPC_BIN" "frpc@" || return 1

    read -rp "  Iran server IP/address: " server_addr
    if [[ -z "$server_addr" ]]; then log_error "Server address cannot be empty."; return 1; fi

    read -rp "  Server port [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then log_error "Invalid port: $server_port"; return 1; fi

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
    if [[ ${#port_list[@]} -eq 0 ]]; then log_error "No valid ports: $ports_raw"; return 1; fi
    log_info "Parsed ${#port_list[@]} port(s): ${port_list[*]}"

    read -rp "  LB group key [default: secret-key]: " lb_key
    lb_key=${lb_key:-secret-key}

    local cfg_name="client-${server_port}"
    local cfg_file="$FRP_DIR/client/${cfg_name}.toml"
    local svc_name="frpc@${cfg_name}.service"

    mkdir -p "$FRP_DIR/client"
    write_frpc_config "$cfg_file" "$server_addr" "$server_port" "$token" "$lb_key" "${port_list[@]}"
    log_info "Config: $cfg_file (${#port_list[@]} proxies)"

    write_frpc_unit
    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    sleep 1
    if systemctl is-active --quiet "$svc_name"; then
        log_info "frpc running → $server_addr:$server_port ✔"
        echo ""
        log_warn "Install on ALL Kharej servers with SAME ports & group key."
        write_watchdog
    else
        log_error "frpc failed to start."
        log_error "Run: journalctl -u $svc_name -n 20 --no-pager"
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
        [[ -e "$f" ]] || continue; found=1
        local name state uptime
        name=$(basename "$f" .service | sed 's/frps@//')
        state=$(systemctl is-active "frps@${name}.service" 2>/dev/null || echo "unknown")
        uptime=$(systemctl show "frps@${name}.service" -p ActiveEnterTimestamp \
                 --value 2>/dev/null | sed 's/ [A-Z]*$//' || echo "")
        if [[ "$state" == "active" ]]; then
            echo -e "  ${GREEN}●${NC} frps@${name}  ${GREEN}active${NC}  since $uptime"
        else
            echo -e "  ${RED}●${NC} frps@${name}  ${RED}${state}${NC}"
        fi
    done

    echo -e "\n${CYAN}── frpc (Kharej/Client) ──${NC}"
    for f in /etc/systemd/system/frpc@*.service; do
        [[ -e "$f" ]] || continue; found=1
        local name state uptime
        name=$(basename "$f" .service | sed 's/frpc@//')
        state=$(systemctl is-active "frpc@${name}.service" 2>/dev/null || echo "unknown")
        uptime=$(systemctl show "frpc@${name}.service" -p ActiveEnterTimestamp \
                 --value 2>/dev/null | sed 's/ [A-Z]*$//' || echo "")
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
        next=$(systemctl status frp-watchdog.timer 2>/dev/null \
               | grep "Trigger:" | sed 's/.*Trigger: //')
        echo -e "  ${GREEN}●${NC} frp-watchdog  ${GREEN}active${NC}  next: $next"
    else
        echo -e "  ${YELLOW}○${NC} frp-watchdog  not running"
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
        systemctl restart "$svc" 2>/dev/null && log_info "Restarted: $svc" \
                                              || log_error "Failed: $svc"
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
        1) install_server ;;
        2) install_client ;;
        3) show_status    ;;
        4) restart_all    ;;
        5) remove_frp     ;;
        6) echo "Bye!"; exit 0 ;;
        *) log_warn "Invalid option." ;;
    esac
    echo ""
    read -rp "  Press Enter to continue..."
done
