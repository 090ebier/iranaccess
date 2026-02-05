
#!/bin/bash

# Enhanced GRE Tunnel Configuration Script for Iran/Kharej Servers
# Version: 3.0 - Multi-Tunnel Support

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

# Get next available tunnel number
get_next_tunnel_number() {
    local max=0
    for file in "$CONFIG_DIR"/tunnel-*.conf; do
        if [[ -f "$file" ]]; then
            num=$(basename "$file" | sed 's/tunnel-\([0-9]*\).conf/\1/')
            if [[ $num -gt $max ]]; then
                max=$num
            fi
        fi
    done
    echo $((max + 1))
}

# Get next available tunnel IP
get_next_tunnel_ip() {
    local tunnel_num=$1
    # Each tunnel uses a /30 subnet: 172.16.X.0/30
    # Tunnel 1: 172.16.1.0/30 (Iran: .1, Kharej: .2)
    # Tunnel 2: 172.16.2.0/30 (Iran: .1, Kharej: .2)
    # etc.
    echo "172.16.$tunnel_num"
}

# Clean up specific tunnel
cleanup_tunnel() {
    local tunnel_num=$1
    local tunnel_name="GRE$tunnel_num"
    
    echo -e "${YELLOW}Cleaning up tunnel $tunnel_num...${NC}"
    
    # Remove tunnel interface
    if ip link show "$tunnel_name" &>/dev/null; then
        ip link set "$tunnel_name" down 2>/dev/null || true
        ip tunnel del "$tunnel_name" 2>/dev/null || true
        echo "✓ Removed tunnel interface $tunnel_name"
    fi
    
    # Remove iptables rules for this tunnel
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num")
    iptables-save | grep -v "$tunnel_ip" | grep -v "$tunnel_name" | iptables-restore 2>/dev/null || true
    echo "✓ Cleaned iptables rules for tunnel $tunnel_num"
}

# Create systemd service for specific tunnel
create_systemd_service() {
    local tunnel_num=$1
    local service_file="$SERVICE_DIR/gre-tunnel-$tunnel_num.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=GRE Tunnel Service #$tunnel_num
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/gre-tunnel-$tunnel_num-up.sh
ExecStop=/usr/local/bin/gre-tunnel-$tunnel_num-down.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "gre-tunnel-$tunnel_num.service"
    echo -e "${GREEN}✓ Systemd service created for tunnel $tunnel_num${NC}"
}

# Configure Iran Server (Single Kharej)
configure_iran_single() {
    local iran_ipv4=$1
    local kharej_ipv4=$2
    local ports=$3
    local tunnel_num=$4
    local tunnel_name="GRE$tunnel_num"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num")
    
    cleanup_tunnel "$tunnel_num"
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-$tunnel_num.conf" << EOF
SERVER_TYPE=iran
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
IRAN_IP=$iran_ipv4
KHAREJ_IP=$kharej_ipv4
PORTS=$ports
TUNNEL_IP_IRAN=$tunnel_ip.1
TUNNEL_IP_KHAREJ=$tunnel_ip.2
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-$tunnel_num-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-$tunnel_num.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre remote \$KHAREJ_IP local \$IRAN_IP ttl 64
ip addr add \$TUNNEL_IP_IRAN/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

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

echo "GRE tunnel #$tunnel_num configured successfully on Iran server"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-$tunnel_num-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-$tunnel_num.conf

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

# Remove specific iptables rules
iptables-save | grep -v "\$TUNNEL_IP_KHAREJ" | grep -v "\$TUNNEL_NAME" | iptables-restore 2>/dev/null || true

echo "GRE tunnel #$tunnel_num removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-$tunnel_num-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-$tunnel_num-down.sh"
    
    create_systemd_service "$tunnel_num"
    
    # Start the service
    systemctl start "gre-tunnel-$tunnel_num.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Tunnel #$tunnel_num configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel IP (Iran): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej): $tunnel_ip.2"
    echo -e "Forwarded Ports: $ports"
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.2" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check Kharej server.${NC}"
    fi
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
        exit 1
    fi
    
    for ((i=1; i<=num_servers; i++)); do
        echo -e "\n${YELLOW}--- Configuring Tunnel #$i ---${NC}"
        
        read -p "Enter Kharej Server #$i Public IPv4: " kharej
        validate_ipv4 "$kharej" || exit 1
        
        echo -e "${YELLOW}Enter ports to forward through tunnel #$i (comma-separated)${NC}"
        echo -e "${YELLOW}Example: 443,8443,2053${NC}"
        read -p "Ports for tunnel #$i: " ports
        validate_ports "$ports" || exit 1
        
        local tunnel_num=$(get_next_tunnel_number)
        configure_iran_single "$iran_ipv4" "$kharej" "$ports" "$tunnel_num"
        
        echo -e "${GREEN}✓ Tunnel #$i created successfully!${NC}\n"
        sleep 1
    done
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All tunnels configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    show_all_tunnels
}

