#!/bin/sh


if [ -z "$POSTGRES_USER" -o "$POSTGRES_USER" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_USER"
	exit 1
fi

if [ -z "$POSTGRES_PASSWORD" -o "$POSTGRES_PASSWORD" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_PASSWORD"
	exit 1
fi

if [ -z "$POSTGRES_HOST" -o "$POSTGRES_HOST" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_HOST"
	exit 1
fi

POSTGRES_PORT=${POSTGRES_PORT:=5432}

if [ -z "$POSTGRES_DATABASE" -o "$POSTGRES_DATABASE" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_DATABASE"
	exit 1
fi

if [ -z "$POSTGRES_MASTER_USER" -o "$POSTGRES_MASTER_USER" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_MASTER_USER"
	exit 1
fi

if [ -z "$POSTGRES_MASTER_PASSWORD" -o "$POSTGRES_MASTER_PASSWORD" = "**None**" ]; then
	echo "$(date) FATAL: You need to set POSTGRES_MASTER_PASSWORD"
	exit 1
fi

# We don't need AWS S3 keys for this script but must be checked here for RESTORE_SH
S3_REGION=${S3_REGION:="us-west-1"}
S3_PREFIX=${S3_PREFIX:="backup"}

if [ -z "$S3_BUCKET" -o "$S3_BUCKET" = "**None**" ]; then
	echo "$(date) FATAL: You need to set S3_BUCKET"
	exit 1
fi

if [ -z "$S3_ACCESS_KEY_ID" -o "$S3_ACCESS_KEY_ID" = "**None**" ]; then
	echo "$(date) FATAL: You need to set S3_ACCESS_KEY_ID"
	exit 1
fi

if [ -z "$S3_SECRET_ACCESS_KEY" -o "$S3_SECRET_ACCESS_KEY" = "**None**" ]; then
	echo "$(date) FATAL: You need to set S3_SECRET_ACCESS_KEY"
	exit 1
fi

export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$S3_REGION

newest_backup_name () {
	aws s3 ls s3://$S3_BUCKET/$S3_PREFIX/ |sort |awk '{print $4}'
}

prepare_db () {
	cat << EOM | env PGPASSWORD=$POSTGRES_MASTER_PASSWORD psql -U $POSTGRES_MASTER_USER -h $POSTGRES_HOST -p $POSTGRES_PORT postgres
DROP DATABASE IF EXISTS $POSTGRES_DATABASE;
DROP ROLE IF EXISTS $POSTGRES_USER;
CREATE ROLE $POSTGRES_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';
GRANT $POSTGRES_USER TO $POSTGRES_MASTER_USER;
CREATE DATABASE $POSTGRES_DATABASE WITH OWNER $POSTGRES_USER;
EOM
}

restore_db () {
	newest=$1
	sqlfile=$(mktemp /var/tmp/restore-sql-gz-XXXXXXXX)
	trap "rm -f $sqlfile" 0 2 3 15
	aws s3api get-object --bucket "$S3_BUCKET" --key "$S3_PREFIX/$newest" $sqlfile > /dev/null
	if [ $? -ne 0 ]; then
		echo "$(date) Unable to get $S3_BUCKET/$S3_PREFIX/$newest"
		return 1
	fi
	gunzip < $sqlfile | env PGPASSWORD=$POSTGRES_MASTER_PASSWORD psql -U $POSTGRES_MASTER_USER -h $POSTGRES_HOST -p $POSTGRES_PORT $POSTGRES_DATABASE
	return $?
}

newest=$(newest_backup_name)
if [ $? -ne 0 ]; then
	echo "$(date) Unable to get newest DB backup.  Retrying"
	exit 1
fi

echo "$(date) Re-creating DB and role"
prepare_db
if [ $? -ne 0 ]; then
	echo "$(date) Unable to get newest DB backup.  Retrying"
	exit 1
fi
echo "$(date) Succeeded to create DB and role"

echo "$(date) Restoring DB with $newest"
restore_db $newest
if [ $? -ne 0 ]; then
	echo "$(date) Failed to restore DB"
	exit 1
fi
echo "$(date) Succeeded to restore DB"
