#!/bin/bash
# Ghostman OSINT Toolkit (all-in-one)
# File name: ghostman-osint.sh
# Usage: chmod +x ghostman-osint.sh && ./ghostman-osint.sh
set -e

# ---------------------------
# Colors & helpers
# ---------------------------
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
MAG="\033[1;35m"
RESET="\033[0m"

echog() { echo -e "${CYAN}[Ghostman]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[!]:${RESET} $1"; }
err()   { echo -e "${RED}[ERR]:${RESET} $1" >&2; }

CONF="$HOME/.ghostman_conf"
CASE_DIR="$HOME/OSINT_Cases"
mkdir -p "$CASE_DIR"

# ---------------------------
# Banner
# ---------------------------
clear
if command -v figlet >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then
  figlet -f slant "Ghostman" | lolcat
else
  echo -e "${MAG}"
  echo "  ____ _               _   __  __                 "
  echo " / ___| |__   ___  ___| |_|  \/  | __ _ _ __ ___  "
  echo "| |  _| '_ \ / _ \/ __| __| |\/| |/ _\` | '_ \` _ \ "
  echo "| |_| | | | |  __/ (__| |_| |  | | (_| | | | | | |"
  echo " \____|_| |_|\___|\___|\__|_|  |_|\__,_|_| |_| |_|"
  echo -e "${RESET}"
fi
echo -e "${YELLOW}Welcome, Ghostman.${RESET}"
sleep 1

# ---------------------------
# Helper funcs
# ---------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found. Please install it and re-run."; exit 1; }
}

save_conf() {
  cat > "$CONF" <<EOF
# Ghostman configuration (do not share)
SHODAN_API="${SHODAN_API:-}"
CENSYS_API="${CENSYS_API:-}"
CENSYS_SECRET="${CENSYS_SECRET:-}"
HIBP_API="${HIBP_API:-}"
TOR_ENABLED="${TOR_ENABLED:-no}"
EOF
  chmod 600 "$CONF"
}

load_conf() {
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    source "$CONF"
  else
    SHODAN_API=""
    CENSYS_API=""
    CENSYS_SECRET=""
    HIBP_API=""
    TOR_ENABLED="no"
  fi
}

proxy_prefix() {
  # Use torsocks when tor mode enabled and torsocks is available
  load_conf
  if [[ "$TOR_ENABLED" == "yes" && -x "$(command -v torsocks)" ]]; then
    echo "torsocks"
  else
    echo ""
  fi
}

run_with_proxy() {
  prefix="$(proxy_prefix)"
  if [[ -n "$prefix" ]]; then
    # run command with torsocks
    torsocks "$@"
  else
    "$@"
  fi
}

timestamp() {
  date +"%Y-%m-%d_%H-%M-%S"
}

# ---------------------------
# Installation
# ---------------------------
install_prereqs() {
  echog "Updating system and installing prerequisites..."
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y python3 python3-pip git curl wget tor torsocks exiftool amass figlet lolcat jq wkhtmltopdf || true
  # pip installs
  sudo -H pip3 install spiderfoot maigret holehe shodan || true
}

install_or_update_gitrepo() {
  name="$1"; url="$2"
  if [ -d "$name" ]; then
    echog "Updating $name..."
    (cd "$name" && git pull) || warn "Couldn't update $name from git."
  else
    echog "Cloning $name..."
    git clone "$url" "$name" || warn "Couldn't clone $url"
  fi
  # install python deps if requirements exist
  if [ -f "$name/requirements.txt" ]; then
    echog "Installing $name python requirements..."
    sudo -H pip3 install -r "$name/requirements.txt" || warn "pip install failed for $name"
  fi
}

install_tools() {
  echog "Installing & updating OSINT tools..."
  install_or_update_gitrepo recon-ng https://github.com/lanmaster53/recon-ng.git
  install_or_update_gitrepo sherlock https://github.com/sherlock-project/sherlock.git
  install_or_update_gitrepo theHarvester https://github.com/laramies/theHarvester.git
  install_or_update_gitrepo Sublist3r https://github.com/aboul3la/Sublist3r.git
  install_or_update_gitrepo ghunt https://github.com/mxrch/ghunt.git
  # spiderfoot already installed via pip
  echog "Tool install/update finished."
}

