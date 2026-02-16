#!/bin/bash

# Enhanced GRE Tunnel Configuration Script for Iran/Kharej Servers
# Version: 5.2 - Added MSS Clamping, RP Filter, and Sysctl Optimization

set -e

if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration directory
CONFIG_DIR="/etc/gre-tunnels"
SERVICE_DIR="/etc/systemd/system"

# Create config directory if not exists
mkdir -p $CONFIG_DIR

# Validate IPv4
validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                echo -e "${RED}Invalid IPv4: $ip${NC}"
                return 1
            fi
        done
        return 0
    else
        echo -e "${RED}Invalid IPv4 format: $ip${NC}"
        return 1
    fi
}

# Validate port list
validate_ports() {
    local ports=$1
    if [[ ! $ports =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        echo -e "${RED}Invalid port format. Use: 80,443,8080${NC}"
        return 1
    fi
    
    IFS=',' read -r -a port_array <<< "$ports"
    for port in "${port_array[@]}"; do
        if [[ $port -lt 1 || $port -gt 65535 ]]; then
            echo -e "${RED}Port $port is out of range (1-65535)${NC}"
            return 1
        fi
    done
    return 0
}

# Check if tunnel number already exists
check_tunnel_exists() {
    local tunnel_type=$1  # "iran" or "kharej"
    local tunnel_num=$2
    local config_file="$CONFIG_DIR/tunnel-${tunnel_type}-${tunnel_num}.conf"
    
    if [[ -f "$config_file" ]]; then
        return 0  # exists
    else
        return 1  # doesn't exist
    fi
}

# List existing tunnels of a type
list_existing_tunnels() {
    local tunnel_type=$1  # "iran" or "kharej"
    local prefix="tunnel-${tunnel_type}-"
    local found=0
    
    echo -e "${YELLOW}Existing ${tunnel_type} tunnels:${NC}"
    for file in "$CONFIG_DIR"/${prefix}*.conf; do
        if [[ -f "$file" ]]; then
            found=1
            num=$(basename "$file" | sed "s/${prefix}\([0-9]*\).conf/\1/")
            source "$file"
            echo -e "  • ${tunnel_type}-${num}: ${CYAN}$([ -n "$IRAN_IP" ] && echo "$IRAN_IP" || echo "$KHAREJ1_IP") → $([ -n "$KHAREJ_IP" ] && echo "$KHAREJ_IP" || echo "$KHAREJ2_IP")${NC}"
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "  ${YELLOW}(No ${tunnel_type} tunnels configured yet)${NC}"
    fi
    echo ""
}

# Get next available tunnel number for specific type
get_next_tunnel_number() {
    local tunnel_type=$1  # "iran" or "kharej"
    local max=0
    local prefix=""
    
    if [[ "$tunnel_type" == "iran" ]]; then
        prefix="tunnel-iran-"
    else
        prefix="tunnel-kharej-"
    fi
    
    for file in "$CONFIG_DIR"/${prefix}*.conf; do
        if [[ -f "$file" ]]; then
            num=$(basename "$file" | sed "s/${prefix}\([0-9]*\).conf/\1/")
            if [[ $num -gt $max ]]; then
                max=$num
            fi
        fi
    done
    echo $((max + 1))
}

# Get tunnel identifier (iran-X or kharej-X)
get_tunnel_id() {
    local tunnel_type=$1
    local tunnel_num=$2
    echo "${tunnel_type}-${tunnel_num}"
}

# Get next available tunnel IP based on type
get_next_tunnel_ip() {
    local tunnel_num=$1
    local tunnel_type=$2  # "iran" or "kharej"
    
    if [[ "$tunnel_type" == "iran" ]]; then
        # Iran-Kharej tunnels use 172.16.X.0/30
        echo "172.16.$tunnel_num"
    else
        # Kharej-Kharej tunnels use 172.17.X.0/30
        echo "172.17.$tunnel_num"
    fi
}

# Ask for MSS clamping configuration
ask_mss_clamping() {
    local tunnel_name=$1
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}TCP MSS Clamping Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}MSS clamping helps prevent fragmentation issues in GRE tunnels${NC}"
    echo -e "${YELLOW}Recommended for better performance and stability${NC}"
    echo ""
    
    read -p "Enable MSS clamping for this tunnel? (yes/no) [yes]: " enable_mss
    enable_mss=${enable_mss:-yes}
    
    if [[ "$enable_mss" == "yes" || "$enable_mss" == "y" ]]; then
        read -p "Enter MSS value (recommended: 1360) [1360]: " mss_value
        mss_value=${mss_value:-1360}
        
        if [[ ! $mss_value =~ ^[0-9]+$ ]] || [[ $mss_value -lt 500 || $mss_value -gt 1460 ]]; then
            echo -e "${YELLOW}Invalid MSS value. Using default: 1360${NC}"
            mss_value=1360
        fi
        
        echo "$mss_value"
        return 0
    else
        echo "0"
        return 1
    fi
}

