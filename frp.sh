#!/bin/bash

# ============================================================
#   FRP Load Balancer Script (Multi-Kharej to Single Iran)
#   Version: 3.0
#   Features:
#     - Multi-port via comma:  8080,8443,9000
#     - Port range:            1000-1010
#     - Mixed:                 80,443,8000-8010,9090
#     - Load Balancing via 'group' feature
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
#   Helper Functions
# ─────────────────────────────────────────

log_info()    { echo -e "${GREEN}[✔]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✘]${NC} $1"; }
log_section() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

# Parse mixed port spec: "80,443,8000-8010,9090"
# Outputs one port per line
parse_ports() {
    local input="$1"
    local result=()

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            if (( start > end )); then
                log_error "Invalid range: $part (start > end)"
                return 1
            fi
            for (( p=start; p<=end; p++ )); do
                result+=("$p")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            result+=("$part")
        else
            log_error "Invalid port entry: '$part'"
            return 1
        fi
    done

    printf '%s\n' "${result[@]}"
}

# Validate a single port number
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        return 1
    fi
    return 0
}

show_menu() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    FRP Load Balancer Setup  v3.0     ║"
    echo "  ║  Multi-Port | Range | Comma Support  ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  1)  Install FRP on Iran  (Server / frps)"
    echo "  2)  Install FRP on Kharej (Client / frpc - LB Mode)"
    echo "  3)  Show Status"
    echo "  4)  Remove FRP"
    echo "  5)  Exit"
    echo ""
    read -p "  Choose [1-5]: " choice
}

# ─────────────────────────────────────────
#   Install Server (Iran)
# ─────────────────────────────────────────

