cat > /usr/local/bin/wp.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# URL فایل wp-cli.phar (می‌تونی بذاری روی ریپوی خودت)
WPCLI_URL="${WPCLI_URL:-https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar}"

# مسیر وردپرس: اگر داخل پروژه باشی لازم نیست؛ در غیر اینصورت با --path تنظیم میشه
WP_PATH="${WP_PATH:-}"

# محل فایل موقت: اول RAM اگر هست، بعد /tmp
TMP_BASE="/tmp"
[[ -d /dev/shm && -w /dev/shm ]] && TMP_BASE="/dev/shm"

tmpfile="$(mktemp "$TMP_BASE/wpcli.XXXXXX.phar")"
cleanup(){ rm -f "$tmpfile"; }
trap cleanup EXIT

curl -fsSL "$WPCLI_URL" -o "$tmpfile"

if [[ -n "${WP_PATH}" ]]; then
  exec php "$tmpfile" --path="$WP_PATH" "$@"
else
  exec php "$tmpfile" "$@"
fi
EOF

chmod +x /usr/local/bin/wp.sh