# Apply MSS clamping rules
apply_mss_clamping() {
    local tunnel_name=$1
    local mss_value=$2
    
    if [[ "$mss_value" != "0" && -n "$mss_value" ]]; then
        iptables -t mangle -A FORWARD -o "$tunnel_name" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss_value"
        iptables -t mangle -A FORWARD -i "$tunnel_name" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$mss_value"
        echo -e "${GREEN}✓ MSS clamping enabled with value: $mss_value${NC}"
    fi
}

# Remove MSS clamping rules
remove_mss_clamping() {
    local tunnel_name=$1
    
    iptables-save -t mangle | grep "$tunnel_name" | grep TCPMSS | while read -r rule; do
        iptables -t mangle -D ${rule#-A } 2>/dev/null || true
    done
}

# Disable RP filter for tunnel interface
disable_rp_filter() {
    local tunnel_name=$1
    
    if [[ -d "/proc/sys/net/ipv4/conf/$tunnel_name" ]]; then
        echo 0 > "/proc/sys/net/ipv4/conf/$tunnel_name/rp_filter"
        echo -e "${GREEN}✓ RP filter disabled for $tunnel_name${NC}"
    fi
}

# Clean up specific tunnel
cleanup_tunnel() {
    local tunnel_id=$1
    local tunnel_name="GRE-${tunnel_id}"
    
    echo -e "${YELLOW}Cleaning up tunnel $tunnel_id...${NC}"
    
    # Remove MSS clamping rules
    remove_mss_clamping "$tunnel_name"
    
    # Remove tunnel interface
    if ip link show "$tunnel_name" &>/dev/null; then
        ip link set "$tunnel_name" down 2>/dev/null || true
        ip tunnel del "$tunnel_name" 2>/dev/null || true
        echo "✓ Removed tunnel interface $tunnel_name"
    fi
    
    # Remove iptables rules for this tunnel
    iptables-save | grep -v "$tunnel_name" | iptables-restore 2>/dev/null || true
    echo "✓ Cleaned iptables rules for tunnel $tunnel_id"
}

# Create systemd service for specific tunnel
create_systemd_service() {
    local tunnel_id=$1
    local service_file="$SERVICE_DIR/gre-tunnel-${tunnel_id}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=GRE Tunnel Service $tunnel_id
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh
ExecStop=/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "gre-tunnel-${tunnel_id}.service"
    echo -e "${GREEN}✓ Systemd service created for tunnel $tunnel_id${NC}"
}

# Configure Iran Server (Single Kharej)
configure_iran_single() {
    local iran_ipv4=$1
    local kharej_ipv4=$2
    local ports=$3
    local tunnel_num=$4
    local tunnel_id=$(get_tunnel_id "iran" "$tunnel_num")
    local tunnel_name="GRE-${tunnel_id}"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num" "iran")
    
    cleanup_tunnel "$tunnel_id"
    
    # Ask for MSS clamping
    local mss_value
    mss_value=$(ask_mss_clamping "$tunnel_name")
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-${tunnel_id}.conf" << EOF
SERVER_TYPE=iran
TUNNEL_TYPE=iran-kharej
TUNNEL_ID=$tunnel_id
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
IRAN_IP=$iran_ipv4
KHAREJ_IP=$kharej_ipv4
PORTS=$ports
TUNNEL_IP_IRAN=$tunnel_ip.1
TUNNEL_IP_KHAREJ=$tunnel_ip.2
MSS_VALUE=$mss_value
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre remote \$KHAREJ_IP local \$IRAN_IP ttl 64
ip addr add \$TUNNEL_IP_IRAN/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

# Disable RP filter for tunnel
if [[ -d "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME" ]]; then
    echo 0 > "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME/rp_filter"
fi

# Add route for tunnel network
ip route add $tunnel_ip.0/30 dev \$TUNNEL_NAME 2>/dev/null || true

# Configure iptables - DNAT selected ports to Kharej
iptables -t nat -A PREROUTING -p tcp -m multiport --dports \$PORTS -j DNAT --to-destination \$TUNNEL_IP_KHAREJ
iptables -t nat -A PREROUTING -p udp -m multiport --dports \$PORTS -j DNAT --to-destination \$TUNNEL_IP_KHAREJ

# Masquerade traffic going through GRE
iptables -t nat -A POSTROUTING -o \$TUNNEL_NAME -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i \$TUNNEL_NAME -j ACCEPT
iptables -A FORWARD -o \$TUNNEL_NAME -j ACCEPT

# Apply MSS clamping if enabled
if [[ "\$MSS_VALUE" != "0" && -n "\$MSS_VALUE" ]]; then
    iptables -t mangle -A FORWARD -o \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
    iptables -t mangle -A FORWARD -i \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
fi

echo "GRE tunnel $tunnel_id configured successfully on Iran server"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Remove MSS clamping rules
iptables-save -t mangle | grep "\$TUNNEL_NAME" | grep TCPMSS | while read -r rule; do
    iptables -t mangle -D \${rule#-A } 2>/dev/null || true
done

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

# Remove specific iptables rules
iptables-save | grep -v "\$TUNNEL_IP_KHAREJ" | grep -v "\$TUNNEL_NAME" | iptables-restore 2>/dev/null || true

echo "GRE tunnel $tunnel_id removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh"
    
    create_systemd_service "$tunnel_id"
    
    # Start the service
    systemctl start "gre-tunnel-${tunnel_id}.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Tunnel $tunnel_id configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel ID: $tunnel_id"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel Type: Iran -> Kharej"
    echo -e "Tunnel IP (Iran): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej): $tunnel_ip.2"
    echo -e "Forwarded Ports: $ports"
    if [[ "$mss_value" != "0" ]]; then
        echo -e "MSS Clamping: ${GREEN}Enabled${NC} (value: $mss_value)"
    else
        echo -e "MSS Clamping: ${YELLOW}Disabled${NC}"
    fi
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.2" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check Kharej server.${NC}"
    fi
    
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠  IMPORTANT NEXT STEP:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Now configure Kharej server with:${NC}"
    echo -e "  • Menu option: ${BLUE}3${NC}"
    echo -e "  • Tunnel number: ${BLUE}$tunnel_num${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Configure Iran Server (Multiple Kharej)
configure_iran_multi() {
    local iran_ipv4=$1
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Multi-Tunnel Configuration${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    read -p "How many Kharej servers do you want to connect? (1-10): " num_servers
    
    if [[ ! $num_servers =~ ^[0-9]+$ ]] || [[ $num_servers -lt 1 ]] || [[ $num_servers -gt 10 ]]; then
        echo -e "${RED}Invalid number. Must be between 1-10${NC}"
        return 1
    fi
    
    for ((i=1; i<=num_servers; i++)); do
        echo -e "\n${YELLOW}--- Configuring Tunnel #$i ---${NC}"
        
        read -p "Enter Kharej Server #$i Public IPv4: " kharej
        validate_ipv4 "$kharej" || return 1
        
        echo -e "${YELLOW}Enter ports to forward through tunnel #$i (comma-separated)${NC}"
        echo -e "${YELLOW}Example: 443,8443,2053${NC}"
        read -p "Ports for tunnel #$i: " ports
        validate_ports "$ports" || return 1
        
        local tunnel_num=$(get_next_tunnel_number "iran")
        configure_iran_single "$iran_ipv4" "$kharej" "$ports" "$tunnel_num"
        
        echo -e "${GREEN}✓ Tunnel #$i created successfully!${NC}\n"
        sleep 1
    done
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All tunnels configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    show_all_tunnels
}

# Configure Kharej Server (receiving from Iran)
configure_kharej() {
    local kharej_ipv4=$1
    local iran_ipv4=$2
    local tunnel_num=$3
    local tunnel_id=$(get_tunnel_id "iran" "$tunnel_num")
    local tunnel_name="GRE-${tunnel_id}"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num" "iran")
    
    cleanup_tunnel "$tunnel_id"
    
    # Ask for MSS clamping
    local mss_value
    mss_value=$(ask_mss_clamping "$tunnel_name")
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-${tunnel_id}.conf" << EOF
SERVER_TYPE=kharej
TUNNEL_TYPE=iran-kharej
TUNNEL_ID=$tunnel_id
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
IRAN_IP=$iran_ipv4
KHAREJ_IP=$kharej_ipv4
TUNNEL_IP_IRAN=$tunnel_ip.1
TUNNEL_IP_KHAREJ=$tunnel_ip.2
MSS_VALUE=$mss_value
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre local \$KHAREJ_IP remote \$IRAN_IP ttl 64
ip addr add \$TUNNEL_IP_KHAREJ/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

# Disable RP filter for tunnel
if [[ -d "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME" ]]; then
    echo 0 > "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME/rp_filter"
fi

# Add route for tunnel network
ip route add $tunnel_ip.0/30 dev \$TUNNEL_NAME 2>/dev/null || true

# Allow forwarding
iptables -A FORWARD -i \$TUNNEL_NAME -j ACCEPT
iptables -A FORWARD -o \$TUNNEL_NAME -j ACCEPT

# Apply MSS clamping if enabled
if [[ "\$MSS_VALUE" != "0" && -n "\$MSS_VALUE" ]]; then
    iptables -t mangle -A FORWARD -o \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
    iptables -t mangle -A FORWARD -i \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
fi

echo "GRE tunnel $tunnel_id configured successfully on Kharej server"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Remove MSS clamping rules
iptables-save -t mangle | grep "\$TUNNEL_NAME" | grep TCPMSS | while read -r rule; do
    iptables -t mangle -D \${rule#-A } 2>/dev/null || true
done

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

echo "GRE tunnel $tunnel_id removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh"
    
    create_systemd_service "$tunnel_id"
    
    # Start the service
    systemctl start "gre-tunnel-${tunnel_id}.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Tunnel $tunnel_id configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel ID: $tunnel_id"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel Type: Iran -> Kharej"
    echo -e "Tunnel IP (Iran): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej): $tunnel_ip.2"
    if [[ "$mss_value" != "0" ]]; then
        echo -e "MSS Clamping: ${GREEN}Enabled${NC} (value: $mss_value)"
    else
        echo -e "MSS Clamping: ${YELLOW}Disabled${NC}"
    fi
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.1" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check Iran server.${NC}"
    fi
}

# Configure Kharej-to-Kharej tunnel (First Kharej - receives from Iran and forwards to another Kharej)
configure_kharej_to_kharej_source() {
    local kharej1_ipv4=$1
    local kharej2_ipv4=$2
    local ports=$3
    local tunnel_num=$4
    local tunnel_id=$(get_tunnel_id "kharej" "$tunnel_num")
    local tunnel_name="GRE-${tunnel_id}"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num" "kharej")
    
    cleanup_tunnel "$tunnel_id"
    
    # Ask for MSS clamping
    local mss_value
    mss_value=$(ask_mss_clamping "$tunnel_name")
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-${tunnel_id}.conf" << EOF
SERVER_TYPE=kharej-source
TUNNEL_TYPE=kharej-kharej
TUNNEL_ID=$tunnel_id
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
KHAREJ1_IP=$kharej1_ipv4
KHAREJ2_IP=$kharej2_ipv4
PORTS=$ports
TUNNEL_IP_KHAREJ1=$tunnel_ip.1
TUNNEL_IP_KHAREJ2=$tunnel_ip.2
MSS_VALUE=$mss_value
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre remote \$KHAREJ2_IP local \$KHAREJ1_IP ttl 64
ip addr add \$TUNNEL_IP_KHAREJ1/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

# Disable RP filter for tunnel
if [[ -d "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME" ]]; then
    echo 0 > "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME/rp_filter"
fi

# Add route for tunnel network
ip route add $tunnel_ip.0/30 dev \$TUNNEL_NAME 2>/dev/null || true

# Configure iptables - DNAT selected ports to second Kharej
iptables -t nat -A PREROUTING -p tcp -m multiport --dports \$PORTS -j DNAT --to-destination \$TUNNEL_IP_KHAREJ2
iptables -t nat -A PREROUTING -p udp -m multiport --dports \$PORTS -j DNAT --to-destination \$TUNNEL_IP_KHAREJ2

# Masquerade traffic going through GRE
iptables -t nat -A POSTROUTING -o \$TUNNEL_NAME -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i \$TUNNEL_NAME -j ACCEPT
iptables -A FORWARD -o \$TUNNEL_NAME -j ACCEPT

# Apply MSS clamping if enabled
if [[ "\$MSS_VALUE" != "0" && -n "\$MSS_VALUE" ]]; then
    iptables -t mangle -A FORWARD -o \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
    iptables -t mangle -A FORWARD -i \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
fi

echo "GRE Kharej-to-Kharej tunnel $tunnel_id configured successfully (Source)"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Remove MSS clamping rules
iptables-save -t mangle | grep "\$TUNNEL_NAME" | grep TCPMSS | while read -r rule; do
    iptables -t mangle -D \${rule#-A } 2>/dev/null || true
done

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

# Remove specific iptables rules
iptables-save | grep -v "\$TUNNEL_IP_KHAREJ2" | grep -v "\$TUNNEL_NAME" | iptables-restore 2>/dev/null || true

echo "GRE tunnel $tunnel_id removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh"
    
    create_systemd_service "$tunnel_id"
    
    # Start the service
    systemctl start "gre-tunnel-${tunnel_id}.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Kharej-to-Kharej Tunnel $tunnel_id configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel ID: $tunnel_id"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel Type: Kharej1 -> Kharej2"
    echo -e "Tunnel IP (Kharej1): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej2): $tunnel_ip.2"
    echo -e "Forwarded Ports: $ports"
    if [[ "$mss_value" != "0" ]]; then
        echo -e "MSS Clamping: ${GREEN}Enabled${NC} (value: $mss_value)"
    else
        echo -e "MSS Clamping: ${YELLOW}Disabled${NC}"
    fi
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.2" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check second Kharej server.${NC}"
    fi
    
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠  IMPORTANT NEXT STEP:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Now configure Kharej2 server with:${NC}"
    echo -e "  • Menu option: ${BLUE}6${NC}"
    echo -e "  • Tunnel number: ${BLUE}$tunnel_num${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Configure Kharej-to-Kharej tunnel (Second Kharej - destination)
configure_kharej_to_kharej_dest() {
    local kharej2_ipv4=$1
    local kharej1_ipv4=$2
    local tunnel_num=$3
    local tunnel_id=$(get_tunnel_id "kharej" "$tunnel_num")
    local tunnel_name="GRE-${tunnel_id}"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num" "kharej")
    
    cleanup_tunnel "$tunnel_id"
    
    # Ask for MSS clamping
    local mss_value
    mss_value=$(ask_mss_clamping "$tunnel_name")
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-${tunnel_id}.conf" << EOF
SERVER_TYPE=kharej-destination
TUNNEL_TYPE=kharej-kharej
TUNNEL_ID=$tunnel_id
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
KHAREJ1_IP=$kharej1_ipv4
KHAREJ2_IP=$kharej2_ipv4
TUNNEL_IP_KHAREJ1=$tunnel_ip.1
TUNNEL_IP_KHAREJ2=$tunnel_ip.2
MSS_VALUE=$mss_value
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre local \$KHAREJ2_IP remote \$KHAREJ1_IP ttl 64
ip addr add \$TUNNEL_IP_KHAREJ2/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

# Disable RP filter for tunnel
if [[ -d "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME" ]]; then
    echo 0 > "/proc/sys/net/ipv4/conf/\$TUNNEL_NAME/rp_filter"
fi

# Add route for tunnel network
ip route add $tunnel_ip.0/30 dev \$TUNNEL_NAME 2>/dev/null || true

# Allow forwarding
iptables -A FORWARD -i \$TUNNEL_NAME -j ACCEPT
iptables -A FORWARD -o \$TUNNEL_NAME -j ACCEPT

# Apply MSS clamping if enabled
if [[ "\$MSS_VALUE" != "0" && -n "\$MSS_VALUE" ]]; then
    iptables -t mangle -A FORWARD -o \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
    iptables -t mangle -A FORWARD -i \$TUNNEL_NAME -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$MSS_VALUE
fi

echo "GRE Kharej-to-Kharej tunnel $tunnel_id configured successfully (Destination)"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-${tunnel_id}.conf

# Remove MSS clamping rules
iptables-save -t mangle | grep "\$TUNNEL_NAME" | grep TCPMSS | while read -r rule; do
    iptables -t mangle -D \${rule#-A } 2>/dev/null || true
done

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

echo "GRE tunnel $tunnel_id removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh"
    
    create_systemd_service "$tunnel_id"
    
    # Start the service
    systemctl start "gre-tunnel-${tunnel_id}.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Kharej-to-Kharej Tunnel $tunnel_id configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel ID: $tunnel_id"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel Type: Kharej1 -> Kharej2"
    echo -e "Tunnel IP (Kharej1): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej2): $tunnel_ip.2"
    if [[ "$mss_value" != "0" ]]; then
        echo -e "MSS Clamping: ${GREEN}Enabled${NC} (value: $mss_value)"
    else
        echo -e "MSS Clamping: ${YELLOW}Disabled${NC}"
    fi
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.1" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check first Kharej server.${NC}"
    fi
}

# Configure multiple Kharej-to-Kharej tunnels from one source
configure_kharej_multi_forward() {
    local kharej_source_ipv4=$1
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Multi-Forward Configuration${NC}"
    echo -e "${CYAN}Kharej Forwarding to Multiple Kharej${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    read -p "How many destination Kharej servers? (1-5): " num_servers
    
    if [[ ! $num_servers =~ ^[0-9]+$ ]] || [[ $num_servers -lt 1 ]] || [[ $num_servers -gt 5 ]]; then
        echo -e "${RED}Invalid number. Must be between 1-5${NC}"
        return 1
    fi
    
    for ((i=1; i<=num_servers; i++)); do
        echo -e "\n${YELLOW}--- Configuring Forward Tunnel #$i ---${NC}"
        
        read -p "Enter Destination Kharej #$i Public IPv4: " kharej_dest
        validate_ipv4 "$kharej_dest" || return 1
        
        echo -e "${YELLOW}Enter ports to forward to Kharej #$i (comma-separated)${NC}"
        echo -e "${YELLOW}Example: 443,8443,2053${NC}"
        read -p "Ports for tunnel #$i: " ports
        validate_ports "$ports" || return 1
        
        local tunnel_num=$(get_next_tunnel_number "kharej")
        configure_kharej_to_kharej_source "$kharej_source_ipv4" "$kharej_dest" "$ports" "$tunnel_num"
        
        echo -e "${GREEN}✓ Forward tunnel #$i created successfully!${NC}"
        echo -e "${MAGENTA}Remember to configure destination Kharej with tunnel number: $tunnel_num${NC}\n"
        sleep 1
    done
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All forward tunnels configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    show_all_tunnels
}

# Optimize system sysctl settings
optimize_sysctl() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}System Optimization (Sysctl)${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}This will download and run an optimized sysctl configuration${NC}"
    echo -e "${YELLOW}from: https://raw.githubusercontent.com/090ebier/iranaccess/refs/heads/main/opsysctl.sh${NC}"
    echo ""
    
    read -p "Continue with sysctl optimization? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        read -p "Press Enter to continue..."
        return 0
    fi
    
    echo -e "\n${YELLOW}Downloading and executing sysctl optimization script...${NC}\n"
    
    if command -v curl &> /dev/null; then
        bash <(curl -Ls https://raw.githubusercontent.com/090ebier/iranaccess/refs/heads/main/opsysctl.sh)
        
        if [[ $? -eq 0 ]]; then
            echo -e "\n${GREEN}✓ System optimization completed successfully!${NC}"
        else
            echo -e "\n${RED}✗ Optimization script failed or was cancelled${NC}"
        fi
    else
        echo -e "${RED}✗ curl is not installed. Please install curl first:${NC}"
        echo -e "  apt-get install curl -y   (Debian/Ubuntu)"
        echo -e "  yum install curl -y       (CentOS/RHEL)"
    fi
    
    read -p "Press Enter to continue..."
}

# Show all tunnels
show_all_tunnels() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Active GRE Tunnels${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local found=0
    
    # Show Iran-Kharej tunnels
    echo -e "\n${BLUE}━━━ Iran-Kharej Tunnels (172.16.x.x) ━━━${NC}"
    local found_iran=0
    for config_file in "$CONFIG_DIR"/tunnel-iran-*.conf; do
        if [[ -f "$config_file" ]]; then
            found=1
            found_iran=1
            source "$config_file"
            
            echo -e "\n${YELLOW}Tunnel ID: $TUNNEL_ID${NC}"
            echo -e "  Tunnel Name: $TUNNEL_NAME"
            echo -e "  Server Type: $SERVER_TYPE"
            echo -e "  Iran IP: $IRAN_IP"
            echo -e "  Kharej IP: $KHAREJ_IP"
            echo -e "  Tunnel IPs: $TUNNEL_IP_IRAN <-> $TUNNEL_IP_KHAREJ"
            [[ -n "$PORTS" ]] && echo -e "  Forwarded Ports: $PORTS"
            
            if [[ -n "$MSS_VALUE" && "$MSS_VALUE" != "0" ]]; then
                echo -e "  MSS Clamping: ${GREEN}Enabled${NC} ($MSS_VALUE)"
            else
                echo -e "  MSS Clamping: ${YELLOW}Disabled${NC}"
            fi
            
            if ip link show "$TUNNEL_NAME" &>/dev/null; then
                echo -e "  Status: ${GREEN}✓ UP${NC}"
                
                # Check RP filter
                if [[ -f "/proc/sys/net/ipv4/conf/$TUNNEL_NAME/rp_filter" ]]; then
                    local rp_value=$(cat "/proc/sys/net/ipv4/conf/$TUNNEL_NAME/rp_filter")
                    if [[ "$rp_value" == "0" ]]; then
                        echo -e "  RP Filter: ${GREEN}Disabled (0)${NC}"
                    else
                        echo -e "  RP Filter: ${YELLOW}Enabled ($rp_value)${NC}"
                    fi
                fi
                
                if systemctl is-active --quiet "gre-tunnel-$TUNNEL_ID.service"; then
                    echo -e "  Service: ${GREEN}✓ Active${NC}"
                else
                    echo -e "  Service: ${RED}✗ Inactive${NC}"
                fi
            else
                echo -e "  Status: ${RED}✗ DOWN${NC}"
            fi
        fi
    done
    
    if [[ $found_iran -eq 0 ]]; then
        echo -e "  ${YELLOW}(No Iran-Kharej tunnels configured)${NC}"
    fi
    
    # Show Kharej-Kharej tunnels
    echo -e "\n${CYAN}━━━ Kharej-Kharej Tunnels (172.17.x.x) ━━━${NC}"
    local found_kharej=0
    for config_file in "$CONFIG_DIR"/tunnel-kharej-*.conf; do
        if [[ -f "$config_file" ]]; then
            found=1
            found_kharej=1
            source "$config_file"
            
            echo -e "\n${YELLOW}Tunnel ID: $TUNNEL_ID${NC}"
            echo -e "  Tunnel Name: $TUNNEL_NAME"
            echo -e "  Server Type: $SERVER_TYPE"
            echo -e "  Kharej1 IP: $KHAREJ1_IP"
            echo -e "  Kharej2 IP: $KHAREJ2_IP"
            echo -e "  Tunnel IPs: $TUNNEL_IP_KHAREJ1 <-> $TUNNEL_IP_KHAREJ2"
            [[ -n "$PORTS" ]] && echo -e "  Forwarded Ports: $PORTS"
            
            if [[ -n "$MSS_VALUE" && "$MSS_VALUE" != "0" ]]; then
                echo -e "  MSS Clamping: ${GREEN}Enabled${NC} ($MSS_VALUE)"
            else
                echo -e "  MSS Clamping: ${YELLOW}Disabled${NC}"
            fi
            
            if ip link show "$TUNNEL_NAME" &>/dev/null; then
                echo -e "  Status: ${GREEN}✓ UP${NC}"
                
                # Check RP filter
                if [[ -f "/proc/sys/net/ipv4/conf/$TUNNEL_NAME/rp_filter" ]]; then
                    local rp_value=$(cat "/proc/sys/net/ipv4/conf/$TUNNEL_NAME/rp_filter")
                    if [[ "$rp_value" == "0" ]]; then
                        echo -e "  RP Filter: ${GREEN}Disabled (0)${NC}"
                    else
                        echo -e "  RP Filter: ${YELLOW}Enabled ($rp_value)${NC}"
                    fi
                fi
                
                if systemctl is-active --quiet "gre-tunnel-$TUNNEL_ID.service"; then
                    echo -e "  Service: ${GREEN}✓ Active${NC}"
                else
                    echo -e "  Service: ${RED}✗ Inactive${NC}"
                fi
            else
                echo -e "  Status: ${RED}✗ DOWN${NC}"
            fi
        fi
    done
    
    if [[ $found_kharej -eq 0 ]]; then
        echo -e "  ${YELLOW}(No Kharej-Kharej tunnels configured)${NC}"
    fi
    
    if [[ $found -eq 0 ]]; then
        echo -e "\n${YELLOW}No tunnels configured${NC}"
    fi
    echo ""
}

# Remove specific tunnel
remove_specific_tunnel() {
    show_all_tunnels
    
    echo -e "${YELLOW}Enter tunnel ID to remove (e.g., iran-1, kharej-1)${NC}"
    read -p "Tunnel ID (or 'back' to return): " tunnel_id
    
    if [[ "$tunnel_id" == "back" ]]; then
        return 0
    fi
    
    local config_file="$CONFIG_DIR/tunnel-${tunnel_id}.conf"
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Tunnel $tunnel_id does not exist${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "${YELLOW}Removing tunnel $tunnel_id...${NC}"
    
    # Stop and disable service
    systemctl stop "gre-tunnel-${tunnel_id}.service" 2>/dev/null || true
    systemctl disable "gre-tunnel-${tunnel_id}.service" 2>/dev/null || true
    
    # Remove files
    rm -f "$SERVICE_DIR/gre-tunnel-${tunnel_id}.service"
    rm -f "/usr/local/bin/gre-tunnel-${tunnel_id}-up.sh"
    rm -f "/usr/local/bin/gre-tunnel-${tunnel_id}-down.sh"
    rm -f "$config_file"
    
    # Cleanup network
    cleanup_tunnel "$tunnel_id"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Tunnel $tunnel_id removed successfully${NC}"
    read -p "Press Enter to continue..."
}

# Remove all tunnels
remove_all_tunnels() {
    echo -e "${RED}WARNING: This will remove ALL tunnels!${NC}"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        read -p "Press Enter to continue..."
        return 0
    fi
    
    echo -e "${YELLOW}Removing all tunnels...${NC}"
    
    for config_file in "$CONFIG_DIR"/tunnel-*.conf; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            
            systemctl stop "gre-tunnel-$TUNNEL_ID.service" 2>/dev/null || true
            systemctl disable "gre-tunnel-$TUNNEL_ID.service" 2>/dev/null || true
            rm -f "$SERVICE_DIR/gre-tunnel-$TUNNEL_ID.service"
            rm -f "/usr/local/bin/gre-tunnel-$TUNNEL_ID-up.sh"
            rm -f "/usr/local/bin/gre-tunnel-$TUNNEL_ID-down.sh"
            rm -f "$config_file"
            cleanup_tunnel "$TUNNEL_ID"
            
            echo "✓ Removed tunnel $TUNNEL_ID"
        fi
    done
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ All tunnels removed${NC}"
    read -p "Press Enter to continue..."
}

# Main Menu
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║   GRE Tunnel Manager v5.2              ║${NC}"
        echo -e "${GREEN}║   MSS + RP Filter + Sysctl Optimize    ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BLUE}Iran Server Options:${NC}"
        echo "  1) Add Single Kharej Tunnel (iran-X)"
        echo "  2) Add Multiple Kharej Tunnels (Load Balancing)"
        echo ""
        echo -e "${BLUE}Kharej Server Options (Receiving from Iran):${NC}"
        echo "  3) Configure as Kharej (Single)"
        echo ""
        echo -e "${CYAN}Kharej-to-Kharej Options:${NC}"
        echo "  4) Forward to Single Kharej (kharej-X)"
        echo "  5) Forward to Multiple Kharej (Multi-Forward)"
        echo "  6) Configure as Destination Kharej"
        echo ""
        echo -e "${MAGENTA}Management:${NC}"
        echo "  7) Show All Tunnels Status"
        echo "  8) Remove Specific Tunnel"
        echo "  9) Remove All Tunnels"
        echo " 10) Optimize System Sysctl"
        echo ""
        echo "  0) Exit"
        echo ""
        echo -e "${YELLOW}Features:${NC}"
        echo -e "  • ${GREEN}MSS Clamping:${NC} Prevent fragmentation (default: 1360)"
        echo -e "  • ${GREEN}RP Filter:${NC} Auto-disabled for tunnels"
        echo -e "  • ${GREEN}Sysctl Optimize:${NC} System-wide network tuning"
        echo ""
        read -p "Enter your choice (0-10): " choice

        case "$choice" in
            1)
                echo -e "\n${YELLOW}Configuring Iran Server (Single Tunnel)...${NC}\n"
                
                # Show existing tunnels
                list_existing_tunnels "iran"
                
                read -p "Enter Iran Server Public IPv4: " iran
                validate_ipv4 "$iran" || { read -p "Press Enter to continue..."; continue; }
                
                read -p "Enter Kharej Server Public IPv4: " kharej
                validate_ipv4 "$kharej" || { read -p "Press Enter to continue..."; continue; }
                
                echo -e "\n${YELLOW}Enter ports to forward (comma-separated, e.g., 443,8443,2053)${NC}"
                read -p "Ports: " ports
                validate_ports "$ports" || { read -p "Press Enter to continue..."; continue; }
                
                # Ask for tunnel number
                local suggested=$(get_next_tunnel_number "iran")
                echo -e "\n${YELLOW}Enter tunnel number for iran-X (suggested: $suggested)${NC}"
                read -p "Tunnel number: " tunnel_num
                
                if [[ ! $tunnel_num =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid tunnel number${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                # Check if exists
                if check_tunnel_exists "iran" "$tunnel_num"; then
                    echo -e "${RED}Tunnel iran-$tunnel_num already exists!${NC}"
                    read -p "Overwrite? (yes/no): " overwrite
                    if [[ "$overwrite" != "yes" ]]; then
                        read -p "Press Enter to continue..."
                        continue
                    fi
                fi
                
                configure_iran_single "$iran" "$kharej" "$ports" "$tunnel_num"
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "\n${YELLOW}Configuring Iran Server (Multi-Tunnel)...${NC}\n"
                read -p "Enter Iran Server Public IPv4: " iran
                validate_ipv4 "$iran" || { read -p "Press Enter to continue..."; continue; }
                
                configure_iran_multi "$iran"
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "\n${YELLOW}Configuring Kharej Server (receiving from Iran)...${NC}\n"
                
                # Show existing tunnels
                list_existing_tunnels "iran"
                
                read -p "Enter Kharej Server Public IPv4: " kharej
                validate_ipv4 "$kharej" || { read -p "Press Enter to continue..."; continue; }
                
                read -p "Enter Iran Server Public IPv4: " iran
                validate_ipv4 "$iran" || { read -p "Press Enter to continue..."; continue; }
                
                echo -e "\n${YELLOW}What tunnel number is this? (Check Iran server for iran-X)${NC}"
                read -p "Tunnel number (just the number, e.g., 1 for iran-1): " tunnel_num
                
                if [[ ! $tunnel_num =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid tunnel number${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                configure_kharej "$kharej" "$iran" "$tunnel_num"
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "\n${YELLOW}Configuring Kharej Forward (Single Destination)...${NC}\n"
                echo -e "${CYAN}This Kharej will forward traffic to another Kharej${NC}\n"
                
                # Show existing tunnels
                list_existing_tunnels "kharej"
                
                read -p "Enter This Kharej Server Public IPv4: " kharej1
                validate_ipv4 "$kharej1" || { read -p "Press Enter to continue..."; continue; }
                
                read -p "Enter Destination Kharej Server Public IPv4: " kharej2
                validate_ipv4 "$kharej2" || { read -p "Press Enter to continue..."; continue; }
                
                echo -e "\n${YELLOW}Enter ports to forward to destination (comma-separated)${NC}"
                echo -e "${YELLOW}Example: 443,8443,2053${NC}"
                read -p "Ports: " ports
                validate_ports "$ports" || { read -p "Press Enter to continue..."; continue; }
                
                # Ask for tunnel number
                local suggested=$(get_next_tunnel_number "kharej")
                echo -e "\n${YELLOW}Enter tunnel number for kharej-X (suggested: $suggested)${NC}"
                read -p "Tunnel number: " tunnel_num
                
                if [[ ! $tunnel_num =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid tunnel number${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                # Check if exists
                if check_tunnel_exists "kharej" "$tunnel_num"; then
                    echo -e "${RED}Tunnel kharej-$tunnel_num already exists!${NC}"
                    read -p "Overwrite? (yes/no): " overwrite
                    if [[ "$overwrite" != "yes" ]]; then
                        read -p "Press Enter to continue..."
                        continue
                    fi
                fi
                
                configure_kharej_to_kharej_source "$kharej1" "$kharej2" "$ports" "$tunnel_num"
                read -p "Press Enter to continue..."
                ;;
            5)
                echo -e "\n${YELLOW}Configuring Kharej Multi-Forward...${NC}\n"
                echo -e "${CYAN}This Kharej will forward to MULTIPLE destination Kharej servers${NC}\n"
                
                read -p "Enter This Kharej Server Public IPv4: " kharej_source
                validate_ipv4 "$kharej_source" || { read -p "Press Enter to continue..."; continue; }
                
                configure_kharej_multi_forward "$kharej_source"
                read -p "Press Enter to continue..."
                ;;
            6)
                echo -e "\n${YELLOW}Configuring Destination Kharej...${NC}\n"
                echo -e "${CYAN}This Kharej receives traffic from another Kharej${NC}\n"
                
                # Show existing tunnels
                list_existing_tunnels "kharej"
                
                read -p "Enter This Kharej Server Public IPv4 (destination): " kharej2
                validate_ipv4 "$kharej2" || { read -p "Press Enter to continue..."; continue; }
                
                read -p "Enter Source Kharej Server Public IPv4: " kharej1
                validate_ipv4 "$kharej1" || { read -p "Press Enter to continue..."; continue; }
                
                echo -e "\n${YELLOW}What tunnel number was used on source Kharej? (e.g., 1 for kharej-1)${NC}"
                read -p "Tunnel number: " tunnel_num
                
                if [[ ! $tunnel_num =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid tunnel number${NC}"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                configure_kharej_to_kharej_dest "$kharej2" "$kharej1" "$tunnel_num"
                read -p "Press Enter to continue..."
                ;;
            7)
                show_all_tunnels
                read -p "Press Enter to continue..."
                ;;
            8)
                remove_specific_tunnel
                ;;
            9)
                remove_all_tunnels
                ;;
            10)
                optimize_sysctl
                ;;
            0)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Start the main menu
main_menu