# Configure Kharej Server
configure_kharej() {
    local kharej_ipv4=$1
    local iran_ipv4=$2
    local tunnel_num=$3
    local tunnel_name="GRE$tunnel_num"
    local tunnel_ip=$(get_next_tunnel_ip "$tunnel_num")
    
    cleanup_tunnel "$tunnel_num"
    
    # Save configuration
    cat > "$CONFIG_DIR/tunnel-$tunnel_num.conf" << EOF
SERVER_TYPE=kharej
TUNNEL_NUM=$tunnel_num
TUNNEL_NAME=$tunnel_name
IRAN_IP=$iran_ipv4
KHAREJ_IP=$kharej_ipv4
TUNNEL_IP_IRAN=$tunnel_ip.1
TUNNEL_IP_KHAREJ=$tunnel_ip.2
EOF

    # Create startup script
    cat > "/usr/local/bin/gre-tunnel-$tunnel_num-up.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-$tunnel_num.conf

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 > /dev/null

# Create GRE tunnel
ip tunnel add \$TUNNEL_NAME mode gre local \$KHAREJ_IP remote \$IRAN_IP ttl 64
ip addr add \$TUNNEL_IP_KHAREJ/30 dev \$TUNNEL_NAME
ip link set \$TUNNEL_NAME mtu 1420
ip link set \$TUNNEL_NAME up

# Add route for tunnel network
ip route add $tunnel_ip.0/30 dev \$TUNNEL_NAME 2>/dev/null || true

# Allow forwarding
iptables -A FORWARD -i \$TUNNEL_NAME -j ACCEPT
iptables -A FORWARD -o \$TUNNEL_NAME -j ACCEPT

echo "GRE tunnel #$tunnel_num configured successfully on Kharej server"
EOF

    # Create shutdown script
    cat > "/usr/local/bin/gre-tunnel-$tunnel_num-down.sh" << EOF
#!/bin/bash
source $CONFIG_DIR/tunnel-$tunnel_num.conf

ip link set \$TUNNEL_NAME down 2>/dev/null || true
ip tunnel del \$TUNNEL_NAME 2>/dev/null || true

echo "GRE tunnel #$tunnel_num removed"
EOF

    chmod +x "/usr/local/bin/gre-tunnel-$tunnel_num-up.sh"
    chmod +x "/usr/local/bin/gre-tunnel-$tunnel_num-down.sh"
    
    create_systemd_service "$tunnel_num"
    
    # Start the service
    systemctl start "gre-tunnel-$tunnel_num.service"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Tunnel #$tunnel_num configured successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Tunnel Name: $tunnel_name"
    echo -e "Tunnel IP (Iran): $tunnel_ip.1"
    echo -e "Tunnel IP (Kharej): $tunnel_ip.2"
    echo ""
    
    # Test tunnel
    if ping -c 2 -W 2 "$tunnel_ip.1" &>/dev/null; then
        echo -e "${GREEN}✓ Tunnel is UP and working!${NC}"
    else
        echo -e "${YELLOW}⚠ Tunnel created but ping test failed. Check Iran server.${NC}"
    fi
}

# Show all tunnels
show_all_tunnels() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Active GRE Tunnels${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local found=0
    for config_file in "$CONFIG_DIR"/tunnel-*.conf; do
        if [[ -f "$config_file" ]]; then
            found=1
            source "$config_file"
            
            echo -e "\n${BLUE}Tunnel #$TUNNEL_NUM ($TUNNEL_NAME)${NC}"
            echo -e "Server Type: ${YELLOW}$SERVER_TYPE${NC}"
            echo -e "Iran IP: $IRAN_IP"
            echo -e "Kharej IP: $KHAREJ_IP"
            echo -e "Tunnel IPs: $TUNNEL_IP_IRAN <-> $TUNNEL_IP_KHAREJ"
            [[ -n "$PORTS" ]] && echo -e "Forwarded Ports: $PORTS"
            
            if ip link show "$TUNNEL_NAME" &>/dev/null; then
                echo -e "Status: ${GREEN}✓ UP${NC}"
                if systemctl is-active --quiet "gre-tunnel-$TUNNEL_NUM.service"; then
                    echo -e "Service: ${GREEN}✓ Active${NC}"
                else
                    echo -e "Service: ${RED}✗ Inactive${NC}"
                fi
            else
                echo -e "Status: ${RED}✗ DOWN${NC}"
            fi
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}No tunnels configured${NC}"
    fi
    echo ""
}