install_server() {
    log_section "Installing FRP Server (frps) on Iran"

    # Download frps
    log_info "Downloading frps..."
    if ! curl -fsSL -o "$FRPS_BIN" "$FRPS_DOWNLOAD"; then
        log_error "Download failed. Check your connection or URL."
        return 1
    fi
    chmod +x "$FRPS_BIN"

    # Collect config
    read -p "  Bind port for frps [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then
        log_error "Invalid port: $server_port"
        return 1
    fi

    read -p "  Auth token [default: $DEFAULT_TOKEN]: " token
    token=${token:-$DEFAULT_TOKEN}

    local cfg_name="server-${server_port}"
    local cfg_file="$FRP_DIR/server/${cfg_name}.toml"
    local svc_name="frps@${cfg_name}.service"

    mkdir -p "$FRP_DIR/server"

    # Write config
    cat > "$cfg_file" <<EOF
bindAddr = "::"
bindPort = $server_port
transport.heartbeatTimeout = 90
transport.maxPoolCount = 65535
transport.tcpMux = false
auth.method = "token"
auth.token = "$token"
EOF

    # Systemd template (only write once)
    if [[ ! -f /etc/systemd/system/frps@.service ]]; then
        cat > /etc/systemd/system/frps@.service <<'EOF'
[Unit]
Description=FRP Server Service (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /root/frp/server/%i.toml
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    if systemctl is-active --quiet "$svc_name"; then
        log_info "frps is running on port $server_port"
        log_info "Config: $cfg_file"
        log_info "Service: $svc_name"
    else
        log_error "frps failed to start. Check: journalctl -u $svc_name -e"
    fi
}

# ─────────────────────────────────────────
#   Install Client (Kharej)
# ─────────────────────────────────────────

install_client() {
    log_section "Installing FRP Client (Kharej) — Load Balance Mode"

    # Download frpc
    log_info "Downloading frpc..."
    if ! curl -fsSL -o "$FRPC_BIN" "$FRPC_DOWNLOAD"; then
        log_error "Download failed. Check your connection or URL."
        return 1
    fi
    chmod +x "$FRPC_BIN"

    # Collect config
    read -p "  Enter Iran server IP/address: " server_addr
    if [[ -z "$server_addr" ]]; then
        log_error "Server address cannot be empty."
        return 1
    fi

    read -p "  Server port [default: $DEFAULT_SERVER_PORT]: " server_port
    server_port=${server_port:-$DEFAULT_SERVER_PORT}
    if ! validate_port "$server_port"; then
        log_error "Invalid port: $server_port"
        return 1
    fi

    read -p "  Auth token [default: $DEFAULT_TOKEN]: " token
    token=${token:-$DEFAULT_TOKEN}

    echo ""
    echo -e "  ${YELLOW}Port formats supported:${NC}"
    echo "    Single port:   8080"
    echo "    Port range:    1000-1010"
    echo "    Comma list:    80,443,8080"
    echo "    Mixed:         80,443,8000-8005,9090"
    echo ""
    read -p "  Enter ports: " ports_raw
    ports_raw=${ports_raw:-8080}

    # Parse ports
    mapfile -t port_list < <(parse_ports "$ports_raw")
    if [[ ${#port_list[@]} -eq 0 ]]; then
        log_error "No valid ports parsed from: $ports_raw"
        return 1
    fi

    log_info "Parsed ${#port_list[@]} port(s): ${port_list[*]}"

    read -p "  Load balancer group name [default: lb-group]: " lb_group
    lb_group=${lb_group:-lb-group}

    read -p "  Load balancer group key [default: secret-key]: " lb_key
    lb_key=${lb_key:-secret-key}

    local cfg_name="client-${server_port}"
    local cfg_file="$FRP_DIR/client/${cfg_name}.toml"
    local svc_name="frpc@${cfg_name}.service"

    mkdir -p "$FRP_DIR/client"

    # Build config header
    cat > "$cfg_file" <<EOF
serverAddr = "$server_addr"
serverPort = $server_port
loginFailExit = false
auth.method = "token"
auth.token = "$token"

transport.protocol = "tcp"
transport.tcpMux = false

EOF

    # Append one proxy block per port
    # IMPORTANT: loadBalancer must use inline dot-notation (loadBalancer.group = ...)
    # NOT [proxies.loadBalancer] section header — that breaks multi-proxy TOML parsing
    for port in "${port_list[@]}"; do
        cat >> "$cfg_file" <<EOF
[[proxies]]
name = "lb-tcp-${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${port}
remotePort = ${port}
loadBalancer.group = "${lb_group}"
loadBalancer.groupKey = "${lb_key}"

EOF
    done

    log_info "Config written: $cfg_file  (${#port_list[@]} proxy entries)"

    # Systemd template (only write once)
    if [[ ! -f /etc/systemd/system/frpc@.service ]]; then
        cat > /etc/systemd/system/frpc@.service <<'EOF'
[Unit]
Description=FRP Client Service (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /root/frp/client/%i.toml
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable "$svc_name"
    systemctl restart "$svc_name"

    if systemctl is-active --quiet "$svc_name"; then
        log_info "frpc is running  →  $server_addr:$server_port"
        log_info "Service: $svc_name"
        echo ""
        log_warn "Run this script on ALL Kharej servers with the SAME ports & group settings."
    else
        log_error "frpc failed to start. Check: journalctl -u $svc_name -e"
    fi
}

# ─────────────────────────────────────────
#   Status
# ─────────────────────────────────────────

show_status() {
    log_section "FRP Service Status"

    echo -e "\n${CYAN}── frps (Server) ──${NC}"
    for f in /etc/systemd/system/frps@*.service; do
        local name
        name=$(basename "$f" .service | sed 's/frps@//')
        local state
        state=$(systemctl is-active "frps@${name}.service" 2>/dev/null)
        if [[ "$state" == "active" ]]; then
            echo -e "  frps@${name}  ${GREEN}● active${NC}"
        else
            echo -e "  frps@${name}  ${RED}● ${state}${NC}"
        fi
    done

    echo -e "\n${CYAN}── frpc (Client) ──${NC}"
    for f in /etc/systemd/system/frpc@*.service; do
        local name
        name=$(basename "$f" .service | sed 's/frpc@//')
        local state
        state=$(systemctl is-active "frpc@${name}.service" 2>/dev/null)
        if [[ "$state" == "active" ]]; then
            echo -e "  frpc@${name}  ${GREEN}● active${NC}"
        else
            echo -e "  frpc@${name}  ${RED}● ${state}${NC}"
        fi
    done

    echo ""
    echo -e "${CYAN}── Config Files ──${NC}"
    [[ -d "$FRP_DIR/server" ]] && ls "$FRP_DIR/server/"*.toml 2>/dev/null | while read -r f; do echo "  $f"; done
    [[ -d "$FRP_DIR/client" ]] && ls "$FRP_DIR/client/"*.toml 2>/dev/null | while read -r f; do echo "  $f"; done
}

# ─────────────────────────────────────────
#   Remove FRP
# ─────────────────────────────────────────

remove_frp() {
    log_section "Removing FRP"
    echo -e "${RED}This will stop and remove all FRP services, binaries, and configs.${NC}"
    read -p "  Are you sure? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Cancelled."; return; }

    # Stop and disable all services
    for svc in $(systemctl list-units --type=service --all | grep -oP 'frp[sc]@\S+\.service'); do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
        log_info "Stopped: $svc"
    done

    # Remove binaries and configs
    rm -f "$FRPS_BIN" "$FRPC_BIN"
    rm -f /etc/systemd/system/frps@.service /etc/systemd/system/frpc@.service
    rm -rf "$FRP_DIR"

    systemctl daemon-reload
    log_info "FRP fully removed."
}

# ─────────────────────────────────────────
#   Main Loop
# ─────────────────────────────────────────

# Root check
if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root."
    exit 1
fi

while true; do
    show_menu
    case "$choice" in
        1) install_server ;;
        2) install_client ;;
        3) show_status ;;
        4) remove_frp ;;
        5) echo "Bye!"; exit 0 ;;
        *) log_warn "Invalid option." ;;
    esac
    echo ""
    read -p "  Press Enter to continue..."
done
