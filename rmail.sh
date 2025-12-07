#!/usr/bin/env bash
set -Eeuo pipefail

green=$'\033[0;32m'
cyan=$'\033[0;36m'
red=$'\033[0;31m'
clear=$'\033[0m'

printf "%s\n\n" "${green}*** Restore Emails ***${clear}"

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
  printf "%s\n" "${red}ERROR: Could not detect mail base.${clear}"
  exit 1
}

printf "%s\n" "${cyan}Mail source detected:${green} $MAIL_BASE ${clear}"

read -r -p "Enter username: " username

pass2='2Ab@'

if [[ ! -d "/home/$username" ]]; then
  printf "%s\n" "${red}User not found. Aborting.${clear}"
  exit 1
fi

choose_domain() {
  local base="$1" d
  local -a domains=()

  while IFS= read -r -d '' d; do
    domains+=("$(basename "$d")")
  done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0)

  if (( ${#domains[@]} > 0 )); then
    printf "%s\n" "${cyan}Domains detected:${clear}"
    for i in "${!domains[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${domains[$i]}"
    done

    read -r -p "Select number or Enter to type manually: " ch

    if [[ "$ch" =~ ^[0-9]+$ ]] && (( ch>=1 && ch<=${#domains[@]} )); then
      printf "%s\n" "${domains[$((ch-1))]}"
      return 0
    fi
  fi

  read -r -p "Enter domain: " x
  printf "%s\n" "$x"
}

domain="$(choose_domain "$MAIL_BASE")"
[[ -z "$domain" ]] && { printf "%s\n" "${red}Domain empty${clear}"; exit 1; }

if [[ -d /usr/local/directadmin ]]; then

  printf "%s\n" "${cyan}DirectAdmin detected.${clear}"
  printf "%s\n" "${green}Restoring...${clear}"

  [[ ! -d "$MAIL_BASE/$domain" ]] && {
    printf "%s\n" "${red}Domain folder not found in backup${clear}"
    exit 1
  }

  cd "$MAIL_BASE/$domain"

  DEST="/home/$username/imap/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER" ]] || continue

    PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)${pass2}"
    DEST_USER="$DEST/$EMAIL_USER/Maildir"

    /usr/local/directadmin/scripts/add_email.sh "$EMAIL_USER" "$domain" "$PASS" 1 0

    mkdir -p "$DEST_USER"
    cp -a "$EMAIL_USER/"* "$DEST_USER/" || true
    chown -R "$username:mail" "$DEST_USER"

    printf "%s\n" "${green}$EMAIL_USER restored${clear}"
  done
  shopt -u dotglob

  printf "%s\n" "${green}DONE.${clear}"
fi
