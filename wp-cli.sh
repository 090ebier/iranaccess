#!/bin/bash

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1;m'

# WP-CLI Configuration
WPCLI_PATH="/tmp/wp-cli.phar"
WPCLI_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"

# Global variables
PHP_BIN=""
PHP_VERSION_ARG=""
SYSTEM_USER=""
REMAINING_ARGS=()

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print header
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}              WP-CLI Manager & Automation Tool             ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to normalize PHP version input
normalize_php_version() {
    local input=$1
    local normalized=""
    
    # Remove any "php" prefix and convert to lowercase
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/^php//')
    
    # Handle different formats: 74, 7.4, 80, 8.0, etc.
    if [[ "$input" =~ ^[0-9]{2}$ ]]; then
        # Format: 74, 80, 81, 82, 83
        normalized="${input:0:1}.${input:1:1}"
    elif [[ "$input" =~ ^[0-9]\.[0-9]$ ]]; then
        # Format: 7.4, 8.0, 8.1
        normalized="$input"
    elif [[ "$input" =~ ^[0-9]\.[0-9]{2}$ ]]; then
        # Format: 7.40, 8.10
        normalized="$input"
    else
        echo ""
        return 1
    fi
    
    echo "$normalized"
}

# Function to detect all available PHP versions
detect_php() {
    local php_paths=()
    local php_versions=()
    
    # Check for DirectAdmin
    for php_dir in /usr/local/php*/bin/php; do
        if [ -x "$php_dir" ]; then
            local version=$($php_dir -r "echo PHP_VERSION;" 2>/dev/null | cut -d. -f1,2)
            if [ -n "$version" ]; then
                php_paths+=("$php_dir")
                php_versions+=("$version")
            fi
        fi
    done
    
    # Check for cPanel
    for php_dir in /opt/cpanel/ea-php*/root/bin/php; do
        if [ -x "$php_dir" ]; then
            local version=$($php_dir -r "echo PHP_VERSION;" 2>/dev/null | cut -d. -f1,2)
            if [ -n "$version" ]; then
                php_paths+=("$php_dir")
                php_versions+=("$version")
            fi
        fi
    done
    
    # Check for system PHP
    if command -v php &> /dev/null; then
        local sys_php=$(command -v php)
        local version=$($sys_php -r "echo PHP_VERSION;" 2>/dev/null | cut -d. -f1,2)
        if [ -n "$version" ]; then
            php_paths+=("$sys_php")
            php_versions+=("$version")
        fi
    fi
    
    # Return as space-separated pairs: path1|version1 path2|version2
    for i in "${!php_paths[@]}"; do
        echo "${php_paths[$i]}|${php_versions[$i]}"
    done
}

