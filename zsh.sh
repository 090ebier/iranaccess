#!/bin/bash
# ==============================
# ZSH + Oh My Zsh clean installer
# ==============================

set -e

echo "[+] Installing packages..."
apt update
apt install -y zsh curl git

echo "[+] Setting default shell to zsh..."
chsh -s /usr/bin/zsh root

echo "[+] Installing Oh My Zsh..."
export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "[+] Backing up old zshrc..."
mv ~/.zshrc ~/.zshrc.bak.$(date +%s) 2>/dev/null || true

echo "[+] Creating clean .zshrc..."

cat > ~/.zshrc <<'EOF'
# ===== Base =====
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git)
source $ZSH/oh-my-zsh.sh

# ===== History =====
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# ===== Prompt =====
setopt PROMPT_SUBST
PROMPT=$'%B%F{blue}┌──%f(%F{yellow}%n%f@%F{cyan}%m%f)%F{blue}-%f[%F{green}%~%f]\n%F{blue}└──%f(%F{white}%*%f)%F{blue}-%f%F{red}# %f%b'

# ===== Aliases =====
alias ls='ls --color=auto'
alias ll='ls -lah --group-directories-first --color=auto --time-style=long-iso'
alias grep='grep --color=auto'
EOF

echo "[+] Cleaning broken history (safe)..."
mv ~/.zsh_history ~/.zsh_history.bad.$(date +%s) 2>/dev/null || true

echo "[+] Importing bash history safely..."

touch ~/.zsh_history
cat ~/.bash_history >> ~/.zsh_history
fc -R ~/.zsh_history

echo
echo "[✓] Done."
echo "👉 Now run: zsh"
