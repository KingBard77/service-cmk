#!/usr/bin/env bash

set -euo pipefail

# COLORS
NC='\033[0m'
SUCCESS='\033[0;32m'
ERROR='\033[0;31m'
WARN='\033[1;33m'
INFO='\033[1;34m'

# FALSE = run inside VM, TRUE = run remotely via xxclustersh
IS_REMOTE=TRUE

# SOURCE SCRIPT DIRECTORY
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && "${BASH_SOURCE[0]}" != "-bash" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# SOURCE SETUP.CONF
if [[ "$IS_REMOTE" == FALSE ]]; then
    CONFIG_FILE="${SCRIPT_DIR}/conf/setup.conf"
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        echo -e "${ERROR}  ERROR: Missing configuration file: $CONFIG_FILE${NC}"
        exit 1
    fi
fi

# USAGE
usage() {
    echo -e "${INFO}  #####################################################################${NC}"
    echo -e "${INFO}  #                Install (CMK) Service - Usage Guide                #${NC}"
    echo -e "${INFO}  #####################################################################${NC}"
    echo -e ""
    echo -e "${INFO}  Usage:${NC}"
    echo -e "${WARN}    sudo bash -x ./[SCRIPT_NAME]${NC}"
    echo -e ""
    echo -e "${INFO}  Description:${NC}"
    echo -e "    This script installs and configures CheckMK (CMK) services"
    echo -e ""
    echo -e "${INFO}  Requirements:${NC}"
    echo -e "    - Must be run as root (use sudo)"
    echo -e "    - Make sure conf/setup.conf is present with valid variables"
    echo -e ""
    echo -e "${INFO}  Example:${NC}"
    echo -e "    sudo bash -x ./service-cmk.sh"
    echo -e ""
    exit 1
}

# AGRS FOR HELP USAGE
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

echo -e "${INFO}  ##### Package: Update ${NC}"
apt --assume-yes update

echo -e "${INFO}  ##### OS: Version ${NC}"
OS_NAME=$(lsb_release -sc)

echo -e "${INFO}  ##### CMK: Download ${NC}"
CHECK_MK_URL=$(curl -s https://checkmk.com/download \
  | grep -oP '"(check-mk-raw-[^"]+\.deb)"' \
  | grep "$OS_NAME" \
  | grep -vE 'b[0-9]|rc[0-9]' \
  | head -n 1 \
  | awk -F '"' '{split($2, a, "_"); version=a[1]; sub(/check-mk-raw-/, "", version); print "https://download.checkmk.com/checkmk/" version "/" $2}')
wget -O checkmk.deb "$CHECK_MK_URL"

echo -e "${INFO}  ##### CMK: Install ${NC}"
apt install --assume-yes ./checkmk.deb

echo -e "${INFO}  ##### CMK: Version ${NC}"
OMD_VERSION=$(omd version | awk '{print $7}' | sed 's/\.cre//')

echo -e "${INFO}  ##### CMK: Create ${NC}"
omd create "$CMK_SITE_NAME"

echo -e "${INFO}  ##### CMK: Alias ${NC}"
ln -sf "/etc/systemd/system/check-mk-raw-${OMD_VERSION}.service" "/etc/systemd/system/checkmk2-3.service"

echo -e "${INFO}  ##### CMK: Systemd ${NC}"
systemctl daemon-reload

#echo -e "${INFO}  ##### CMK: Service ${NC}"
#systemctl enable "check-mk-raw-${OMD_VERSION}.service"
#systemctl restart "check-mk-raw-${OMD_VERSION}.service"

echo -e "${INFO}  ##### CMK: Credential ${NC}"
su - "$CMK_SITE_NAME" -c "sed -i '\$ s/})/, '\''$CMK_USER_NAME'\'': {'\''alias'\'': '\''$CMK_USER_ALIAS'\'', '\''roles'\'': ['\''$CMK_USER_ROLE'\''], '\''locked'\'': False, '\''connector'\'': '\''htpasswd'\''}})/' \"/omd/sites/$CMK_SITE_NAME/etc/check_mk/multisite.d/wato/users.mk\""
su - "$CMK_SITE_NAME" -c "sed -i \"s/})/, '$CMK_USER_NAME': {'alias': '$CMK_USER_ALIAS', 'email': '$CMK_USER_EMAIL', 'pager': '', 'contactgroups': [], 'fallback_contact': False, 'disable_notifications': {}, 'user_scheme_serial': 1}})/\" \"/omd/sites/$CMK_SITE_NAME/etc/check_mk/conf.d/wato/contacts.mk\""
htpasswd -bB /omd/sites/"${CMK_SITE_NAME}"/etc/htpasswd "$CMK_USER_NAME" "$CMK_USER_PASSWORD"

echo -e "${INFO}  ##### CMK: Configure Apache ${NC}"
cat <<EOF > "/omd/sites/$CMK_SITE_NAME/etc/apache/listen-port.conf"
ServerName ${CMK_SERVER_HOST}:${CMK_SERVER_PORT}
Listen ${CMK_SERVER_HOST}:${CMK_SERVER_PORT}
EOF

echo -e "${INFO}  ##### CMK: Service Restart ${NC}"
omd restart "$CMK_SITE_NAME"

echo -e "${INFO}  ##### CMK: Clean ${NC}"
apt --assume-yes autoremove
apt --assume-yes autoclean

echo -e "${SUCCESS} #### CMK: Install Complete #####${NC}"

echo -e "${INFO}#### Reboot ${NC}"
#reboot