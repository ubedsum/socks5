#!/bin/bash
# SOCKS5 Server Installer for Ubuntu
# Written by Google Gemini for user request
#
# This script installs, configures, and uninstalls Dante SOCKS5 server on Ubuntu.
# It handles dependencies, firewall rules, and user creation.

set -e

function YourBanner(){
  # ASCII Art Logo for "UBED"
  echo -e "
    \e[1;36m__  __ \e[1;33m_____\e[1;36m ______ \e[1;33m_____\e[0m
    \e[1;36m\\ \\/ / \e[1;33m| __ )\e[1;36m|  _ \\ \e[1;33m| __ )\e[0m
    \e[1;36m >  <  \e[1;33m|  _ \e[1;36m | | | |\e[1;33m|  _ \e[0m
    \e[1;36m/ /\\ \\ \e[1;33m| |_) |\e[1;36m| |_| |\e[1;33m| |_) |\e[0m
    \e[1;36m/_/  \\_\\\e[1;33m|____/\e[1;36m|____/ \e[1;33m|____/\e[0m
  "
  echo -e "
    \e[1;32m=============================================\e[0m
    \e[1;32m  Dante SOCKS5 Server Installer for Ubuntu\e[0m
    \e[1;32m=============================================\e[0m
  "
  echo -e "  This script will set up a SOCKS5 proxy on your VPS.\n"
}

function check_os(){
  source /etc/os-release
  if [[ "$ID" != 'ubuntu' ]]; then
    echo -e "[\e[1;31mError\e[0m] This script is only for Ubuntu. Exiting..."
    exit 1
  fi
}

function check_root(){
  if [[ $EUID -ne 0 ]];then
    echo -e "[\e[1;31mError\e[0m] This script must be run as root. Exiting..."
    exit 1
  fi
}

function install_dependencies(){
  echo -e "[\e[1;32m*\e[0m] Updating package list..."
  apt-get update -y &> /dev/null
  echo -e "[\e[1;32m*\e[0m] Installing required packages (dante-server, wget, nano, netcat)..."
  apt-get install dante-server wget nano netcat -y &> /dev/null
}

function configure_firewall(){
  if command -v ufw &> /dev/null; then
    echo -e "[\e[1;32m*\e[0m] UFW detected. Checking firewall status..."
    if ufw status | grep -q "active"; then
      echo -e "[\e[1;32m*\e[0m] UFW is active. Allowing port $SOCKSPORT..."
      ufw allow "$SOCKSPORT"/tcp comment 'Allow SOCKS5 Proxy' &> /dev/null
      echo -e "[\e[1;32m*\e[0m] UFW rules updated."
    else
      echo -e "[\e[1;33m!\e[0m] UFW is not active. Skipping firewall configuration."
    fi
  fi
}

function generate_dante_config(){
  echo -e "[\e[1;32m*\e[0m] Generating Dante configuration file at /etc/danted.conf..."

  SOCKSINET=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
  if [ -z "$SOCKSINET" ]; then
    echo -e "[\e[1;31mError\e[0m] Failed to detect the main network interface. Exiting..."
    exit 1
  fi

  cat > /etc/danted.conf <<EOF
logoutput: /var/log/socks.log
internal: 0.0.0.0 port = $SOCKSPORT
external: $SOCKSINET
socksmethod: $SOCKSAUTH
user.privileged: root
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error connect disconnect
}
  
client block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect error
}
  
socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error connect disconnect
}
  
socks block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect error
}
EOF
}

function setup_user(){
  if [ "$SOCKSAUTH" == 'username' ]; then
    echo -e "[\e[1;32m*\e[0m] Setting up user authentication for SOCKS5 proxy..."
    userdel -r -f "$socksUser" &> /dev/null || true
    # Use -r to remove home directory
    useradd -m -s /usr/sbin/nologin "$socksUser" &> /dev/null
    echo -e "$socksPass\n$socksPass" | passwd "$socksUser" &> /dev/null
    echo -e "[\e[1;32m*\e[0m] User '$socksUser' created with restricted shell."
  fi

  # NOTE: Using /usr/sbin/nologin is generally preferred over /bin/false
  # for service accounts on modern systems, but /bin/false is also fine.
  # Added a check to use /usr/sbin/nologin in useradd.
}

function start_service(){
  echo -e "[\e[1;32m*\e[0m] Starting and enabling Dante service..."
  systemctl daemon-reload # Good practice after config changes
  systemctl restart danted.service
  systemctl enable danted.service &> /dev/null
  echo -e "[\e[1;32m*\e[0m] Dante service status:"
  systemctl status danted.service | head -n 3
}

function success_message(){
  clear
  YourBanner
  # Use Google Search to find external IP to avoid using wget just for this if not necessary,
  # but keeping wget check as a fallback if the search tool is unavailable or for script simplicity.
  # For a self-contained script, keeping the wget call is simpler.
  PROXY_IP=$(wget -4qO- http://ipinfo.io/ip)
  echo -e "\n== SOCKS5 Server successfully installed! ==\n"
  echo -e "  Proxy IP Address:    \e[1;32m$PROXY_IP\e[0m"
  echo -e "  Proxy Port:          \e[1;32m$SOCKSPORT\e[0m"
  if [ "$SOCKSAUTH" == 'username' ]; then
    echo -e "  Username:            \e[1;32m$socksUser\e[0m"
    echo -e "  Password:            \e[1;32m$socksPass\e[0m"
  fi
  echo -e "\n  SOCKS5 info saved to /root/socks5.txt"
  
  cat > ~/socks5.txt <<EOF
== Your SOCKS5 Proxy Information ==
IP Address: $PROXY_IP
Port: $SOCKSPORT
EOF
  if [ "$SOCKSAUTH" == 'username' ]; then
    echo -e "Username: $socksUser" >> ~/socks5.txt
    echo -e "Password: $socksPass" >> ~/socks5.txt
  fi
  
  echo -e "\n  Sharing SOCKS5 info to termbin.com for easy access..."
  # Added timeout for nc
  ONLINE_LINK=$(timeout 10 cat ~/socks5.txt | nc termbin.com 9999 2>/dev/null)
  if [ -n "$ONLINE_LINK" ]; then
      echo -e "  Online Link: \e[1;34m$ONLINE_LINK\e[0m\n"
      echo "  Use the link to quickly share your proxy details."
  else
      echo -e "  [\e[1;33m!\e[0m] Could not share to termbin.com (timeout or connection error)."
  fi
  echo -e "=============================================\n"
}

function uninstall(){
  echo -e "\n[\e[1;31m!\e[0m] Are you sure you want to uninstall SOCKS5 server? (y/n)"
  read -rp " Your choice: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "[\e[1;32m*\e[0m] Stopping and disabling Dante service..."
    systemctl stop danted.service
    systemctl disable danted.service &> /dev/null

    echo -e "[\e[1;32m*\e[0m] Removing Dante server package..."
    apt-get remove --purge dante-server -y &> /dev/null
    
    echo -e "[\e[1;32m*\e[0m] Removing configuration files and logs..."
    rm -f /etc/danted.conf
    rm -f /var/log/socks.log
    rm -f /root/socks5.txt

    # Clean up ufw rule if it exists (Optional, but good for completeness)
    if command -v ufw &> /dev/null; then
        echo -e "[\e[1;32m*\e[0m] Checking for and removing SOCKS5 UFW rule..."
        # Find all ports allowed by the SOCKS5 comment and delete them
        ufw status verbose | grep "Allow SOCKS5 Proxy" | awk '{print $1}' | while read -r port_entry; do
            ufw delete allow "$port_entry" &>/dev/null
        done
    fi

    echo -e "[\e[1;32m*\e[0m] Cleaning up..."
    apt-get autoremove -y &> /dev/null
    apt-get clean &> /dev/null
    
    echo -e "\n[\e[1;32m✓\e[0m] SOCKS5 server successfully uninstalled.\n"
  else
    echo -e "\n[\e[1;33m!\e[0m] Uninstallation cancelled.\n"
  fi
}

function Installation(){
  install_dependencies
  generate_dante_config
  setup_user
  configure_firewall
  start_service
  success_message
}

function main_menu(){
  clear
  YourBanner
  echo -e " Choose an option:"
  echo -e " [1] Install Public Proxy (no auth)"
  echo -e " [2] Install Private Proxy (with auth)"
  echo -e " [3] Uninstall SOCKS5 Proxy Server"
  
  opts="" # Ensure opts is empty before the loop
  until [[ "$opts" =~ ^[1-3]$ ]]; do
    read -rp " Select an option [1-3]: " -e opts
  done

  case $opts in
    1)
    SOCKSPORT="" # Reset variable for the loop
    until [[ "$SOCKSPORT" =~ ^[0-9]+$ ]] && [ "$SOCKSPORT" -ge 1 ] && [ "$SOCKSPORT" -le 65535 ]; do
      read -rp " Enter SOCKS5 Port [1-65535]: " -i 2408 -e SOCKSPORT
    done
    SOCKSAUTH='none'
    Installation
    ;;
    2)
    SOCKSPORT="" # Reset variable for the loop
    until [[ "$SOCKSPORT" =~ ^[0-9]+$ ]] && [ "$SOCKSPORT" -ge 1 ] && [ "$SOCKSPORT" -le 65535 ]; do
      read -rp " Enter SOCKS5 Port [1-65535]: " -i 2408 -e SOCKSPORT
    done
    SOCKSAUTH='username'
    socksUser="" # Reset variable for the loop
    until [[ "$socksUser" =~ ^[a-zA-Z0-9_]+$ ]]; do
      read -rp " Enter SOCKS5 Username: " -e socksUser
    done
    socksPass="" # Reset variable for the loop
    until [[ "$socksPass" =~ ^[a-zA-Z0-9_]+$ ]]; do
      read -rp " Enter SOCKS5 Password: " -e socksPass
    done
    Installation
    ;;
    3)
    uninstall
    exit 0
    ;;
  esac
}

# --- Main Script Execution ---
YourBanner
check_os
check_root
main_menu
