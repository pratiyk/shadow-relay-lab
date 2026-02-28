#!/bin/bash
# Optimized Startup script for Project: ShadowRelay on a Single Ubuntu GCP VM
# Designed for Vulnerability Simulation (LFI -> Exposed Credentials -> Privilege Escalation)
set -e

exec > /var/log/startup-script.log 2>&1

echo "=========================================="
echo "Starting Project: ShadowRelay Initialization"
echo "=========================================="

# --- Variables ---
REPO_URL="https://github.com/pratiyk/shadow-relay-lab.git"
REPO_DIR="/opt/shadow-relay-lab"

WEB_ROOT="/var/www/html"
SVC_USER="svc_ldap"
SVC_PASS="LdapSvc!2024"
FLAG_INITIAL="VulnOS{initial_foothold_ldap}"
FLAG_ROOT="VulnOS{root_privesc_complete}"

# --- 1. System Dependencies ---
echo "[1] Updating packages and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 php libapache2-mod-php git curl sudo cron \
                   python3 python3-pip python3-venv smbclient ldap-utils

# --- 2. Repository Setup ---
echo "[2] Cloning Repository..."
# Forcefully remove old repo to ensure fresh state on reboot/re-run
if [ -d "$REPO_DIR" ]; then
    rm -rf "$REPO_DIR"
fi
git clone "$REPO_URL" "$REPO_DIR"
cd "$REPO_DIR"

# --- 3. Web Application Configuration ---
echo "[3] Configuring Vulnerable Web App..."

# Clean default Apache index
rm -f "$WEB_ROOT/index.html"

# If the web-app directory doesn't exist in the repo yet, create fallback vulnerable files
if [ ! -d "$REPO_DIR/web-app" ]; then
    echo "Creating fallback web files since web-app repo dir is missing..."
    mkdir -p "$REPO_DIR/web-app/legacy_backup"
    
cat << 'EOF' > "$REPO_DIR/web-app/index.php"
<!DOCTYPE html>
<html>
<head><title>GFS Fleet Management Portal</title></head>
<body>
    <h2>Global Freight Solutions Portal</h2>
    <a href="?page=home.php">Home</a> | <a href="?page=vehicles.php">Vehicles</a>
    <hr>
    <?php
        if (isset($_GET['page'])) {
            // VULNERABILITY: Local File Inclusion
            include($_GET['page']);
        } else {
            echo "<p>Welcome. Please select a page.</p>";
        }
    ?>
</body>
</html>
EOF

    echo "<p>System migration mostly complete.</p>" > "$REPO_DIR/web-app/home.php"
    echo "<p>Vehicle DB offline.</p>" > "$REPO_DIR/web-app/vehicles.php"

cat << EOF > "$REPO_DIR/web-app/legacy_backup/web.config"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <connectionStrings>
    <!-- FLAG: $FLAG_INITIAL -->
    <add name="ADLDAP" connectionString="LDAP://gfs.local" />
  </connectionStrings>
  <appSettings>
    <add key="LDAPUser" value="$SVC_USER" />
    <add key="LDAPPassword" value="$SVC_PASS" />
  </appSettings>
</configuration>
EOF
fi

# Copy the vulnerable web app from the repo to the Apache web root
cp -r "$REPO_DIR/web-app/"* "$WEB_ROOT/"

# Ensure proper permissions
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# Restart Apache
systemctl restart apache2

# --- 4. User Configuration ---
echo "[4] Configuring Users and SSH..."
if ! id -u "$SVC_USER" >/dev/null 2>&1; then
    # Create the user from the leaked credentials
    useradd -m -s /bin/bash "$SVC_USER"
    echo "$SVC_USER:$SVC_PASS" | chpasswd
fi

# To allow SSH login with the leaked password, ensure PasswordAuth is enabled
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# Remove include config that overrides password auth on newer Ubuntu
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf || true
systemctl restart ssh

# --- 5. Privilege Escalation Vector ---
echo "[5] Configuring Root Privilege Escalation Vector..."

# Setup a mock vulnerable service running as root
cat << 'EOF' > /usr/local/bin/gfs_backup_service.sh
#!/bin/bash
# Automatically syncs the web directory to a backup location
rsync -av /var/www/html/ /var/backups/gfs_web/
EOF
chmod 755 /usr/local/bin/gfs_backup_service.sh

cat << EOF > /etc/systemd/system/gfs-backup.service
[Unit]
Description=Global Freight Solutions Web Backup
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gfs_backup_service.sh
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gfs-backup.service

# VULNERABILITY: User svc_ldap can restart the gfs-backup service without a password
echo "$SVC_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart gfs-backup" > /etc/sudoers.d/gfs-lab-sudo
chmod 440 /etc/sudoers.d/gfs-lab-sudo

# VULNERABILITY: The service script is writable by the svc_ldap group/user
chown root:$SVC_USER /usr/local/bin/gfs_backup_service.sh
chmod 775 /usr/local/bin/gfs_backup_service.sh

# Place the final root flag
echo "$FLAG_ROOT" > /root/flag.txt
chmod 600 /root/flag.txt

echo "=========================================="
echo "ShadowRelay Setup Complete. Happy Hunting!"
echo "=========================================="
