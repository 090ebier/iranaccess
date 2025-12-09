#!/bin/bash
# ============================================================
# Smart PHP Auto Tuner v6.0 (Hybrid Edition)
# Author: Abolfazl Erfani
# Features:
#  - 3 Modes: Auto / Profile / Custom
#  - Dynamic tuning based on RAM & CPU
#  - Selectable Performance Profiles
#  - Safe sed replacements
#  - PHP version selector
#  - Auto rollback on failure
#  - Colored CLI output
#  - Timezone validation
# ============================================================

set -euo pipefail

# --- Colors & symbols ---
GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"
OK="${GREEN}✓${RESET}"
FAIL="${RED}✗${RESET}"
WARN="${YELLOW}⚠️${RESET}"
SEP="-------------------------------------------"

start_time=$(date +%s)
echo -e "${CYAN}Smart PHP Auto Tuner v6.0 (Hybrid Edition)${RESET}"
echo "$SEP"

# --- Detect system resources ---
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')

echo -e "Detected CPU cores: ${CYAN}${CPU_CORES}${RESET}"
echo -e "Detected RAM: ${CYAN}${TOTAL_RAM}MB${RESET}"
echo "$SEP"

# --- Mode selection ---
echo -e "${CYAN}Select tuning mode:${RESET}"
echo -e "  1️⃣  Auto Mode        - Detect and tune automatically"
echo -e "  2️⃣  Profile Mode     - Choose Performance / Balanced / Secure"
echo -e "  3️⃣  Custom Mode      - Manually enter all values"
echo -e "  4️⃣  Backup Manager   - Restore/Delete php.ini backups"
read -p "Enter mode number [1]: " mode_choice
mode_choice=${mode_choice:-1}
echo "$SEP"


# --- Function: assign values for Auto Mode ---
auto_mode() {
  if [ "$TOTAL_RAM" -lt 2048 ]; then
      LEVEL="LOW"
      memory_limit="1024M"
      post_max_size="256M"
      upload_max_filesize="256M"
      max_execution_time="300"
      max_input_time="400"
      max_input_vars="8000"
      max_file_uploads="100"
      default_socket_timeout="180"
      session_gc_maxlifetime="14400"
  elif [ "$TOTAL_RAM" -lt 8192 ]; then
      LEVEL="MEDIUM"
      memory_limit="1536M"
      post_max_size="512M"
      upload_max_filesize="512M"
      max_execution_time="300"
      max_input_time="450"
      max_input_vars="12000"
      max_file_uploads="200"
      default_socket_timeout="240"
      session_gc_maxlifetime="21600"
  else
      LEVEL="HIGH"
      memory_limit="2048M"
      post_max_size="768M"
      upload_max_filesize="768M"
      max_execution_time="300"
      max_input_time="500"
      max_input_vars="20000"
      max_file_uploads="300"
      default_socket_timeout="300"
      session_gc_maxlifetime="28800"
  fi
  echo -e "${CYAN}Auto Mode selected:${RESET} ${LEVEL} tuning applied."
}

# --- Function: assign values for Profile Mode ---
profile_mode() {
  echo -e "${CYAN}Choose optimization profile:${RESET}"
  echo -e "  1️⃣  ${GREEN}Performance${RESET} - For high traffic / heavy sites"
  echo -e "  2️⃣  ${YELLOW}Balanced${RESET}    - Recommended for most servers"
  echo -e "  3️⃣  ${RED}Secure${RESET}        - For shared or limited servers"
  read -p "Enter profile number [2]: " profile_choice
  profile_choice=${profile_choice:-2}

  case $profile_choice in
    1)
      PROFILE_NAME="Performance"
      memory_limit="4096M"
      post_max_size="1024M"
      upload_max_filesize="1024M"
      max_execution_time="600"
      max_input_time="600"
      max_input_vars="30000"
      max_file_uploads="300"
      default_socket_timeout="300"
      session_gc_maxlifetime="43200"
      ;;
    3)
      PROFILE_NAME="Secure"
      memory_limit="512M"
      post_max_size="128M"
      upload_max_filesize="128M"
      max_execution_time="120"
      max_input_time="150"
      max_input_vars="3000"
      max_file_uploads="50"
      default_socket_timeout="90"
      session_gc_maxlifetime="7200"
      ;;
    *)
      PROFILE_NAME="Balanced"
      memory_limit="2048M"
      post_max_size="768M"
      upload_max_filesize="768M"
      max_execution_time="300"
      max_input_time="450"
      max_input_vars="12000"
      max_file_uploads="200"
      default_socket_timeout="240"
      session_gc_maxlifetime="21600"
      ;;
  esac
  echo -e "${CYAN}Profile selected:${RESET} ${PROFILE_NAME}"
}

