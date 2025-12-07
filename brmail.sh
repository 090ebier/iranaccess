#!/bin/bash
# mailmgr.sh - modular mail backup/restore for cPanel <-> DirectAdmin
# 2025

green='\033[0;32m'
cyan='\033[0;36m'
red='\033[0;31m'
clear='\033[0m'

WWW_DIR="/var/www/html"

die() { echo -e "${red}$*${clear}"; exit 1; }
info() { echo -e "${cyan}$*${clear}"; }
ok() { echo -e "${green}$*${clear}"; }

need_root() { [[ $EUID -eq 0 ]] || die "Run as root."; }

detect_panel() {
  if [[ -d /usr/local/directadmin ]]; then
    echo "directadmin"
  elif [[ -d /usr/local/cpanel ]]; then
    echo "cpanel"
  else
    echo "unknown"
  fi
}

ensure_www_dir() { [[ -d "$WWW_DIR" ]] || die "Web directory not found: $WWW_DIR"; }
safe_username() { [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid username: $1"; }

# -------------------------------
# Global tmp cleanup
# -------------------------------
TMP_DIRS=()
cleanup_tmp() { for d in "${TMP_DIRS[@]}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup_tmp EXIT INT TERM

# --------- BACKUP (Option 1) ----------
backup_mail() {
  local panel username src out fqdn url

  panel="$(detect_panel)"
  [[ "$panel" != "unknown" ]] || die "Control panel not detected (DirectAdmin/cPanel)."

  read -r -p "Enter source username to backup: " username
  safe_username "$username"
  [[ -d "/home/$username" ]] || die "User home not found: /home/$username"

  if [[ "$panel" == "directadmin" ]]; then
    src="/home/$username/imap"
  else
    src="/home/$username/mail"
  fi
  [[ -d "$src" ]] || die "Mail directory not found: $src"

  ensure_www_dir
  out="${WWW_DIR}/mail-${username}.tar.gz"

  info "Panel: $panel"
  info "Source: $src"
  info "Creating: $out"

  tar -C "/home/$username" -czf "$out" "$(basename "$src")" || die "tar failed"
  chmod 744 "$out" || die "chmod failed"

  fqdn="$(hostname -f 2>/dev/null || hostname)"
  url="http://${fqdn}/$(basename "$out")"

  ok "Backup created successfully."
  echo -e "${green}Download:${clear} $url"
}

# --------- PATH DETECTION FOR RESTORE ----------
detect_mail_or_imap_base() {
  local cur mail_src="" imap_src=""
  cur="$(pwd -P)"

  while [[ "$cur" != "/" ]]; do
    [[ -d "$cur/homedir/mail" ]] && mail_src="$cur/homedir/mail"
    [[ -d "$cur/mail" ]] && mail_src="$cur/mail"
    [[ "$(basename "$cur")" == "mail" ]] && mail_src="$cur"

    [[ -d "$cur/imap" ]] && imap_src="$cur/imap"
    [[ "$(basename "$cur")" == "imap" ]] && imap_src="$cur"

    if [[ -n "$mail_src" || -n "$imap_src" ]]; then
      echo "MAIL_SRC=$mail_src IMAP_SRC=$imap_src"
      return 0
    fi
    cur="$(dirname "$cur")"
  done

  echo "MAIL_SRC= IMAP_SRC="
  return 0
}

# --------- RESTORE HELPERS ----------
restore_cpanel_to_directadmin() {
  local username domain pass2 mail_src
  username="$1"; domain="$2"; mail_src="$3"
  pass2='2Ab@'

  [[ -n "$mail_src" ]] || die "MAIL source not detected."
  [[ -d "$mail_src/$domain" ]] || die "Mail path not found: $mail_src/$domain"
  cd "$mail_src/$domain" || die "cd failed"

  local DESTINATION_PATH="/home/$username/imap/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER" ]] || continue

    local DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER/Maildir"

    # Create mailbox
    local password
    password=$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)
    password+=$pass2
    /usr/local/directadmin/scripts/add_email.sh "$EMAIL_USER" "$domain" "$password" 1 0
    echo -e "${cyan}Email account $EMAIL_USER created.${clear}"

    # Merge copy: copy whole Maildir tree into destination (no glob issues)
    mkdir -p "$DEST_EMAIL_PATH"
    cp -a "$EMAIL_USER/." "$DEST_EMAIL_PATH/" 2>/dev/null || true

    chown -R "$username:mail" "$DESTINATION_PATH/$EMAIL_USER" 2>/dev/null || true
    echo -e "${green}$EMAIL_USER restored successfully.\n${clear}"
    sleep 1
  done
  shopt -u dotglob
}

