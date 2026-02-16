#!/bin/bash
# ============================================================
# Apply Optimized sysctl settings for High-Traffic VPN/Tunnel Server
# ============================================================

SYSCTL_CONF="/etc/sysctl.d/99-vpn-optimization.conf"

echo "Creating $SYSCTL_CONF with optimized settings..."

cat > $SYSCTL_CONF << 'EOF'
# 1. Network Core Settings
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 65536

# 2. TCP Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 8192 262144 134217728
net.ipv4.tcp_wmem = 8192 262144 134217728
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_mem = 8388608 12582912 16777216

# 3. IP Settings
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.arp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.route.max_size = 8048576

# 4. Connection Tracking
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_buckets = 500000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 30
net.netfilter.nf_conntrack_generic_timeout = 120

# 5. UDP Optimization
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 6. Memory & Swap
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 65536

# 7. Security
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 8. Kernel
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.aio-max-nr = 1048576

# 9. IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# 10. Iran Network Special
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_probe_interval = 600
net.ipv4.tcp_no_metrics_save = 1

# 11. GRE Tunnel
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.ip_default_ttl = 64
EOF

echo "Applying sysctl settings..."
sysctl --system

echo "All settings applied successfully!"
