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
        print_message "$YELLOW" "⚠️  WARNING: You are not in a public_html directory!"
        print_message "$CYAN" "Current path: $current_dir"
        print_message "$CYAN" "Expected paths:"
        print_message "$CYAN" "  - /home/username/public_html"
        print_message "$CYAN" "  - /home/username/domains/example.com/public_html"
        echo ""
        echo -ne "${YELLOW}Do you want to continue anyway? (y/n): ${NC}"
        read confirm
        
        if [ "$confirm" != "y" ]; then
            print_message "$RED" "Operation cancelled"
            cleanup_wpcli
            exit 1
        fi
        
        print_message "$GREEN" "✓ Continuing in current directory..."
    fi
    
    # Extract username
    SYSTEM_USER=$(extract_username)
    
    if [ -z "$SYSTEM_USER" ]; then
        print_message "$YELLOW" "⚠️  Could not extract username from path"
        print_message "$CYAN" "Current path: $current_dir"
        echo ""
        echo -ne "${YELLOW}Enter username manually (or press Enter to skip ownership fix): ${NC}"
        read manual_user
        
        if [ -n "$manual_user" ]; then
            if id "$manual_user" &>/dev/null; then
                SYSTEM_USER="$manual_user"
                print_message "$GREEN" "✓ Using user: $SYSTEM_USER"
            else
                print_message "$RED" "❌ User '$manual_user' does not exist!"
                print_message "$YELLOW" "⚠️  Ownership will not be changed"
            fi
        else
            print_message "$YELLOW" "⚠️  Skipping ownership fix"
        fi
    else
        # Verify user exists
        if ! id "$SYSTEM_USER" &>/dev/null; then
            print_message "$RED" "❌ Warning: User '$SYSTEM_USER' does not exist on this system!"
            print_message "$YELLOW" "⚠️  Ownership will not be changed"
            SYSTEM_USER=""
        else
            print_message "$GREEN" "✓ Detected user: $SYSTEM_USER"
        fi
    fi
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
    local fix_perms="${FIX_PERMISSIONS:-false}"
    local use_force="${USE_FORCE:-false}"
    
    # Remove --allow-root if user already added it
    cmd="${cmd// --allow-root/}"
    
    # Add --force for specific operations if flag is set
    if [ "$use_force" = "true" ] && [[ ! "$cmd" =~ --force ]]; then
        cmd="$cmd --force"
    fi
    
    print_message "$CYAN" "🚀 Executing: wp $cmd --allow-root"
    echo ""
    
    if $PHP_BIN "$WPCLI_PATH" $cmd --allow-root; then
        echo ""
        print_message "$GREEN" "✓ Command executed successfully"
        
        # Only fix permissions if flag is set
        if [ "$fix_perms" = "true" ]; then
            fix_permissions
        fi
        return 0
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
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}WordPress Core${NC}                                          ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[1]${NC}  Download WordPress Core                           ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[2]${NC}  Update WordPress Core                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[3]${NC}  Check Core Version                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}Database Management${NC}                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[4]${NC}  Database Backup (Export)                          ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[5]${NC}  Database Restore (Import)                         ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[6]${NC}  Search & Replace in Database                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[7]${NC}  Optimize Database                                 ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[8]${NC}  Database Size & Info                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}Plugins Management${NC}                                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[9]${NC}  List All Plugins                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[10]${NC} Update All Plugins                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[11]${NC} Install Plugin                                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[12]${NC} Activate/Deactivate Plugin                        ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[13]${NC} Delete Plugin                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}Themes Management${NC}                                       ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[14]${NC} List All Themes                                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[15]${NC} Update All Themes                                 ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[16]${NC} Install Theme                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[17]${NC} Activate Theme                                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}User Management${NC}                                         ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[18]${NC} List All Users                                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[19]${NC} Create New User                                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[20]${NC} Change User Password                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[21]${NC} Delete User                                       ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}Cache & Performance${NC}                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[22]${NC} Flush All Cache                                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[23]${NC} Regenerate Thumbnails                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[24]${NC} Clear Transients                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}Maintenance & Security${NC}                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[25]${NC} Enable/Disable Maintenance Mode                   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[26]${NC} Fix Permissions & Ownership                       ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[27]${NC} Verify Core Checksums                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[28]${NC} Reset Admin Password                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}  ${CYAN}${BOLD}System & Tools${NC}                                          ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[29]${NC} Site Info & System Status                         ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[30]${NC} Change PHP Version                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}[31]${NC} Run Custom WP-CLI Command                         ${YELLOW}│${NC}"
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
    
    local cmd="core download --version=$version --locale=$locale"
    
    FIX_PERMISSIONS=true USE_FORCE=true run_wpcli $cmd
    
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
    
    FIX_PERMISSIONS=true USE_FORCE=true run_wpcli core update
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to update plugins
update_plugins() {
    print_header
    print_message "$MAGENTA" "🔌 Update Plugins"
    echo ""
    
    FIX_PERMISSIONS=true USE_FORCE=true run_wpcli plugin update --all
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to update themes
update_themes() {
    print_header
    print_message "$MAGENTA" "🎨 Update Themes"
    echo ""
    
    FIX_PERMISSIONS=true USE_FORCE=true run_wpcli theme update --all
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to check core version
check_core_version() {
    print_header
    print_message "$MAGENTA" "📋 WordPress Core Version"
    echo ""
    
    run_wpcli core version --extra
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to restore database
restore_database() {
    print_header
    print_message "$MAGENTA" "📥 Database Restore (Import)"
    echo ""
    
    print_message "$YELLOW" "Available SQL files in current directory:"
    ls -lh *.sql 2>/dev/null || print_message "$RED" "No SQL files found!"
    echo ""
    
    echo -ne "${YELLOW}SQL filename to import: ${NC}"
    read sql_file
    
    if [ ! -f "$sql_file" ]; then
        print_message "$RED" "❌ File not found: $sql_file"
    else
        print_message "$RED" "⚠️  WARNING: This will overwrite your current database!"
        echo -ne "${YELLOW}Are you sure? (yes/no): ${NC}"
        read confirm
        
        if [ "$confirm" = "yes" ]; then
            run_wpcli db import "$sql_file"
        else
            print_message "$YELLOW" "Import cancelled"
        fi
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to optimize database
optimize_database() {
    print_header
    print_message "$MAGENTA" "⚡ Optimize Database"
    echo ""
    
    run_wpcli db optimize
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to show database info
database_info() {
    print_header
    print_message "$MAGENTA" "📊 Database Size & Info"
    echo ""
    
    run_wpcli db size --tables
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to list plugins
list_plugins() {
    print_header
    print_message "$MAGENTA" "🔌 All Plugins"
    echo ""
    
    run_wpcli plugin list
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to install plugin
install_plugin() {
    print_header
    print_message "$MAGENTA" "⬇️  Install Plugin"
    echo ""
    
    echo -ne "${YELLOW}Plugin slug (e.g., contact-form-7): ${NC}"
    read plugin_slug
    
    if [ -z "$plugin_slug" ]; then
        print_message "$RED" "❌ Plugin slug cannot be empty!"
    else
        echo -ne "${YELLOW}Activate after install? (y/n): ${NC}"
        read activate
        
        local cmd="plugin install $plugin_slug"
        if [ "$activate" = "y" ]; then
            cmd="$cmd --activate"
        fi
        
        FIX_PERMISSIONS=true USE_FORCE=true run_wpcli $cmd
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to activate/deactivate plugin
toggle_plugin() {
    print_header
    print_message "$MAGENTA" "🔄 Activate/Deactivate Plugin"
    echo ""
    
    run_wpcli plugin list
    echo ""
    
    echo -ne "${YELLOW}Plugin slug: ${NC}"
    read plugin_slug
    
    echo -ne "${YELLOW}Action (activate/deactivate): ${NC}"
    read action
    
    if [ -z "$plugin_slug" ] || [ -z "$action" ]; then
        print_message "$RED" "❌ Plugin slug and action are required!"
    else
        run_wpcli plugin $action $plugin_slug
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to delete plugin
delete_plugin() {
    print_header
    print_message "$MAGENTA" "🗑️  Delete Plugin"
    echo ""
    
    run_wpcli plugin list
    echo ""
    
    echo -ne "${YELLOW}Plugin slug to delete: ${NC}"
    read plugin_slug
    
    if [ -z "$plugin_slug" ]; then
        print_message "$RED" "❌ Plugin slug cannot be empty!"
    else
        print_message "$RED" "⚠️  WARNING: This will permanently delete the plugin!"
        echo -ne "${YELLOW}Are you sure? (yes/no): ${NC}"
        read confirm
        
        if [ "$confirm" = "yes" ]; then
            FIX_PERMISSIONS=true run_wpcli plugin delete $plugin_slug
        else
            print_message "$YELLOW" "Deletion cancelled"
        fi
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to list themes
list_themes() {
    print_header
    print_message "$MAGENTA" "🎨 All Themes"
    echo ""
    
    run_wpcli theme list
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to install theme
install_theme() {
    print_header
    print_message "$MAGENTA" "⬇️  Install Theme"
    echo ""
    
    echo -ne "${YELLOW}Theme slug (e.g., twentytwentyfour): ${NC}"
    read theme_slug
    
    if [ -z "$theme_slug" ]; then
        print_message "$RED" "❌ Theme slug cannot be empty!"
    else
        echo -ne "${YELLOW}Activate after install? (y/n): ${NC}"
        read activate
        
        local cmd="theme install $theme_slug"
        if [ "$activate" = "y" ]; then
            cmd="$cmd --activate"
        fi
        
        FIX_PERMISSIONS=true USE_FORCE=true run_wpcli $cmd
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to activate theme
activate_theme() {
    print_header
    print_message "$MAGENTA" "✨ Activate Theme"
    echo ""
    
    run_wpcli theme list
    echo ""
    
    echo -ne "${YELLOW}Theme slug to activate: ${NC}"
    read theme_slug
    
    if [ -z "$theme_slug" ]; then
        print_message "$RED" "❌ Theme slug cannot be empty!"
    else
        run_wpcli theme activate $theme_slug
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to list users
list_users() {
    print_header
    print_message "$MAGENTA" "👥 All Users"
    echo ""
    
    run_wpcli user list
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to create user
create_user() {
    print_header
    print_message "$MAGENTA" "➕ Create New User"
    echo ""
    
    echo -ne "${YELLOW}Username: ${NC}"
    read username
    
    echo -ne "${YELLOW}Email: ${NC}"
    read email
    
    echo -ne "${YELLOW}Role (administrator/editor/author/contributor/subscriber): ${NC}"
    read role
    role=${role:-subscriber}
    
    if [ -z "$username" ] || [ -z "$email" ]; then
        print_message "$RED" "❌ Username and email are required!"
    else
        run_wpcli user create "$username" "$email" --role="$role"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to change user password
change_user_password() {
    print_header
    print_message "$MAGENTA" "🔐 Change User Password"
    echo ""
    
    run_wpcli user list
    echo ""
    
    echo -ne "${YELLOW}Username or User ID: ${NC}"
    read user_id
    
    echo -ne "${YELLOW}New password (leave empty to generate): ${NC}"
    read -s new_password
    echo ""
    
    if [ -z "$user_id" ]; then
        print_message "$RED" "❌ User ID/username is required!"
    else
        if [ -z "$new_password" ]; then
            run_wpcli user update "$user_id" --prompt=user_pass
        else
            run_wpcli user update "$user_id" --user_pass="$new_password"
        fi
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to delete user
delete_user() {
    print_header
    print_message "$MAGENTA" "🗑️  Delete User"
    echo ""
    
    run_wpcli user list
    echo ""
    
    echo -ne "${YELLOW}Username or User ID to delete: ${NC}"
    read user_id
    
    if [ -z "$user_id" ]; then
        print_message "$RED" "❌ User ID/username is required!"
    else
        print_message "$RED" "⚠️  WARNING: This will permanently delete the user!"
        echo -ne "${YELLOW}Reassign posts to user ID (or leave empty): ${NC}"
        read reassign_id
        
        echo -ne "${YELLOW}Confirm deletion? (yes/no): ${NC}"
        read confirm
        
        if [ "$confirm" = "yes" ]; then
            if [ -n "$reassign_id" ]; then
                run_wpcli user delete "$user_id" --reassign="$reassign_id"
            else
                run_wpcli user delete "$user_id" --yes
            fi
        else
            print_message "$YELLOW" "Deletion cancelled"
        fi
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to flush cache
flush_cache() {
    print_header
    print_message "$MAGENTA" "🧹 Flush All Cache"
    echo ""
    
    print_message "$CYAN" "Flushing object cache..."
    run_wpcli cache flush
    
    echo ""
    print_message "$CYAN" "Flushing rewrite rules..."
    run_wpcli rewrite flush
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to regenerate thumbnails
regenerate_thumbnails() {
    print_header
    print_message "$MAGENTA" "🖼️  Regenerate Thumbnails"
    echo ""
    
    print_message "$YELLOW" "This may take a while for sites with many images..."
    echo -ne "${YELLOW}Continue? (y/n): ${NC}"
    read confirm
    
    if [ "$confirm" = "y" ]; then
        FIX_PERMISSIONS=true run_wpcli media regenerate --yes
    else
        print_message "$YELLOW" "Operation cancelled"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to clear transients
clear_transients() {
    print_header
    print_message "$MAGENTA" "🗑️  Clear Transients"
    echo ""
    
    run_wpcli transient delete --all
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to toggle maintenance mode
toggle_maintenance() {
    print_header
    print_message "$MAGENTA" "🔧 Maintenance Mode"
    echo ""
    
    echo -ne "${YELLOW}Action (activate/deactivate): ${NC}"
    read action
    
    if [ "$action" = "activate" ]; then
        run_wpcli maintenance-mode activate
    elif [ "$action" = "deactivate" ]; then
        run_wpcli maintenance-mode deactivate
    else
        print_message "$RED" "❌ Invalid action!"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to verify core checksums
verify_checksums() {
    print_header
    print_message "$MAGENTA" "🔍 Verify Core Checksums"
    echo ""
    
    run_wpcli core verify-checksums
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to reset admin password
reset_admin_password() {
    print_header
    print_message "$MAGENTA" "🔐 Reset Admin Password"
    echo ""
    
    run_wpcli user list --role=administrator
    echo ""
    
    echo -ne "${YELLOW}Admin username: ${NC}"
    read admin_user
    
    if [ -z "$admin_user" ]; then
        print_message "$RED" "❌ Admin username is required!"
    else
        run_wpcli user update "$admin_user" --prompt=user_pass
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}

# Function to show site info
site_info() {
    print_header
    print_message "$MAGENTA" "ℹ️  Site Info & System Status"
    echo ""
    
    print_message "$CYAN" "WordPress Information:"
    run_wpcli core version --extra
    
    echo ""
    print_message "$CYAN" "Site Options:"
    run_wpcli option get siteurl
    run_wpcli option get home
    
    echo ""
    print_message "$CYAN" "Active Theme:"
    run_wpcli theme list --status=active
    
    echo ""
    print_message "$CYAN" "Active Plugins Count:"
    run_wpcli plugin list --status=active --field=name | wc -l
    
    echo ""
    echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
    read
}
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
            2) update_core ;;
            3) check_core_version ;;
            4) backup_database ;;
            5) restore_database ;;
            6) search_replace ;;
            7) optimize_database ;;
            8) database_info ;;
            9) list_plugins ;;
            10) update_plugins ;;
            11) install_plugin ;;
            12) toggle_plugin ;;
            13) delete_plugin ;;
            14) list_themes ;;
            15) update_themes ;;
            16) install_theme ;;
            17) activate_theme ;;
            18) list_users ;;
            19) create_user ;;
            20) change_user_password ;;
            21) delete_user ;;
            22) flush_cache ;;
            23) regenerate_thumbnails ;;
            24) clear_transients ;;
            25) toggle_maintenance ;;
            26) 
                print_header
                fix_permissions
                echo ""
                echo -ne "${YELLOW}Press Enter to return to main menu...${NC}"
                read
                ;;
            27) verify_checksums ;;
            28) reset_admin_password ;;
            29) site_info ;;
            30) select_php_version_interactive ;;
            31) custom_command ;;
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
