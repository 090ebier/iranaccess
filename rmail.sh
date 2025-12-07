#!/bin/bash
# by i.sharifi & e.yazdanpanah - updated 2025
green='\033[0;32m'
cyan='\033[0;36m'
red='\033[0;31m'
clear='\033[0m'

echo -e ${green}"\n*** Restore Emails ***"${clear}
echo -e ${cyan}"\nMake sure to extract backup and run this script in its root directory."${clear}

# -------------------------------
# ONLY CHANGE: detect base paths for:
#   - cPanel backup mail source (homedir/mail OR mail)
#   - DirectAdmin backup imap source (imap)
#
# Supports running from:
#   - backup root
#   - inside homedir/mail or mail or imap (or deeper)
#   - mail-only (/root/mail) or imap-only (/root/imap)
#
# Sets:
#   WORKDIR  -> directory we cd into (some stable base)
#   MAIL_SRC -> mail base dir (ends with /mail) when present
#   IMAP_SRC -> imap base dir (ends with /imap) when present
# -------------------------------
detect_paths() {
  local cur
  cur="$(pwd -P)"

  WORKDIR=""
  MAIL_SRC=""
  IMAP_SRC=""

  while [[ "$cur" != "/" ]]; do
    # cpmove style
    if [[ -d "$cur/homedir/mail" ]]; then
      WORKDIR="$cur"
      MAIL_SRC="$cur/homedir/mail"
      # keep walking? no need
      return 0
    fi

    # mail-only root style (contains mail/)
    if [[ -d "$cur/mail" ]]; then
      WORKDIR="$cur"
      MAIL_SRC="$cur/mail"
      return 0
    fi

    # imap-only root style (contains imap/)
    if [[ -d "$cur/imap" ]]; then
      WORKDIR="$cur"
      IMAP_SRC="$cur/imap"
      return 0
    fi

    # if we are already inside a "mail" directory
    if [[ "$(basename "$cur")" == "mail" ]]; then
      WORKDIR="$cur"
      MAIL_SRC="$cur"
      return 0
    fi

    # if we are already inside an "imap" directory
    if [[ "$(basename "$cur")" == "imap" ]]; then
      WORKDIR="$cur"
      IMAP_SRC="$cur"
      return 0
    fi

    cur="$(dirname "$cur")"
  done

  return 1
}

detect_paths || {
  echo -e ${red}"Couldn't detect backup base (missing homedir/mail, mail or imap). Aborting...\n"${clear}
  exit 1
}

cd "$WORKDIR" || {
  echo -e ${red}"Couldn't access working directory. Aborting...\n"${clear}
  exit 1
}

echo -en "Enter username: "
read username;
echo -en "Enter domain: "
read domain;
pass2=2Ab@;

# check if user exists
if [ ! -d "/home/$username" ]; then
  echo -e ${red} "Couldn't find username on this server. Aborting...\n"${clear}
  exit 1
fi

if [[ -d /usr/local/directadmin ]] ; then
##################################
# --- Cpanel to Directadmin --- #
##################################
echo -e ${cyan}"Control panel detected: ${green}DirectAdmin"${clear}
echo -e ${green}"*** Restoring Cpanel Emails to DirectAdmin ***"${clear}
sleep 2

# Ensure MAIL_SRC exists for this direction
if [[ -z "$MAIL_SRC" ]]; then
  echo -e ${red}"Couldn't detect mail source path (homedir/mail or mail). Aborting..."${clear}
  exit 1
fi

# check email directory in backup
if [ ! -d "$MAIL_SRC/$domain" ]; then
  echo -e ${red}"Email path not found in backup: $MAIL_SRC/$domain. Aborting... "${clear}
  exit 1
fi

cd "$MAIL_SRC/$domain" || exit 1
DESTINATION_PATH="/home/$username/imap/$domain"

shopt -s dotglob
for EMAIL_USER in *; do
  [ -d "$EMAIL_USER" ] || continue

  DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER/Maildir"

  # Generate password
  password=$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)
  password+=$pass2

  # Create email account
  /usr/local/directadmin/scripts/add_email.sh $EMAIL_USER $domain $password 1 0
  echo -e ${cyan}"Email account $EMAIL_USER created."${clear}

  mkdir -p "$DEST_EMAIL_PATH"
  cp -a "$EMAIL_USER/"* "$DEST_EMAIL_PATH/" 2>/dev/null

  chown -R $username:mail "$DEST_EMAIL_PATH"
  echo -e ${green}"$EMAIL_USER restored successfully.\n"${clear}
  sleep 1
done
shopt -u dotglob

echo -e ${green}"*** Restore complete ***"${clear}

else
#################################
# --- DirectAdmin to Cpanel --- #
#################################
echo -e ${cyan}"Control panel detected: ${green}cPanel"${clear}
echo -e ${green}"*** Restoring DirectAdmin Emails to Cpanel ***"${clear}
sleep 2

# Ensure IMAP_SRC exists for this direction
if [[ -z "$IMAP_SRC" ]]; then
  echo -e ${red}"Couldn't detect imap source path (imap). Aborting..."${clear}
  exit 1
fi

# check email directory in backup
if [ ! -d "$IMAP_SRC/$domain" ]; then
  echo -e ${red}"Email path not found in backup: $IMAP_SRC/$domain. Aborting... "${clear}
  exit 1
fi

cd "$IMAP_SRC/$domain" || exit 1
DESTINATION_PATH="/home/$username/mail/$domain"

shopt -s dotglob
for EMAIL_USER in *; do
  [ -d "$EMAIL_USER/Maildir" ] || continue

  DEST_EMAIL_PATH="$DESTINATION_PATH/$EMAIL_USER"
  password=$(tr -dc 'A-Za-z0-9!@#$%^&*()=<>?' < /dev/urandom | head -c 12)
  password+=$pass2

  uapi --user=$username Email add_pop email=${EMAIL_USER}@${domain} password=$password | awk -v email_user="$EMAIL_USER" '
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
  cp -a "$EMAIL_USER/Maildir/"* "$DEST_EMAIL_PATH/" 2>/dev/null

  chown -R $username. "$DEST_EMAIL_PATH"
  echo -e ${green}"$EMAIL_USER restored successfully.\n"${clear}
  sleep 1
done
shopt -u dotglob

echo -e ${green}"*** Restore complete ***"${clear}

fi
