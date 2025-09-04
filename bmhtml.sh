#!/bin/bash

# Destination path
DEST="/var/www/html"

# Allowed extensions
VALID_EXTENSIONS=("tar.gz" "zip" "tar.zst" "tar")

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

    # Copy to destination
    cp "$FILE" "$DEST/$BASENAME"

    # Set permissions and ownership
    chmod 744 "$DEST/$BASENAME"
    chown root:root "$DEST/$BASENAME"

    # Print download link
    echo "✅ Download link: https://$SERVER_HOST/$BASENAME"
done
