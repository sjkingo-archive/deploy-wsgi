#!/bin/bash

# Configuration paths for this script.
APP_PATH=
BACKUP_DIR=
SUPERVISOR_APP_NAME=

# Check dependencies
DEPENDENCIES="python pg_dump git tar pip sudo supervisorctl"
for d in $DEPENDENCIES ; do
    o="`which $d 2>&1`"
    if [ $? -ne 0 ] ; then
        echo "Error: required dependency \"$d\" not installed or on PATH:"
        echo "$o"
        exit 9
    fi
done

# Arguments check.
if [ $# -gt 2 ] || [ "$1" = "--help" ] ; then
    echo "Usage: deploy.sh [--no-backup]    run the script, optionally not taking a backup (default: backup to $BACKUP_DIR)"
    echo "                  --help          display this usage information"
    echo
    echo "The script will operate on the app located at $APP_PATH. You can change"
    echo "this and the location of backups by setting \$APP_PATH and \$BACKUP_DIR at the top of this file ($0)."
    [[ $# -gt 2 ]] && exit 1
    exit 0
fi

# Set up environment. It is expected that the parent directory of APP_PATH
# is a virtualenv.
cd $APP_PATH && \
source ../bin/activate 2>/dev/null
if [ $? -ne 0 ] ; then
    echo "Error: The parent directory of $APP_PATH is not a virtualenv."
    exit 2
fi

set -e

# Extract database name from settings.
DB_NAME=`python -c 'import settings ; print settings.DATABASES["default"]["NAME"]'`

# Silence Django's management commands
DJANGO_MANAGE_ARGS="-v 0 --noinput"

# Rotate the backup directory. We do this regardless of
# whether we are backing up the app or not.
if [ -d $BACKUP_DIR ] ; then
    last=$BACKUP_DIR.last
    if [ -d $last ] ; then
        rm -rf $last
    fi
    mv $BACKUP_DIR $last
fi
mkdir -p $BACKUP_DIR

# Make a backup of the app, or don't
if [ "$1" = "--no-backup" ] ; then
    echo "backup: not taking a backup (--no-backup given).."
else
    echo "backup: taking backup of app ($PWD) and database ($DB_NAME).."
    pg_dump $DB_NAME > $BACKUP_DIR/before_update.sql
    git status > $BACKUP_DIR/before_update.gitstatus
    git log -n 1 >> $BACKUP_DIR/before_update.gitstatus
    tar -cjf $BACKUP_DIR/before_update.tar.bz2 ../$(basename $APP_PATH)
fi

echo "git: pulling from origin.."
git pull -q

echo "pip: installing/updating dependencies.."
pip install -q -r requirements.txt

echo "django: applying migrations.."
python manage.py migrate $DJANGO_MANAGE_ARGS

echo "django: collecting static files.."
python manage.py collectstatic $DJANGO_MANAGE_ARGS

echo "supervisor: reloading the app (using sudo).."
sudo supervisorctl restart $SUPERVISOR_APP_NAME >/dev/null

echo "Completed. Updated to:"
git log -n 1

exit 0
