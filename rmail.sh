#!/bin/bash
# by i.sharifi & e.yazdanpanah - updated 2025

green='\033[0;32m'
cyan='\033[0;36m'
red='\033[0;31m'
clear='\033[0m'

echo -e "${green}\n*** Restore Emails ***${clear}"

# -------------------------------
# Detect mail source base
# Supports:
#   - cpmove root: <root>/homedir/mail
#   - mail-only backup: <root>/mail
#   - running from inside homedir/mail or mail or deeper
# Returns: absolute path to mail base (ends with /mail)
# -------------------------------
detect_mail_base() {
  local cur
  cur="$(pwd -P)"

  while [[ "$cur" != "/" ]]; do
    # case 1: cpmove root style
    if [[ -d "$cur/homedir/mail" ]]; then
      echo "$cur/homedir/mail"
      return 0
    fi
    # case 2: mail-only extracted (contains ./mail/<domain>/...)
    if [[ -d "$cur/mail" ]]; then
      echo "$cur/mail"
      return 0
    fi
    # case 3: we are already inside .../homedir/mail OR .../mail
    if [[ "$(basename "$cur")" == "mail" ]]; then
      echo "$cur"
      return 0
    fi

    cur="$(dirname "$cur")"
  done

  return 1
}

MAIL_BASE="$(detect_mail_base)" || {
  echo -e "${red}ERROR: Could not detect mail backup base. Expected one of:${clear}"
  echo -e "${red}  - cpmove style: <root>/homedir/mail/${clear}"
  echo -e "${red}  - mail-only:    <root>/mail/${clear}"
  exit 1
}

echo -e "${cyan}Mail source detected: ${green}$MAIL_BASE${clear}"

echo -en "Enter username: "
read -r username

echo -en "Enter domain: "
read -r domain

pass2='2Ab@'

# check if user exists
if [[ ! -d "/home/$username" ]]; then
  echo -e "${red}Couldn't find username on this server. Aborting...\n${clear}"
  exit 1
fi

if [[ -z "${domain:-}" ]]; then
  echo -e "${red}ERROR: Domain is empty. Aborting...${clear}"
  exit 1
fi

if [[ -d /usr/local/directadmin ]]; then
##################################
# --- Cpanel to Directadmin --- #
##################################
  echo -e "${cyan}Control panel detected: ${green}DirectAdmin${clear}"
  echo -e "${green}*** Restoring Cpanel Emails to DirectAdmin ***${clear}"
  sleep 1

  # check email directory in backup (now based on MAIL_BASE)
  if [[ ! -d "$MAIL_BASE/$domain" ]]; then
    echo -e "${red}Email path not found in backup: $MAIL_BASE/$domain. Aborting...${clear}"
    exit 1
  fi

  cd "$MAIL_BASE/$domain" || exit 1
  DESTINATION_PATH="/home/$username/imap/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER" ]] || continue

    DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER/Maildir"

    # Generate password
    password="$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)"
    password+="$pass2"

    # Create email account
    /usr/local/directadmin/scripts/add_email.sh "$EMAIL_USER" "$domain" "$password" 1 0
    echo -e "${cyan}Email account $EMAIL_USER created.${clear}"

    mkdir -p "$DEST_EMAIL_PATH"
    cp -a "$EMAIL_USER/"* "$DEST_EMAIL_PATH/" 2>/dev/null || true

    chown -R "$username:mail" "$DEST_EMAIL_PATH"
    echo -e "${green}$EMAIL_USER restored successfully.\n${clear}"
    sleep 1
  done
  shopt -u dotglob

  echo -e "${green}*** Restore complete ***${clear}"

else
#################################
# --- DirectAdmin to Cpanel --- #
#################################
  echo -e "${cyan}Control panel detected: ${green}cPanel${clear}"
  echo -e "${green}*** Restoring DirectAdmin Emails to Cpanel ***${clear}"
  sleep 2

  # NOTE: این شاخه هنوز مثل قبل فرض می‌کنه بکاپ DA داری (./imap/$domain)
  if [[ ! -d "./imap/$domain" ]]; then
    echo -e "${red}Email path not found in backup. Aborting... ${clear}"
    exit 1
  fi

  cd "./imap/$domain" || exit 1
  DESTINATION_PATH="/home/$username/mail/$domain"

  shopt -s dotglob
  for EMAIL_USER in *; do
    [[ -d "$EMAIL_USER/Maildir" ]] || continue

    DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER"
    password="$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)"
    password+="$pass2"

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

    mkdir -p "$DEST_EMAIL_PATH"
    cp -a "$EMAIL_USER/Maildir/"* "$DEST_EMAIL_PATH/" 2>/dev/null || true

    chown -R "$username." "$DEST_EMAIL_PATH"
    echo -e "${green}$EMAIL_USER restored successfully.\n${clear}"
    sleep 1
  done
  shopt -u dotglob

  echo -e "${green}*** Restore complete ***${clear}"
fi
