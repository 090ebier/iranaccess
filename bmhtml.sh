#!/bin/bash

# Destination path
DEST="/var/www/html"

# Allowed extensions
VALID_EXTENSIONS=("tar.gz" "zip" "tar.zst" "tar" "sql" "rar")

usage() {
  echo "Usage: $0 [-c | -m]"
  echo "  -c   copy files (default)"
  echo "  -m   move files"
}

# Default action is copy
ACTION="copy"

# Parse flags
while getopts ":cmh" opt; do
  case "$opt" in
    c) ACTION="copy" ;;
    m) ACTION="move" ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "⚠️ Invalid option: -$OPTARG"
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

# Get server hostname (fallback to IP if empty)
SERVER_HOST=$(hostname -f 2>/dev/null)
if [[ -z "$SERVER_HOST" ]]; then
  SERVER_HOST=$(hostname -i)
fi

# Ask user for input
read -p "Enter file paths (separated by , or space): " INPUT

# Split input by comma or space
IFS=', ' read -ra FILES <<< "$INPUT"

for FILE in "${FILES[@]}"; do
  FILE=$(echo "$FILE" | xargs)  # trim spaces
  [[ -z "$FILE" ]] && continue

  # If only filename is provided, check in current directory
  if [[ ! "$FILE" == /* ]]; then
    FILE="$(pwd)/$FILE"
  fi

  if [[ ! -f "$FILE" ]]; then
    echo "⚠️ File '$FILE' does not exist."
    continue
  fi

  BASENAME=$(basename "$FILE")

  # Check file extension
  VALID=false
  for EXT in "${VALID_EXTENSIONS[@]}"; do
    if [[ "$BASENAME" == *.$EXT ]]; then
      VALID=true
      break
    fi
  done

  if [[ "$VALID" == false ]]; then
    echo "⚠️ File '$FILE' has an invalid extension."
    continue
  fi

  DEST_PATH="$DEST/$BASENAME"

  # Copy or Move to destination
  if [[ "$ACTION" == "move" ]]; then
    mv -f -- "$FILE" "$DEST_PATH"
  else
    cp -f -- "$FILE" "$DEST_PATH"
  fi

  # Ensure operation succeeded
  if [[ ! -f "$DEST_PATH" ]]; then
    echo "⚠️ Failed to $ACTION '$FILE' to '$DEST_PATH'"
    continue
  fi

  # Set permissions and ownership
  chmod 744 "$DEST_PATH"
  chown root:root "$DEST_PATH"

  # Print download link
  echo "✅ Download link: https://$SERVER_HOST/$BASENAME"
done