# --- Function: Custom Mode ---
custom_mode() {
  echo -e "${CYAN}Enter your own values (press Enter for defaults).${RESET}"
  read -p "memory_limit [1024M]: " input; memory_limit=${input:-1024M}
  read -p "post_max_size [256M]: " input; post_max_size=${input:-256M}
  read -p "upload_max_filesize [256M]: " input; upload_max_filesize=${input:-256M}
  read -p "max_execution_time [300]: " input; max_execution_time=${input:-300}
  read -p "max_input_time [400]: " input; max_input_time=${input:-400}
  read -p "max_input_vars [8000]: " input; max_input_vars=${input:-8000}
  read -p "max_file_uploads [100]: " input; max_file_uploads=${input:-100}
  read -p "default_socket_timeout [180]: " input; default_socket_timeout=${input:-180}
  read -p "session.gc_maxlifetime [14400]: " input; session_gc_maxlifetime=${input:-14400}
}

# --- Backup Manager helpers ---
list_backups() {
  # prints: php_ini|backup_file|mtime_epoch
  while IFS= read -r -d '' b; do
    local ini="${b%.backup-*}"
    local mt
    mt=$(stat -c %Y "$b" 2>/dev/null || echo 0)
    printf "%s|%s|%s\n" "$ini" "$b" "$mt"
  done < <(find /usr/local -path "/usr/local/php*/lib/php.ini.backup-*" -type f -print0 2>/dev/null)
}

show_backups_pretty() {
  local data
  data="$(list_backups | sort -t'|' -k1,1 -k3,3nr || true)"
  if [ -z "$data" ]; then
    echo -e "${WARN} No backups found (php.ini.backup-*) under /usr/local/php*/lib/"
    return 1
  fi

  echo -e "${CYAN}Available backups (newest first per php.ini):${RESET}"
  echo "$data" | awk -F'|' '
    {
      ini=$1; backup=$2; ts=$3;
      cmd="date -d @" ts " +\"%F %T\"";
      cmd | getline d; close(cmd);
      printf " - %s\n    -> %s (%s)\n", ini, backup, d;
    }'
  return 0
}

normalize_ver() {
  local v="$1"
  v="${v,,}"
  v="${v//php/}"
  v="${v//./}"
  v="${v//[^0-9]/}"
  echo "$v"
}

backup_manager() {
  while true; do
    echo "$SEP"
    echo -e "${CYAN}Backup Manager:${RESET}"
    echo -e "  1) List backups"
    echo -e "  2) Restore backup (latest) for ALL versions"
    echo -e "  3) Restore backup (choose version)"
    echo -e "  4) Delete backups for ALL versions"
    echo -e "  5) Delete backups (choose version)"
    echo -e "  0) Exit"
    read -p "Select [1]: " bm
    bm=${bm:-1}

    case "$bm" in
      1)
        show_backups_pretty || true
        ;;
      2)
        echo -e "${YELLOW}Restoring latest backup for ALL versions...${RESET}"
        # For each php.ini, pick newest backup and restore it
        mapfile -t inis < <(list_backups | awk -F'|' '{print $1}' | sort -u)
        if [ ${#inis[@]} -eq 0 ]; then
          echo -e "${WARN} No backups to restore."
          continue
        fi
        for ini in "${inis[@]}"; do
          latest=$(ls -1t "${ini}.backup-"* 2>/dev/null | head -n1 || true)
          if [ -n "$latest" ] && [ -f "$latest" ]; then
            cp "$latest" "$ini"
            echo -e "${OK} Restored: ${CYAN}$ini${RESET} <- ${YELLOW}$latest${RESET}"
          fi
        done
        ;;
      3)
        show_backups_pretty || true
        read -p "Enter version (e.g. 81 / 8.1 / php81): " vin
        ver="$(normalize_ver "$vin")"
        ini="/usr/local/php${ver}/lib/php.ini"
        if [ ! -f "$ini" ]; then
          echo -e "${FAIL} php.ini not found for version ${RED}$vin${RESET} (expected: $ini)"
          continue
        fi
        latest=$(ls -1t "${ini}.backup-"* 2>/dev/null | head -n1 || true)
        if [ -z "$latest" ] || [ ! -f "$latest" ]; then
          echo -e "${WARN} No backups found for: ${CYAN}$ini${RESET}"
          continue
        fi
        cp "$latest" "$ini"
        echo -e "${OK} Restored: ${CYAN}$ini${RESET} <- ${YELLOW}$latest${RESET}"
        ;;
      4)
        echo -e "${YELLOW}Deleting ALL backups...${RESET}"
        count=$(find /usr/local -path "/usr/local/php*/lib/php.ini.backup-*" -type f 2>/dev/null | wc -l || echo 0)
        find /usr/local -path "/usr/local/php*/lib/php.ini.backup-*" -type f -delete 2>/dev/null || true
        echo -e "${OK} Deleted backups: ${CYAN}$count${RESET}"
        ;;
      5)
        show_backups_pretty || true
        read -p "Enter version (e.g. 74 / 7.4 / php74): " vin
        ver="$(normalize_ver "$vin")"
        ini="/usr/local/php${ver}/lib/php.ini"
        if [ ! -f "$ini" ]; then
          echo -e "${FAIL} php.ini not found for version ${RED}$vin${RESET} (expected: $ini)"
          continue
        fi
        count=$(ls -1 "${ini}.backup-"* 2>/dev/null | wc -l || echo 0)
        rm -f "${ini}.backup-"* 2>/dev/null || true
        echo -e "${OK} Deleted backups for ${CYAN}$ini${RESET}: ${CYAN}$count${RESET}"
        ;;
      0)
        echo -e "${CYAN}Exiting Backup Manager.${RESET}"
        return 0
        ;;
      *)
        echo -e "${WARN} Invalid option."
        ;;
    esac
  done
}