restore_directadmin_to_cpanel() {
  local username domain pass2 imap_src
  username="$1"; domain="$2"; imap_src="$3"
  pass2='2Ab@'

  [[ -n "$imap_src" ]] || die "IMAP source not detected."
  [[ -d "$imap_src/$domain" ]] || die "IMAP path not found: $imap_src/$domain"
  cd "$imap_src/$domain" || die "cd failed"

  local DESTINATION_PATH="/home/$username/mail/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER/Maildir" ]] || continue

    local DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER"

    # Create mailbox
    local password
    password=$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)
    password+=$pass2

    uapi --user="$username" Email add_pop email="${EMAIL_USER}@${domain}" password="$password" | awk -v email_user="$EMAIL_USER" '
    /errors/ {
        if ($2 == "~") {
            print "\033[32mEmail " email_user " created successfully.\033[0m"
        } else {
            print "\033[31m" $0 "\033[0m"
            getline
            print "\033[31m" $0 "\033[0m"
        }
    }'

    # Merge copy: copy Maildir contents into cPanel mailbox directory
    mkdir -p "$DEST_EMAIL_PATH"
    cp -a "$EMAIL_USER/Maildir/." "$DEST_EMAIL_PATH/" 2>/dev/null || true

    chown -R "$username." "$DEST_EMAIL_PATH" 2>/dev/null || true
    echo -e "${green}$EMAIL_USER restored successfully.\n${clear}"
    sleep 1
  done
  shopt -u dotglob
}

# --------- RESTORE (Option 2) ----------
restore_mail() {
  local panel username domain archive workdir basevars MAIL_SRC IMAP_SRC

  panel="$(detect_panel)"
  [[ "$panel" != "unknown" ]] || die "Control panel not detected (DirectAdmin/cPanel)."

  read -r -p "Enter destination username (on this server): " username
  safe_username "$username"
  [[ -d "/home/$username" ]] || die "User home not found: /home/$username"

  read -r -p "Enter domain: " domain
  [[ -n "$domain" ]] || die "Domain is empty."

  read -r -p "Enter path to mail-*.tar.gz (leave empty if script is in same dir): " archive
  if [[ -z "${archive:-}" ]]; then
    archive="$(ls -1 mail-*.tar.gz 2>/dev/null | head -n1 || true)"
    [[ -n "$archive" ]] || archive="$(ls -1 *.tar.gz 2>/dev/null | head -n1 || true)"
    [[ -n "$archive" ]] || die "No tar.gz found in current directory. Provide full path."
  fi
  [[ -f "$archive" ]] || die "Archive not found: $archive"

  workdir="$(mktemp -d /tmp/mailrestore.XXXXXX)"
  TMP_DIRS+=("$workdir")

  info "Extracting to: $workdir"
  tar -xzf "$archive" -C "$workdir" || die "Extract failed"
  cd "$workdir" || die "cd failed"

  basevars="$(detect_mail_or_imap_base)"
  eval "$basevars" 2>/dev/null || true

  [[ -z "${MAIL_SRC:-}" && -d "$workdir/homedir/mail" ]] && MAIL_SRC="$workdir/homedir/mail"
  [[ -z "${MAIL_SRC:-}" && -d "$workdir/mail" ]] && MAIL_SRC="$workdir/mail"
  [[ -z "${IMAP_SRC:-}" && -d "$workdir/imap" ]] && IMAP_SRC="$workdir/imap"

  info "Panel: $panel"
  info "Detected MAIL_SRC: ${MAIL_SRC:-none}"
  info "Detected IMAP_SRC: ${IMAP_SRC:-none}"

  if [[ "$panel" == "directadmin" ]]; then
    [[ -n "${MAIL_SRC:-}" ]] || die "Could not find 'mail' source inside archive."
    ok "*** Restoring Cpanel Emails to DirectAdmin ***"
    restore_cpanel_to_directadmin "$username" "$domain" "$MAIL_SRC"
    ok "*** Restore complete ***"
  else
    [[ -n "${IMAP_SRC:-}" ]] || die "Could not find 'imap' source inside archive."
    ok "*** Restoring DirectAdmin Emails to cPanel ***"
    restore_directadmin_to_cpanel "$username" "$domain" "$IMAP_SRC"
    ok "*** Restore complete ***"
  fi
}

# --------- MAIN MENU ----------
main() {
  need_root
  info "Detected panel: $(detect_panel)"
  echo
  echo "1) Backup emails of a user (tar.gz to /var/www/html and show link)"
  echo "2) Restore emails from a tar.gz (extract then run restore logic)"
  echo
  read -r -p "Select option [1-2]: " opt

  case "$opt" in
    1) backup_mail ;;
    2) restore_mail ;;
    *) die "Invalid option." ;;
  esac
}

main
