#!/usr/bin/env bash
# by i.sharifi & e.yazdanpanah - updated 2025

set -Eeuo pipefail

green=$'\033[0;32m'
cyan=$'\033[0;36m'
red=$'\033[0;31m'
clear=$'\033[0m'

printf "%s\n\n" "${green}*** Restore Emails ***${clear}"

# -------------------------------
# Detect mail source base
# Supports:
#   - cpmove root: <root>/homedir/mail
#   - mail-only backup: <root>/mail
#   - running from inside homedir/mail or mail (or deeper)
# Returns: absolute path to mail base (ends with /mail)
# -------------------------------
detect_mail_base() {
  local cur
  cur="$(pwd -P)"

  while [[ "$cur" != "/" ]]; do
    if [[ -d "$cur/homedir/mail" ]]; then
      printf "%s\n" "$cur/homedir/mail"
      return 0
    fi
    if [[ -d "$cur/mail" ]]; then
      printf "%s\n" "$cur/mail"
      return 0
    fi
    if [[ "$(basename "$cur")" == "mail" ]]; then
      printf "%s\n" "$cur"
      return 0
    fi
    cur="$(dirname "$cur")"
  done

  return 1
}

MAIL_BASE="$(detect_mail_base)" || {
  printf "%s\n" "${red}ERROR: Could not detect mail backup base (expected homedir/mail or mail).${clear}"
  exit 1
}

printf "%s\n" "${cyan}Mail source detected: ${green}${MAIL_BASE}${clear}"

read -r -p "Enter username: " username

# suffix ثابت پسورد (اگر لازم داری)
pass2='2Ab@'

if [[ ! -d "/home/$username" ]]; then
  printf "%s\n" "${red}Couldn't find username on this server. Aborting...${clear}"
  exit 1
fi

choose_domain_from_mailbase() {
  local base="$1"
  local -a domains=()
  local d choice

  while IFS= read -r -d '' d; do
    domains+=("$(basename "$d")")
  done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  if (( ${#domains[@]} > 0 )); then
    printf "%s\n" "${cyan}Available domains found:${clear}"
    for i in "${!domains[@]}"; do
      printf "  %s[%d]%s %s\n" "$green" "$((i+1))" "$clear" "${domains[$i]}"
    done

    read -r -p "Select domain by number (or press Enter to type manually): " choice

    if [[ -n "${choice:-}" && "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#domains[@]} )); then
      printf "%s\n" "${domains[$((choice-1))]}"
      return 0
    fi
  fi

  read -r -p "Enter domain: " domain_manual
  printf "%s\n" "$domain_manual"
}

domain="$(choose_domain_from_mailbase "$MAIL_BASE")"
if [[ -z "${domain:-}" ]]; then
  printf "%s\n" "${red}ERROR: Domain is empty. Aborting...${clear}"
  exit 1
fi

if [[ -d /usr/local/directadmin ]]; then
  printf "%s\n" "${cyan}Control panel detected: ${green}DirectAdmin${clear}"
  printf "%s\n" "${green}*** Restoring Cpanel Emails to DirectAdmin ***${clear}"

  if [[ ! -d "$MAIL_BASE/$domain" ]]; then
    printf "%s\n" "${red}Email path not found in backup: $MAIL_BASE/$domain${clear}"
    exit 1
  fi

  cd "$MAIL_BASE/$domain"
  DESTINATION_PATH="/home/$username/imap/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER" ]] || continue

    DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER/Maildir"

    # پسورد مطمئن و ساده:
    # 12 کاراکتر + suffix
    password="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)${pass2}"

    /usr/local/directadmin/scripts/add_email.sh "$EMAIL_USER" "$domain" "$password" 1 0
    printf "%s\n" "${cyan}Email account ${EMAIL_USER} created.${clear}"

    mkdir -p "$DEST_EMAIL_PATH"
    cp -a "$EMAIL_USER/"* "$DEST_EMAIL_PATH/" 2>/dev/null || true

    chown -R "$username:mail" "$DEST_EMAIL_PATH"
    printf "%s\n\n" "${green}${EMAIL_USER} restored successfully.${clear}"
  done
  shopt -u dotglob

  printf "%s\n" "${green}*** Restore complete ***${clear}"

else
  printf "%s\n" "${cyan}Control panel detected: ${green}cPanel${clear}"
  printf "%s\n" "${green}*** Restoring DirectAdmin Emails to Cpanel ***${clear}"
  printf "%s\n" "${red}NOTE: This branch still expects a DA backup structure (./imap/<domain>).${clear}"
  exit 1
fi