# --- Run selected mode ---
case $mode_choice in
  1) auto_mode ;;
  2) profile_mode ;;
  3) custom_mode ;;
  4) backup_manager; exit 0 ;;
  *) auto_mode ;;
esac


echo "$SEP"

# --- Timezone selection & validation ---
while true; do
  read -p "Set timezone [Asia/Tehran or UTC]: " input
  timezone=${input:-"Asia/Tehran"}
  if php -r "exit(in_array('$timezone', timezone_identifiers_list()) ? 0 : 1);" 2>/dev/null; then
    echo -e "${OK} Timezone '${CYAN}${timezone}${RESET}' is valid."
    break
  else
    echo -e "${FAIL} Invalid timezone: ${RED}${timezone}${RESET}"
  fi
done

# --- Detect PHP versions ---
echo "$SEP"
echo -e "${CYAN}Detecting installed PHP versions...${RESET}"
PHP_PATHS=($(ls -d /usr/local/php*/lib/php.ini 2>/dev/null))
if [ ${#PHP_PATHS[@]} -eq 0 ]; then
  echo -e "${FAIL} No PHP installations found under /usr/local/php*/lib/"
  exit 1
fi

for path in "${PHP_PATHS[@]}"; do
  ver=$(echo "$path" | grep -oE 'php[0-9]+' | sed 's/php//')
  echo -e "${OK} Found PHP version: ${CYAN}${ver}${RESET}"
done

# --- Select target PHP versions (smart input) ---
echo "$SEP"
echo -e "${CYAN}Which PHP versions should be updated?${RESET}"
echo -e "  - Press Enter or type 'all' for ALL detected versions"
echo -e "  - Or enter versions separated by space, e.g: 74 81 83"
echo -e "    (also accepts: 7.4 8.1 php74 php81)"
read -p "Target versions [all]: " target_input
target_input=${target_input:-all}

normalize_ver() {
  local v="$1"
  v="${v,,}"             # lowercase
  v="${v//php/}"         # remove php prefix if present
  v="${v//./}"           # remove dot (8.1 -> 81, 7.4 -> 74)
  v="${v//[^0-9]/}"      # keep digits only
  echo "$v"
}

if [[ "${target_input,,}" == "all" ]]; then
  # keep PHP_PATHS as detected (all)
  :
else
  PHP_PATHS=()
  declare -A seen=()
  missing_versions=()

  for token in $target_input; do
    ver_input="$(normalize_ver "$token")"

    # basic validation: expect 2 or 3 digits like 74 / 81 / 82 / 83 / 84 ...
    if [[ -z "$ver_input" || ! "$ver_input" =~ ^[0-9]{2,3}$ ]]; then
      echo -e "${FAIL} Invalid version token: ${RED}$token${RESET} (normalized: '${ver_input}')"
      exit 1
    fi

    # de-duplicate
    if [[ -n "${seen[$ver_input]+x}" ]]; then
      continue
    fi
    seen[$ver_input]=1

    ini="/usr/local/php${ver_input}/lib/php.ini"
    if [ -f "$ini" ]; then
      PHP_PATHS+=("$ini")
    else
      missing_versions+=("$ver_input")
    fi
  done

  if [ ${#PHP_PATHS[@]} -eq 0 ]; then
    echo -e "${FAIL} No valid target php.ini files selected."
    exit 1
  fi

  if [ ${#missing_versions[@]} -gt 0 ]; then
    echo -e "${FAIL} These PHP version(s) were not found:${RESET} ${RED}${missing_versions[*]}${RESET}"
    exit 1
  fi
fi

echo -e "${OK} Target php.ini files:"
for p in "${PHP_PATHS[@]}"; do
  echo -e "  ${CYAN}$p${RESET}"
done


# --- Rollback function ---
rollback() {
  echo -e "\n${WARN} Error detected. Rolling back changes..."
  for backup in /usr/local/php*/lib/php.ini.backup-*; do
    [ -f "$backup" ] || continue
    original="${backup%.backup-*}"
    cp "$backup" "$original"
    echo -e "${YELLOW}↩ Restored backup:${RESET} $original"
  done
  echo -e "${GREEN}Rollback complete.${RESET}"
  exit 1
}
trap rollback ERR

# --- Apply configurations ---
echo "$SEP"
echo -e "${CYAN}Applying PHP configuration updates...${RESET}"

for php_ini in "${PHP_PATHS[@]}"; do
  [ -f "$php_ini" ] || continue
  echo -e "${CYAN}Processing:${RESET} $php_ini"
  backup_file="${php_ini}.backup-$(date +%F-%H%M)"
  cp "$php_ini" "$backup_file"
  echo -e "${YELLOW}Backup created:${RESET} $backup_file"

  sed -i -E "s|^memory_limit\s*=.*|memory_limit = $memory_limit|" "$php_ini"
  sed -i -E "s|^post_max_size\s*=.*|post_max_size = $post_max_size|" "$php_ini"
  sed -i -E "s|^upload_max_filesize\s*=.*|upload_max_filesize = $upload_max_filesize|" "$php_ini"
  sed -i -E "s|^max_execution_time\s*=.*|max_execution_time = $max_execution_time|" "$php_ini"
  sed -i -E "s|^max_input_time\s*=.*|max_input_time = $max_input_time|" "$php_ini"
  sed -i -E "s|^max_input_vars\s*=.*|max_input_vars = $max_input_vars|" "$php_ini"
  sed -i -E "s|^max_file_uploads\s*=.*|max_file_uploads = $max_file_uploads|" "$php_ini"
  sed -i -E "s|^default_socket_timeout\s*=.*|default_socket_timeout = $default_socket_timeout|" "$php_ini"
  sed -i -E "s|^session.gc_maxlifetime\s*=.*|session.gc_maxlifetime = $session_gc_maxlifetime|" "$php_ini"

  if grep -q "^date.timezone" "$php_ini"; then
    sed -i -E "s|^date.timezone\s*=.*|date.timezone = \"$timezone\"|" "$php_ini"
  else
    echo "date.timezone = \"$timezone\"" >> "$php_ini"
  fi

  echo -e "${OK} Updated successfully for $php_ini"
done

# --- Restart services ---
echo "$SEP"
echo -e "${CYAN}Restarting services...${RESET}"
rollback_on_error=false

if systemctl is-active --quiet httpd || systemctl is-active --quiet nginx; then
  echo -e "${YELLOW}Detected Apache/Nginx environment.${RESET}"
  systemctl restart php-fpm* >/dev/null 2>&1 || rollback_on_error=true
  systemctl restart httpd >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || rollback_on_error=true
elif systemctl is-active --quiet lsws; then
  echo -e "${YELLOW}Detected LiteSpeed environment.${RESET}"
  pkill -9 lsws >/dev/null 2>&1 || true
  pkill -9 lsphp >/dev/null 2>&1 || true
  systemctl restart lsws >/dev/null 2>&1 || rollback_on_error=true
else
  echo -e "${WARN} Web server type not detected automatically. Please restart manually."
fi

if [ "$rollback_on_error" = true ]; then
  echo -e "${FAIL} Web server restart failed. Initiating rollback..."
  rollback
fi

end_time=$(date +%s)
duration=$((end_time - start_time))

echo "$SEP"
echo -e "${GREEN}✅ All selected PHP configurations updated successfully!${RESET}"
echo -e "${CYAN}Mode:${RESET} ${mode_choice} | ${CYAN}Execution Time:${RESET} ${duration}s"
echo "$SEP"