# ---------------------------
# Configuration (API keys / Tor)
# ---------------------------
configure() {
  load_conf
  echo
  echog "Ghostman configuration - store API keys and Tor mode."
  read -rp "Shodan API Key (leave blank to keep current): " tmp
  if [ -n "$tmp" ]; then SHODAN_API="$tmp"; fi
  read -rp "Censys API ID (leave blank to keep current): " tmp
  if [ -n "$tmp" ]; then CENSYS_API="$tmp"; fi
  read -rp "Censys Secret (leave blank to keep current): " tmp
  if [ -n "$tmp" ]; then CENSYS_SECRET="$tmp"; fi
  read -rp "HaveIBeenPwned API Key (leave blank to keep current): " tmp
  if [ -n "$tmp" ]; then HIBP_API="$tmp"; fi
  read -rp "Enable Tor mode? (yes/no) [current: ${TOR_ENABLED:-no}]: " tmp
  if [[ "$tmp" =~ ^(yes|no)$ ]]; then TOR_ENABLED="$tmp"; fi

  save_conf
  echog "Configuration saved to $CONF (permissions 600)."
}

# ---------------------------
# Reporting
# ---------------------------
generate_report_for_last_case() {
  last_case=$(ls -1d "$CASE_DIR"/* 2>/dev/null | tail -n 1 || true)
  if [ -z "$last_case" ]; then
    warn "No cases found in $CASE_DIR"
    return 1
  fi
  echog "Generating report for last case: $last_case"

  html="$last_case/report.html"
  pdf="$last_case/report_$(timestamp).pdf"

  cat > "$html" <<EOF
<html>
<head><meta charset="utf-8"><title>Ghostman OSINT Report - $(basename "$last_case")</title>
<style>
body{font-family: Arial, Helvetica, sans-serif; margin:20px}
h1{color:#2b6cb0}
pre{background:#f6f8fa;border:1px solid #ddd;padding:10px;overflow:auto}
.section{margin-bottom:20px}
</style>
</head><body>
<h1>Ghostman OSINT Report</h1>
<p>Case: <strong>$(basename "$last_case")</strong></p>
<p>Generated: $(date -R)</p>
EOF

  # For each log file in the case folder, embed a section
  for f in "$last_case"/*; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    echo "<div class='section'><h2>$fname</h2><pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$f")</pre></div>" >> "$html"
  done

  echo "</body></html>" >> "$html"
  echog "HTML report created: $html"

  if command -v wkhtmltopdf >/dev/null 2>&1; then
    echog "Converting HTML to PDF (wkhtmltopdf)..."
    wkhtmltopdf "$html" "$pdf" && echog "PDF report: $pdf"
  else
    warn "wkhtmltopdf not installed. Skip PDF generation. Install it to enable PDF reports."
  fi
}

# ---------------------------
# API helper functions
# ---------------------------
shodan_query_host() {
  load_conf
  if [ -z "$SHODAN_API" ]; then warn "No Shodan API key configured. Use Configure -> set SHODAN_API."; return; fi
  host="$1"
  echog "Querying Shodan for host: $host"
  out="$CASE_FOLDER/shodan_$host.json"
  if [[ -n "$(proxy_prefix)" ]]; then
    run_with_proxy shodan host "$host" --fields ip_str,port,org,hostnames,os,product > "$out" 2>/dev/null || true
  else
    shodan host "$host" --fields ip_str,port,org,hostnames,os,product > "$out" 2>/dev/null || true
  fi
  echo "Saved: $out"
}

censys_query_host() {
  load_conf
  if [ -z "$CENSYS_API" ] || [ -z "$CENSYS_SECRET" ]; then warn "No Censys credentials configured."; return; fi
  host="$1"
  echog "Querying Censys (certs) for: $host"
  out="$CASE_FOLDER/censys_$host.json"
  # minimal query via Censys Search API v2 using curl
  body="{\"query\":\"$host\",\"per_page\":10}"
  if [[ -n "$(proxy_prefix)" ]]; then
    run_with_proxy curl -s -u "$CENSYS_API:$CENSYS_SECRET" -X POST "https://search.censys.io/api/v2/hosts/search" -H "Content-Type: application/json" -d "$body" -o "$out" || true
  else
    curl -s -u "$CENSYS_API:$CENSYS_SECRET" -X POST "https://search.censys.io/api/v2/hosts/search" -H "Content-Type: application/json" -d "$body" -o "$out" || true
  fi
  echo "Saved: $out"
}

hibp_check_email() {
  load_conf
  if [ -z "$HIBP_API" ]; then warn "No HIBP API key configured."; return; fi
  email="$1"
  echog "Checking breaches for email: $email"
  out="$CASE_FOLDER/hibp_$email.json"
  url="https://haveibeenpwned.com/api/v3/breachedaccount/$(printf "%s" "$email" | jq -sRr @uri)"
  if [[ -n "$(proxy_prefix)" ]]; then
    run_with_proxy curl -s -H "hibp-api-key: $HIBP_API" -H "User-Agent: Ghostman-Toolkit" "$url" -o "$out" || true
  else
    curl -s -H "hibp-api-key: $HIBP_API" -H "User-Agent: Ghostman-Toolkit" "$url" -o "$out" || true
  fi
  echo "Saved: $out"
}

# ---------------------------
# Main menu & flows
# ---------------------------
main_menu() {
  load_conf
  while true; do
    clear
    figlet -f slant "Ghostman" 2>/dev/null || echo "=== Ghostman OSINT ==="
    echo -e "${CYAN}Welcome, Ghostman. Choose an action:${RESET}"
    echo -e "${YELLOW}1${RESET}) Quick install/update prerequisites & tools"
    echo -e "${YELLOW}2${RESET}) Configure API keys & Tor mode"
    echo -e "${YELLOW}3${RESET}) Run OSINT menu"
    echo -e "${YELLOW}4${RESET}) Generate report from last case (HTML + optional PDF)"
    echo -e "${YELLOW}5${RESET}) Show config (safe view)"
    echo -e "${RED}0${RESET}) Exit"
    read -rp "Choice: " choice
    case $choice in
      1) install_prereqs; install_tools; read -rp "Press Enter to continue..." ;;
      2) configure; read -rp "Press Enter to continue..." ;;
      3) osint_menu ;;
      4) generate_report_for_last_case; read -rp "Press Enter to continue..." ;;
      5) show_config; read -rp "Press Enter to continue..." ;;
      0) echog "Goodbye, Ghostman."; exit 0 ;;
      *) warn "Invalid choice." ;;
    esac
  done
}

show_config() {
  load_conf
  echo "Configuration (sensitive values hidden):"
  echo "SHODAN_API: $( [ -n "$SHODAN_API" ] && echo "SET" || echo "NOT SET" )"
  echo "CENSYS_API: $( [ -n "$CENSYS_API" ] && echo "SET" || echo "NOT SET" )"
  echo "CENSYS_SECRET: $( [ -n "$CENSYS_SECRET" ] && echo "SET" || echo "NOT SET" )"
  echo "HIBP_API: $( [ -n "$HIBP_API" ] && echo "SET" || echo "NOT SET" )"
  echo "TOR_ENABLED: ${TOR_ENABLED:-no}"
}

osint_menu() {
  while true; do
    clear
    echo -e "${MAG}Ghostman OSINT - Tools${RESET}"
    echo -e "${YELLOW}1${RESET}) SpiderFoot (GUI/Server)"
    echo -e "${YELLOW}2${RESET}) Recon-ng"
    echo -e "${YELLOW}3${RESET}) Sherlock (username)"
    echo -e "${YELLOW}4${RESET}) Maigret (username)"
    echo -e "${YELLOW}5${RESET}) Holehe (email)"
    echo -e "${YELLOW}6${RESET}) theHarvester (domain)"
    echo -e "${YELLOW}7${RESET}) Amass (domain)"
    echo -e "${YELLOW}8${RESET}) Sublist3r (domain)"
    echo -e "${YELLOW}9${RESET}) ExifTool (image metadata)"
    echo -e "${YELLOW}10${RESET}) GHunt (google account investigator)"
    echo -e "${YELLOW}11${RESET}) Shodan (host lookup via API)"
    echo -e "${YELLOW}12${RESET}) Censys (host search via API)"
    echo -e "${YELLOW}13${RESET}) HIBP (email breach check)"
    echo -e "${YELLOW}14${RESET}) Open case folder (file manager)"
    echo -e "${RED}0${RESET}) Back"
    read -rp "Choose tool: " t
    TIMESTAMP=$(timestamp)
    CASE_FOLDER="$CASE_DIR/$TIMESTAMP"
    mkdir -p "$CASE_FOLDER"
    case $t in
      1)
        echog "Starting SpiderFoot (server mode opens on port 5001)..."
        run_with_proxy spiderfoot -l 127.0.0.1:5001 | tee "$CASE_FOLDER/spiderfoot.log" ;;
      2)
        echog "Starting recon-ng (interactive). Use 'workspaces create <name>' etc."
        (cd recon-ng && run_with_proxy ./recon-ng) | tee "$CASE_FOLDER/recon-ng.log" ;;
      3)
        read -rp "Username: " user
        run_with_proxy python3 sherlock/sherlock.py "$user" | tee "$CASE_FOLDER/sherlock_$user.log" ;;
      4)
        read -rp "Username: " user
        run_with_proxy maigret "$user" | tee "$CASE_FOLDER/maigret_$user.log" ;;
      5)
        read -rp "Email: " mail
        run_with_proxy holehe "$mail" | tee "$CASE_FOLDER/holehe_$mail.log" ;;
      6)
        read -rp "Domain: " dom
        run_with_proxy python3 theHarvester/theHarvester.py -d "$dom" -b all | tee "$CASE_FOLDER/theHarvester_$dom.log" ;;
      7)
        read -rp "Domain: " dom
        run_with_proxy amass enum -d "$dom" | tee "$CASE_FOLDER/amass_$dom.log" ;;
      8)
        read -rp "Domain: " dom
        run_with_proxy python3 Sublist3r/sublist3r.py -d "$dom" | tee "$CASE_FOLDER/sublist3r_$dom.log" ;;
      9)
        read -rp "File path: " file
        exiftool "$file" | tee "$CASE_FOLDER/exiftool_$(basename "$file").log" ;;
      10)
        echog "GHunt requires setup (see GHunt README). Running ghunt interactively..."
        (cd ghunt && run_with_proxy python3 ghunt.py) | tee "$CASE_FOLDER/ghunt.log" ;;
      11)
        read -rp "Host/IP: " host
        shodan_query_host "$host" | tee -a "$CASE_FOLDER/shodan_cmd.log" || true
        ;&
      12)
        read -rp "Host (name or IP): " host2
        censys_query_host "$host2" | tee -a "$CASE_FOLDER/censys_cmd.log" || true
        ;;
      13)
        read -rp "Email: " mail2
        hibp_check_email "$mail2" | tee -a "$CASE_FOLDER/hibp_cmd.log" || true
        ;;
      14)
        if command -v xdg-open >/dev/null 2>&1; then
          xdg-open "$CASE_FOLDER" >/dev/null 2>&1 || warn "Couldn't open file manager."
        else
          warn "xdg-open not available; case folder is: $CASE_FOLDER"
        fi
        ;;
      0) break ;;
      *) warn "Invalid option" ;;
    esac
    echog "Session saved at: $CASE_FOLDER"
    read -rp "Press Enter to continue..." _
  done
}

# ---------------------------
# Start
# ---------------------------
main_menu