# Remove specific tunnel
remove_specific_tunnel() {
    show_all_tunnels
    
    read -p "Enter tunnel number to remove: " tunnel_num
    
    local config_file="$CONFIG_DIR/tunnel-$tunnel_num.conf"
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Tunnel #$tunnel_num does not exist${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Removing tunnel #$tunnel_num...${NC}"
    
    # Stop and disable service
    systemctl stop "gre-tunnel-$tunnel_num.service" 2>/dev/null || true
    systemctl disable "gre-tunnel-$tunnel_num.service" 2>/dev/null || true
    
    # Remove files
    rm -f "$SERVICE_DIR/gre-tunnel-$tunnel_num.service"
    rm -f "/usr/local/bin/gre-tunnel-$tunnel_num-up.sh"
    rm -f "/usr/local/bin/gre-tunnel-$tunnel_num-down.sh"
    rm -f "$config_file"
    
    # Cleanup network
    cleanup_tunnel "$tunnel_num"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ Tunnel #$tunnel_num removed successfully${NC}"
}

# Remove all tunnels
remove_all_tunnels() {
    echo -e "${RED}WARNING: This will remove ALL tunnels!${NC}"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo -e "${YELLOW}Removing all tunnels...${NC}"
    
    for config_file in "$CONFIG_DIR"/tunnel-*.conf; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            
            systemctl stop "gre-tunnel-$TUNNEL_NUM.service" 2>/dev/null || true
            systemctl disable "gre-tunnel-$TUNNEL_NUM.service" 2>/dev/null || true
            rm -f "$SERVICE_DIR/gre-tunnel-$TUNNEL_NUM.service"
            rm -f "/usr/local/bin/gre-tunnel-$TUNNEL_NUM-up.sh"
            rm -f "/usr/local/bin/gre-tunnel-$TUNNEL_NUM-down.sh"
            rm -f "$config_file"
            cleanup_tunnel "$TUNNEL_NUM"
            
            echo "✓ Removed tunnel #$TUNNEL_NUM"
        fi
    done
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ All tunnels removed${NC}"
}

# Main Menu
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  GRE Tunnel Manager v3.0${NC}"
echo -e "${GREEN}  Multi-Tunnel Support${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Iran Server Options:"
echo "  1) Add Single Kharej Tunnel"
echo "  2) Add Multiple Kharej Tunnels (Multi-Tunnel)"
echo ""
echo "Kharej Server Options:"
echo "  3) Configure as Kharej Server"
echo ""
echo "Management:"
echo "  4) Show All Tunnels Status"
echo "  5) Remove Specific Tunnel"
echo "  6) Remove All Tunnels"
echo "  7) Exit"
echo ""
read -p "Enter your choice (1-7): " choice

case "$choice" in
    1)
        echo -e "\n${YELLOW}Configuring Iran Server (Single Tunnel)...${NC}\n"
        read -p "Enter Iran Server Public IPv4: " iran
        validate_ipv4 "$iran" || exit 1
        
        read -p "Enter Kharej Server Public IPv4: " kharej
        validate_ipv4 "$kharej" || exit 1
        
        echo -e "\n${YELLOW}Enter ports to forward (comma-separated, e.g., 443,8443,2053)${NC}"
        read -p "Ports: " ports
        validate_ports "$ports" || exit 1
        
        tunnel_num=$(get_next_tunnel_number)
        configure_iran_single "$iran" "$kharej" "$ports" "$tunnel_num"
        ;;
    2)
        echo -e "\n${YELLOW}Configuring Iran Server (Multi-Tunnel)...${NC}\n"
        read -p "Enter Iran Server Public IPv4: " iran
        validate_ipv4 "$iran" || exit 1
        
        configure_iran_multi "$iran"
        ;;
    3)
        echo -e "\n${YELLOW}Configuring Kharej Server...${NC}\n"
        read -p "Enter Kharej Server Public IPv4: " kharej
        validate_ipv4 "$kharej" || exit 1
        
        read -p "Enter Iran Server Public IPv4: " iran
        validate_ipv4 "$iran" || exit 1
        
        echo -e "\n${YELLOW}What tunnel number is this? (Check Iran server)${NC}"
        read -p "Tunnel number: " tunnel_num
        
        if [[ ! $tunnel_num =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid tunnel number${NC}"
            exit 1
        fi
        
        configure_kharej "$kharej" "$iran" "$tunnel_num"
        ;;
    4)
        show_all_tunnels
        ;;
    5)
        remove_specific_tunnel
        ;;
    6)
        remove_all_tunnels
        ;;
    7)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

exit 0
