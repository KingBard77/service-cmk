#!/usr/bin/env bash

# COLORS
NC='\033[0m'
SUCCESS='\033[0;32m'
ERROR='\033[0;31m'
WARN='\033[0;33m'
INFO='\033[0;34m'

# SOURCE SETUP.CONF
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/conf/setup.conf" ]]; then
    source "$SCRIPT_DIR/conf/setup.conf"
fi

echo -e "${INFO}##### Package: Update ${NC}"
apt --assume-yes update

echo -e "${INFO}##### OS: Version ${NC}"
OS_NAME=$(lsb_release -sc)

echo -e "${INFO}##### CMK: Download ${NC}"
CHECKMK_URL=$(curl -s https://checkmk.com/download \
  | grep -oP '"(check-mk-raw-[^"]+\.deb)"' \
  | grep "$OS_NAME" \
  | grep -vE 'b[0-9]|rc[0-9]' \
  | head -n 1 \
  | awk -F '"' '{split($2, a, "_"); version=a[1]; sub(/check-mk-raw-/, "", version); print "https://download.checkmk.com/checkmk/" version "/" $2}')
wget -O checkmk.deb "$CHECKMK_URL"

echo -e "${INFO}##### CMK: Install ${NC}"
apt install --assume-yes ./checkmk.deb

echo -e "${INFO}##### CMK: Version ${NC}"
OMD_VERSION=$(omd version | awk '{print $7}' | sed 's/\.cre//')

echo -e "${INFO}##### CMK: Create ${NC}"
omd create "$SITE_NAME"

echo -e "${INFO}##### CMK: Alias ${NC}"
ln -sf /etc/systemd/system/check-mk-raw-$OMD_VERSION.service /etc/systemd/system/checkmk2-3.service

echo -e "${INFO}##### CMK: Sysmtemd ${NC}"
systemctl daemon-reload

echo -e "${INFO}##### CMK: Service ${NC}"
systemctl enable check-mk-raw-$OMD_VERSION.service
systemctl restart check-mk-raw-$OMD_VERSION.service

echo -e "${INFO}##### CMK: Credential ${NC}"
su - "$SITE_NAME" -c "sed -i '\$ s/})/, '\''$USERNAME'\'': {'\''alias'\'': '\''$ALIAS'\'', '\''roles'\'': ['\''$ROLE'\''], '\''locked'\'': False, '\''connector'\'': '\''htpasswd'\''}})/' /omd/sites/monitoring/etc/check_mk/multisite.d/wato/users.mk"
su - "$SITE_NAME" -c "sed -i \"s/})/, '$USERNAME': {'alias': '$ALIAS', 'email': '$EMAIL', 'pager': '', 'contactgroups': [], 'fallback_contact': False, 'disable_notifications': {}, 'user_scheme_serial': 1}})/\" /omd/sites/monitoring/etc/check_mk/conf.d/wato/contacts.mk"
htpasswd -bB /omd/sites/${SITE_NAME}/etc/htpasswd $USERNAME $PASSWORD

echo -e "${INFO}##### CMK: Configure ${NC}"
cat << EOF > /omd/sites/${SITE_NAME}/etc/apache/listen-port.conf
ServerName ${CMK_SERVER}:${CMK_PORT}
Listen ${CMK_SERVER}:${CMK_PORT}
EOF

echo -e "${INFO}##### CMK: Service ${NC}"
omd restart "$SITE_NAME"

echo -e "${INFO}##### CMK: Clean ${NC}"
apt --assume-yes autoremove
apt --assume-yes autoclean

echo -e "${SUCCESS}#### CMK: Install Complete #####${NC}"

echo -e "${INFO}#### Reboot ${NC}"
#reboot