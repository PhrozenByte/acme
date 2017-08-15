#!/bin/bash
# Renew Let's Encrypt SSL certificates using acme-tiny
# Version 1.3 (build 20170815)
#
# Copyright (C) 2016-2017  Daniel Rudolf <www.daniel-rudolf.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3 of the License only.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# See <http://www.gnu.org/licenses/> to receive a full-text-copy of
# the GNU General Public License.

APP_NAME="$(basename "$0")"
set -e

VERSION="1.3"
BUILD="20170815"

if [ ! -d "/etc/ssl/acme" ]; then
    echo "$APP_NAME: Base directory '/etc/ssl/acme' not found" >&2
    exit 1
elif [ ! -x "$(which letsencrypt-issue)" ]; then
    echo "$APP_NAME: 'letsencrypt-issue' executable not found" >&2
    exit 1
fi

function showUsage() {
    echo "Usage:"
    echo "  $APP_NAME --all"
    echo "  $APP_NAME DOMAIN_NAME..."
}

# read parameters
DOMAINS=()
while [ $# -gt 0 ]; do
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        showUsage
        echo
        echo "Options:"
        echo "  -a, --all       renew all certificates"
        echo "  -q, --quiet     suppress status information"
        echo
        echo "Help options:"
        echo "  -h, --help      display this help and exit"
        echo "      --version   output version information and exit"
        exit 0
    elif [ "$1" == "--version" ]; then
        echo "letsencrypt-renew.sh $VERSION ($BUILD)"
        echo "Copyright (C) 2016-2017 Daniel Rudolf"
        echo "License GPLv3: GNU GPL version 3 only <http://gnu.org/licenses/gpl.html>."
        echo "This is free software: you are free to change and redistribute it."
        echo "There is NO WARRANTY, to the extent permitted by law."
        echo
        echo "Written by Daniel Rudolf <http://www.daniel-rudolf.de/>"
        exit 0
    elif [ "$1" == "--quiet" ] || [ "$1" == "-q" ]; then
        # pipe stdout to /dev/null
        exec 1> /dev/null
    elif [ "$1" == "--all" ] || [ "$1" == "-a" ]; then
        while IFS="" read -r -u 4 -d $'\0' DOMAIN; do
            DOMAINS+=( "$DOMAIN" )
        done 4< <(find /etc/ssl/acme/live/ -mindepth 1 -printf "%f\0")
    else
        DOMAINS+=( "$1" )
    fi

    shift
done

if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo "$APP_NAME: You must either pass --all or a DOMAIN_NAME" >&2
    showUsage
    exit 1
fi

# renew every domain in a subprocess
EXIT_CODE=0
for DOMAIN in "${DOMAINS[@]}"; do
    echo "# Renewing '$DOMAIN'..."
    letsencrypt-issue --renew "$DOMAIN" || { EXIT_CODE=$?; true; }
    echo
done

exit $EXIT_CODE