# Function to find PHP by version
find_php_by_version() {
    local target_version=$(normalize_php_version "$1")
    
    if [ -z "$target_version" ]; then
        return 1
    fi
    
    local php_list=($(detect_php))
    
    for php_entry in "${php_list[@]}"; do
        local path="${php_entry%|*}"
        local version="${php_entry#*|}"
        
        if [ "$version" = "$target_version" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Function to get highest PHP version
get_highest_php() {
    local php_list=($(detect_php))
    local highest_path=""
    local highest_version="0.0"
    
    for php_entry in "${php_list[@]}"; do
        local path="${php_entry%|*}"
        local version="${php_entry#*|}"
        
        # Compare versions
        if [ "$(printf '%s\n' "$highest_version" "$version" | sort -V | tail -n1)" = "$version" ]; then
            highest_version="$version"
            highest_path="$path"
        fi
    done
    
    echo "$highest_path"
}

# Function to select PHP version (interactive)
select_php_version_interactive() {
    local php_list=($(detect_php))
    
    if [ ${#php_list[@]} -eq 0 ]; then
        print_message "$RED" "❌ No PHP versions found!"
        exit 1
    fi
    
    if [ ${#php_list[@]} -eq 1 ]; then
        local php_entry="${php_list[0]}"
        PHP_BIN="${php_entry%|*}"
        return
    fi
    
    print_message "$YELLOW" "📋 Available PHP versions:"
    echo ""
    
    local i=1
    declare -A menu_map
    for php_entry in "${php_list[@]}"; do
        local path="${php_entry%|*}"
        local version="${php_entry#*|}"
        echo -e "  ${GREEN}[$i]${NC} $path ${CYAN}(PHP $version)${NC}"
        menu_map[$i]="$path"
        ((i++))
    done
    
    echo ""
    echo -ne "${YELLOW}Select [1-${#php_list[@]}]: ${NC}"
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#php_list[@]}" ]; then
        PHP_BIN="${menu_map[$selection]}"
        print_message "$GREEN" "✓ PHP selected: $PHP_BIN"
    else
        print_message "$RED" "❌ Invalid selection!"
        exit 1
    fi
}

# Function to determine PHP binary
determine_php() {
    if [ -n "$PHP_VERSION_ARG" ]; then
        # User specified a version
        print_message "$YELLOW" "🔍 Looking for PHP $PHP_VERSION_ARG..."
        PHP_BIN=$(find_php_by_version "$PHP_VERSION_ARG")
        
        if [ -z "$PHP_BIN" ]; then
            print_message "$RED" "❌ PHP version $PHP_VERSION_ARG not found!"
            print_message "$YELLOW" "Available versions:"
            local php_list=($(detect_php))
            for php_entry in "${php_list[@]}"; do
                local version="${php_entry#*|}"
                echo -e "  ${CYAN}- PHP $version${NC}"
            done
            exit 1
        fi
        
        local actual_version=$($PHP_BIN -r "echo PHP_VERSION;" 2>/dev/null)
        print_message "$GREEN" "✓ Using PHP $actual_version: $PHP_BIN"
    else
        # Auto-select highest version
        PHP_BIN=$(get_highest_php)
        
        if [ -z "$PHP_BIN" ]; then
            print_message "$RED" "❌ No PHP found!"
            exit 1
        fi
        
        local version=$($PHP_BIN -r "echo PHP_VERSION;" 2>/dev/null)
        print_message "$GREEN" "✓ Auto-selected highest PHP $version: $PHP_BIN"
    fi
}

# Function to install WP-CLI
install_wpcli() {
    if [ ! -f "$WPCLI_PATH" ]; then
        print_message "$YELLOW" "⬇️  Downloading WP-CLI..."
        if curl -sS -o "$WPCLI_PATH" "$WPCLI_URL" 2>/dev/null; then
            chmod +x "$WPCLI_PATH"
            print_message "$GREEN" "✓ WP-CLI installed successfully!"
        else
            print_message "$RED" "❌ Failed to download WP-CLI!"
            exit 1
        fi
    fi
}

# Function to cleanup WP-CLI
cleanup_wpcli() {
    if [ -f "$WPCLI_PATH" ]; then
        rm -f "$WPCLI_PATH"
    fi
}

# Function to extract username from path
extract_username() {
    local current_dir=$(pwd)
    
    # Pattern 1: /home/username/domains/example.com/public_html
    if [[ "$current_dir" =~ ^/home/([^/]+)/domains/[^/]+/public_html ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Pattern 2: /home/username/public_html
    if [[ "$current_dir" =~ ^/home/([^/]+)/public_html ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Function to check if we're in public_html
check_directory() {
    local current_dir=$(pwd)
    
    if [[ ! "$current_dir" =~ public_html$ ]]; then
        print_message "$RED" "❌ Error: You must run this script from a public_html directory!"
        print_message "$YELLOW" "Expected paths:"
        print_message "$CYAN" "  - /home/username/public_html"
        print_message "$CYAN" "  - /home/username/domains/example.com/public_html"
        print_message "$YELLOW" ""
        print_message "$YELLOW" "Current path: $current_dir"
        cleanup_wpcli
        exit 1
    fi
    
    # Extract username
    SYSTEM_USER=$(extract_username)
    
    if [ -z "$SYSTEM_USER" ]; then
        print_message "$RED" "❌ Error: Could not extract username from path!"
        print_message "$YELLOW" "Current path: $current_dir"
        cleanup_wpcli
        exit 1
    fi
    
    # Verify user exists
    if ! id "$SYSTEM_USER" &>/dev/null; then
        print_message "$RED" "❌ Error: User '$SYSTEM_USER' does not exist on this system!"
        cleanup_wpcli
        exit 1
    fi
    
    print_message "$GREEN" "✓ Detected user: $SYSTEM_USER"
}

# Function to fix permissions
fix_permissions() {
    print_message "$YELLOW" "🔧 Fixing permissions and ownership..."
    
    # Fix directories to 755 (faster method)
    print_message "$CYAN" "  → Setting directories to 755..."
    find ./ -type d 2>/dev/null | xargs chmod 755 2>/dev/null
    
    # Fix files to 644 (faster method)
    print_message "$CYAN" "  → Setting files to 644..."
    find ./ -type f 2>/dev/null | xargs chmod 644 2>/dev/null
    
    # Fix wp-config.php to 600 for security
    if [ -f "wp-config.php" ]; then
        print_message "$CYAN" "  → Securing wp-config.php (600)..."
        chmod 600 wp-config.php
    fi
    
    # Change ownership to detected user
    if [ -n "$SYSTEM_USER" ]; then
        print_message "$YELLOW" "👤 Changing ownership to: $SYSTEM_USER:$SYSTEM_USER"
        chown -R "$SYSTEM_USER:$SYSTEM_USER" . 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✓ Ownership changed successfully"
        else
            print_message "$YELLOW" "⚠️  Warning: Could not change ownership (may need root/sudo)"
        fi
    fi
    
    print_message "$GREEN" "✓ Permissions fixed"
}

# Function to run WP-CLI command
run_wpcli() {
    local cmd="$@"
    print_message "$CYAN" "🚀 Executing: wp $cmd"
    echo ""
    
    if $PHP_BIN "$WPCLI_PATH" $cmd --allow-root; then
        echo ""
        print_message "$GREEN" "✓ Command executed successfully"
        fix_permissions
    else
        echo ""
        print_message "$RED" "❌ Command failed"
        return 1
    fi
}

# Function to show main menu
show_menu() {
    print_header
    
    local php_version=$($PHP_BIN -r "echo PHP_VERSION;" 2>/dev/null)
    print_message "$CYAN" "📍 Current PHP: ${GREEN}$PHP_BIN${NC} ${MAGENTA}(v$php_version)${NC}"
    print_message "$CYAN" "📁 Directory: ${GREEN}$(pwd)${NC}"
    print_message "$CYAN" "👤 System User: ${GREEN}$SYSTEM_USER${NC}"
    echo ""
    
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}  ${WHITE}${BOLD}Main Menu${NC}                                               ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[1]${NC}  Download WordPress Core                           ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[2]${NC}  Search & Replace                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[3]${NC}  Database Backup                                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[4]${NC}  Update WordPress                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[5]${NC}  Update Plugins                                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[6]${NC}  Update Themes                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[7]${NC}  Fix Permissions                                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[8]${NC}  Change PHP Version                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[9]${NC}  Run Custom Command                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${RED}[0]${NC}  Exit                                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "${CYAN}Select an option: ${NC}"
}

# Function to download WordPress core
download_core() {
    print_header
    print_message "$MAGENTA" "📥 Download WordPress Core"
    echo ""
    
    echo -ne "${YELLOW}Version (default: latest): ${NC}"
    read version
    version=${version:-latest}
    
    echo -ne "${YELLOW}Locale (default: fa_IR): ${NC}"
    read locale
    locale=${locale:-fa_IR}
    
    echo -ne "${YELLOW}Force download? (y/n): ${NC}"
    read force
    
    local cmd="core download --version=$version --locale=$locale"
    if [ "$force" = "y" ]; then
        cmd="$cmd --force"
    fi
    
    run_wpcli $cmd
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to search and replace
search_replace() {
    print_header
    print_message "$MAGENTA" "🔍 Search & Replace"
    echo ""
    
    echo -ne "${YELLOW}Old domain: ${NC}"
    read old_domain
    
    echo -ne "${YELLOW}New domain: ${NC}"
    read new_domain
    
    if [ -z "$old_domain" ] || [ -z "$new_domain" ]; then
        print_message "$RED" "❌ Domains cannot be empty!"
    else
        run_wpcli search-replace "$old_domain" "$new_domain" --skip-columns=guid
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to backup database
backup_database() {
    print_header
    print_message "$MAGENTA" "💾 Database Backup"
    echo ""
    
    local backup_file="backup-$(date +%Y%m%d-%H%M%S).sql"
    
    echo -ne "${YELLOW}Backup filename (default: $backup_file): ${NC}"
    read custom_name
    backup_file=${custom_name:-$backup_file}
    
    run_wpcli db export "$backup_file"
    
    if [ -f "$backup_file" ]; then
        print_message "$GREEN" "✓ Backup saved: $backup_file"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to update WordPress
update_core() {
    print_header
    print_message "$MAGENTA" "🔄 Update WordPress"
    echo ""
    
    run_wpcli core update
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to update plugins
update_plugins() {
    print_header
    print_message "$MAGENTA" "🔌 Update Plugins"
    echo ""
    
    run_wpcli plugin update --all
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to update themes
update_themes() {
    print_header
    print_message "$MAGENTA" "🎨 Update Themes"
    echo ""
    
    run_wpcli theme update --all
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to run custom command
custom_command() {
    print_header
    print_message "$MAGENTA" "⚡ Run Custom Command"
    echo ""
    
    echo -ne "${YELLOW}WP-CLI command (without 'wp'): ${NC}"
    read custom_cmd
    
    if [ -n "$custom_cmd" ]; then
        run_wpcli $custom_cmd
    else
        print_message "$RED" "❌ Command cannot be empty!"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Parse arguments to extract PHP version
parse_arguments() {
    PHP_VERSION_ARG=""
    REMAINING_ARGS=()
    
    for arg in "$@"; do
        # Check if argument looks like a PHP version
        # Matches: 74, 7.4, php74, php7.4, PHP74, PHP7.4
        if [[ "$arg" =~ ^[pP][hH][pP]?[0-9\.]+$ ]] || [[ "$arg" =~ ^[0-9\.]+$ ]]; then
            PHP_VERSION_ARG="$arg"
        else
            REMAINING_ARGS+=("$arg")
        fi
    done
}

# Main script logic
main() {
    # Parse arguments into global variables
    parse_arguments "$@"
    
    # Install WP-CLI first
    install_wpcli
    
    # Determine PHP binary based on whether version was specified
    if [ -n "$PHP_VERSION_ARG" ]; then
        # Version specified - use it
        determine_php
    elif [ ${#REMAINING_ARGS[@]} -eq 0 ]; then
        # No command, no version - interactive mode
        select_php_version_interactive
    else
        # Command given but no version - auto-select highest
        determine_php
    fi
    
    check_directory
    
    # Check if running with direct command
    if [ ${#REMAINING_ARGS[@]} -gt 0 ]; then
        # Direct command mode
        run_wpcli "${REMAINING_ARGS[@]}"
        cleanup_wpcli
        exit $?
    fi
    
    # Interactive menu mode
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) download_core ;;
            2) search_replace ;;
            3) backup_database ;;
            4) update_core ;;
            5) update_plugins ;;
            6) update_themes ;;
            7) 
                print_header
                fix_permissions
                echo ""
                echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
                read
                ;;
            8) select_php_version_interactive ;;
            9) custom_command ;;
            0) 
                print_message "$GREEN" "👋 Goodbye!"
                cleanup_wpcli
                exit 0
                ;;
            *) 
                print_message "$RED" "❌ Invalid option!"
                sleep 2
                ;;
        esac
    done
}

# Trap to cleanup on exit
trap cleanup_wpcli EXIT

# Run main function
main "$@"
