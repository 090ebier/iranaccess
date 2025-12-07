#!/bin/bash
# by i.sharifi & e.yazdanpanah - updated 2025
green='\033[0;32m'
cyan='\033[0;36m'
red='\033[0;31m'
clear='\033[0m'

echo -e ${green}"\n*** Restore Emails ***"${clear}
echo -e ${cyan}"\nMake sure to extract backup and run this script in its root directory."${clear}

# -------------------------------
# ONLY ADD: detect backup root (directory that contains "homedir/")
# This allows running script from inside homedir/mail (or deeper)
# -------------------------------
detect_backup_root() {
  local cur
  cur="$(pwd -P)"
  while [[ "$cur" != "/" ]]; do
    if [[ -d "$cur/homedir" ]]; then
      echo "$cur"
      return 0
    fi
    cur="$(dirname "$cur")"
  done
  return 1
}

BACKUP_ROOT="$(detect_backup_root)" || {
  echo -e ${red}"Couldn't detect backup root (missing homedir/). Aborting...\n"${clear}
  exit 1
}

cd "$BACKUP_ROOT" || {
  echo -e ${red}"Couldn't access backup root. Aborting...\n"${clear}
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

# check email directory in backup
if [ ! -d "./homedir/mail/$domain" ]; then
  echo -e ${red}"Email path not found in backup. Aborting... "${clear}
  exit 1
fi

cd "./homedir/mail/$domain" || exit 1
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

if [ ! -d "./imap/$domain" ]; then
  echo -e ${red}"Email path not found in backup. Aborting... "${clear}
  exit 1
fi

cd "./imap/$domain" || exit 1
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
