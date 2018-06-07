#!/bin/sh

RESTORE_SH="/bin/sh $(dirname $0)/restore.sh"

MAX_RETRY=${MAX_RETRY:=5}
INTERVAL=${CHECK_INTERVAL:=60}

RELATION_CHECK_DIR=${RELATION_CHECK_DIR:="$(dirname $0)/relation_check"}

if [ -z "$RELATION_CHECK_SQL" -o "$RELATION_CHECK_SQL" = "**None**" ]; then
	echo "$(date) FATAL: You need to set RELATION_CHECK_SQL"
	exit 1
fi

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

# Check if RELATION_CHECK_SQL is bundled one
# Otherwise use the value as-is.
if [ -f "$RELATION_CHECK_DIR/${RELATION_CHECK_SQL}.sql" ];then
	RELATION_CHECK_SQL_PATH="$RELATION_CHECK_DIR/${RELATION_CHECK_SQL}.sql"
elif [ -f "${RELATION_CHECK_SQL}" ]; then
	RELATION_CHECK_SQL_PATH="${RELATION_CHECK_SQL}"
else
	echo "$(date) FATAL: RELATION_CHECK_SQL=\"$RELATION_CHECK_SQL\" is invalid.  Use a name of bundled sql file or a full-path"
	exit 1
fi

check_connection () {
	# Initialized DB doesn't have the application-specific user, so this check should be done with the master user.
	env PGPASSWORD=$POSTGRES_MASTER_PASSWORD psql -U $POSTGRES_MASTER_USER -h $POSTGRES_HOST -p $POSTGRES_PORT --list > /dev/null
	return $?
}

check_pg_ok () {
	# If DB user or DB don't exist, it seems that something in the DB is going wrong
	env PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -h $POSTGRES_HOST -p $POSTGRES_PORT $POSTGRES_DATABASE -c 'SELECT 1' > /dev/null
	return $?
}

check_db_ok () {
	# This check is for operational failure or partial restoring
	if [ ! -f $RELATION_CHECK_SQL_PATH ]; then
		echo "$(date) No such file $RELATION_CHECK_SQL_PATH (from env RELATION_CHECK_SQL)"
		exit 1
	fi
	cat $RELATION_CHECK_SQL_PATH | env PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -h $POSTGRES_HOST -p $POSTGRES_PORT $POSTGRES_DATABASE > /dev/null
	return $?
}

interval=0
retry=0
while [ $retry -lt $MAX_RETRY ]
do
	sleep $interval
	interval=$CHECK_INTERVAL

	echo "$(date) Checking database $POSTGRES_DATABASE on $POSTGRES_HOST:$POSTGRES_PORT"
	if ! check_connection; then
		echo "$(date) Connection failed"
		# Don't count up $retry on network error because only this host may be isolated
		continue
	fi

	check_pg_ok
	pg_ok=$?
	if [ $pg_ok != 0 ]; then
		echo "$(date) DB host is up but DB $POSTGRES_DATABASE or the user for the DB is not ready"
	fi

	check_db_ok
	db_ok=$?
	if [ $db_ok != 0 ]; then
		echo "$(date) DB $POSTGRES_DATABASE is ready but relations looks strange"
	fi

	if [ $pg_ok -ne 0 -o $db_ok -ne 0 ]; then
		echo "$(date) DB host is up but DB $POSTGRES_DATABASE is not ready"
		/bin/sh $RESTORE_SH
		if [ $? -ne 0 ]; then
			echo "$(date) Failed to restore DB"
			retry=$((retry + 1))
			continue
		else
			echo "$(date) Succeeded to restore DB"
		fi
	fi
	retry=0

done

echo "$(date) FATAL: DB $POSTGRES_DATABASE on $POSTGRES_HOST is in wrong state, but unable to restore from backup"
exit 1
