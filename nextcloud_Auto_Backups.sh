#!/bin/bash

# AWS S3 bucket name
S3_BUCKET=""

# Nextcloud data directory
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"

# MySQL database connection parameters
DB_USER="nextcloud"
DB_PASSWORD="nextcloud"
DB_NAME="nextcloud"

# Backup directory
BACKUP_DIR="/root/backups"

# Number of days to retain backups
PURGE_DAYS=0

# Timestamp for backup file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create a backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Grant necessary privileges to MySQL user
mysql -u root <<EOF
GRANT PROCESS ON *.* TO '$DB_USER'@'localhost';
GRANT SELECT, LOCK TABLES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Backup Nextcloud data directory
tar -czf "$BACKUP_DIR/nextcloud_data_$TIMESTAMP.tar.gz" -C "$(dirname "$NEXTCLOUD_DATA_DIR")" "$(basename "$NEXTCLOUD_DATA_DIR")"

# Backup MySQL database
mysqldump -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/nextcloud_db_$TIMESTAMP.sql"

# Revoke PROCESS privilege after backup
mysql -u root <<EOF
REVOKE PROCESS ON *.* FROM '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Check if S3_BUCKET is not empty before uploading to AWS S3
if [ -n "$S3_BUCKET" ]; then
  # Upload backups to AWS S3
  aws s3 cp "$BACKUP_DIR/nextcloud_data_$TIMESTAMP.tar.gz" "s3://$S3_BUCKET/"
  aws s3 cp "$BACKUP_DIR/nextcloud_db_$TIMESTAMP.sql" "s3://$S3_BUCKET/"
fi

# Clean up local backups older than or equal to specified days
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$PURGE_DAYS -exec rm {} \;
find "$BACKUP_DIR" -type f -name "*.sql" -mtime +$PURGE_DAYS -exec rm {} \;

# Purge files older than or equal to specified days from AWS S3 if S3_BUCKET is not empty
if [ -n "$S3_BUCKET" ]; then
  aws s3 rm s3://$S3_BUCKET/ --recursive --exclude "*" --include "*_$(date -d "$PURGE_DAYS days ago" +"%Y%m%d")*"
fi
