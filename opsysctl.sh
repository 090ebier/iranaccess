#!/bin/bash

# ============================================================
# Optimized sysctl settings for 2-Core / up to 4GB RAM
# Supports: GRE, PACKET (raw socket), Rathole, Backhaul
# ============================================================

SYSCTL_CONF="/etc/sysctl.d/99-vpn-optimization.conf"

# Detect available RAM in KB
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))

echo "============================================"
echo " Tunnel Optimizer for Low-Resource Servers"
echo " CPU Cores : 2"
echo " Detected RAM : ${TOTAL_RAM_MB} MB"
echo "============================================"
echo ""

# ── Dynamic buffer calculation based on actual RAM ──────────
# Use ~25% of RAM for network buffers (max 128MB on 4GB server)
MAX_SOCK_BUF=$(( TOTAL_RAM_KB * 1024 / 4 ))
[ $MAX_SOCK_BUF -gt 134217728 ] && MAX_SOCK_BUF=134217728  # cap at 128MB
[ $MAX_SOCK_BUF -lt 33554432  ] && MAX_SOCK_BUF=33554432   # min 32MB

DEFAULT_SOCK_BUF=$(( MAX_SOCK_BUF / 4 ))

# TCP memory pages (each page = 4KB)
TCP_MEM_MIN=$(( TOTAL_RAM_KB / 4 / 4 ))      # ~6.25% RAM
TCP_MEM_PRESSURE=$(( TOTAL_RAM_KB / 2 / 4 )) # ~12.5% RAM
TCP_MEM_MAX=$(( TOTAL_RAM_KB * 3 / 4 / 4 ))  # ~18.75% RAM

echo "Creating $SYSCTL_CONF ..."

cat > $SYSCTL_CONF << EOF

# ── 1. Network Core ──────────────────────────────────────────
# Balanced for 2-core — avoid overwhelming the NIC queue
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 100000
net.core.netdev_budget = 300
net.core.netdev_budget_usecs = 5000
net.core.rmem_max = ${MAX_SOCK_BUF}
net.core.wmem_max = ${MAX_SOCK_BUF}
net.core.rmem_default = ${DEFAULT_SOCK_BUF}
net.core.wmem_default = ${DEFAULT_SOCK_BUF}
net.core.optmem_max = 65536

# ── 2. TCP Optimization ───────────────────────────────────────
# BBR + FQ is the best combo for tunnel servers under load
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 4096 131072 ${MAX_SOCK_BUF}
net.ipv4.tcp_wmem = 4096 131072 ${MAX_SOCK_BUF}
net.ipv4.tcp_mem = ${TCP_MEM_MIN} ${TCP_MEM_PRESSURE} ${TCP_MEM_MAX}
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 0
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
#net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_no_metrics_save = 1
# MTU probing — critical for GRE (avoids inner fragmentation)
net.ipv4.tcp_mtu_probing = 1
#net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_ecn = 0
# Conservative on low-RAM: keep TIME_WAIT table smaller
net.ipv4.tcp_max_tw_buckets = 720000

# ── 3. UDP (PACKET tunnel / Rathole / Backhaul) ───────────────
# Raw socket & UDP-based tunnels need decent minimum buffers
net.ipv4.udp_rmem_min = 32768
net.ipv4.udp_wmem_min = 32768

# ── 4. IP / Forwarding ───────────────────────────────────────
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.arp_filter = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.ip_local_port_range = 1024 65535
# TTL 128 — better for multi-hop tunnel chains
net.ipv4.ip_default_ttl = 128

# ── 5. GRE Specific ──────────────────────────────────────────
# Keep PMTU discovery ON to prevent GRE overhead fragmentation
net.ipv4.ip_no_pmtu_disc = 0

# ── 6. Connection Tracking ────────────────────────────────────
# 1M entries ~128MB RAM — safe ceiling for 4GB servers
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_buckets = 250000
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 20
net.netfilter.nf_conntrack_generic_timeout = 60
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120

# ── 7. Memory & Swap ──────────────────────────────────────────
# Low swappiness keeps tunnel buffers in RAM
vm.swappiness = 5
vm.dirty_ratio = 30
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 75
# Reserve enough free RAM for burst traffic spikes
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1

# ── 8. Security ───────────────────────────────────────────────
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ── 9. File Descriptors & Kernel ─────────────────────────────
# 2M fd limit — enough for Rathole/Backhaul without wasting RAM
fs.file-max = 2097152
fs.inotify.max_user_watches = 262144
fs.inotify.max_user_instances = 512
fs.aio-max-nr = 524288

# ── 10. IPv6 (Disabled) ──────────────────────────────────────
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

EOF

# ── Apply settings ────────────────────────────────────────────
echo "Applying sysctl settings..."
sysctl --system > /dev/null 2>&1
echo "✓ sysctl applied"

# ── Set conntrack hashsize via sysfs ─────────────────────────
if [ -f /sys/module/nf_conntrack/parameters/hashsize ]; then
    echo 250000 > /sys/module/nf_conntrack/parameters/hashsize
    echo "✓ nf_conntrack hashsize set to 250000"
fi

# ── Persist hashsize across reboots ──────────────────────────
MODPROBE_CONF="/etc/modprobe.d/nf_conntrack.conf"
echo "options nf_conntrack hashsize=250000" > $MODPROBE_CONF
echo "✓ hashsize persisted to $MODPROBE_CONF"

# ── Load required kernel modules ─────────────────────────────
echo "Loading kernel modules..."
for mod in ip_gre gre nf_conntrack xt_conntrack; do
    modprobe $mod 2>/dev/null && echo "  ✓ $mod" || echo "  ✗ $mod (skipped)"
done

# ── Persist modules across reboots ───────────────────────────
cat > /etc/modules-load.d/tunnel-modules.conf << 'MODULES'
ip_gre
gre
nf_conntrack
xt_conntrack
MODULES
echo "✓ Modules persisted to /etc/modules-load.d/tunnel-modules.conf"

# ── Set ulimit for current session ───────────────────────────
ulimit -n 1048576 2>/dev/null
if ! grep -q "* soft nofile 1048576" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'LIMITS'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
    echo "✓ ulimit (nofile) set to 1048576 in limits.conf"
fi
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
# ── Final summary ─────────────────────────────────────────────
echo ""
echo "============================================"
echo " ✅ Optimization Complete"
echo "============================================"
echo " RAM detected      : ${TOTAL_RAM_MB} MB"
echo " Max socket buffer : $(( MAX_SOCK_BUF / 1024 / 1024 )) MB"
echo " TCP mem range     : ${TCP_MEM_MIN} ~ ${TCP_MEM_MAX} pages"
echo " conntrack max     : 1,000,000 entries"
echo " Congestion ctrl   : BBR + FQ"
echo " MTU probing       : ON  (GRE safe)"
echo " UDP min buffer    : 32KB (PACKET/Rathole)"
echo " IPv6              : Disabled"
echo " Modules loaded    : ip_gre, gre, nf_conntrack"
echo "============================================"
echo " Reboot recommended for full effect."
echo "============================================"
