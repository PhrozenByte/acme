#!/bin/bash
# Renew Let's Encrypt SSL certificates using acme-tiny 
# Version 1.0 (build 20160123)
#
# Copyright (C) 2016  Daniel Rudolf <www.daniel-rudolf.de>
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

VERSION="1.0"
BUILD="20160123"

if [ "$(id -u)" != "0" ]; then
    echo "$APP_NAME: You must run this as root" >&2
    exit 1
elif [ "$(sudo -u acme -- id -un)" != "acme" ]; then
    echo "$APP_NAME: User 'acme' not found or not sudo-able" >&2
    exit 1
elif [ ! -d "/etc/ssl/acme" ]; then
    echo "$APP_NAME: Base directory '/etc/ssl/acme' not found" >&2
    exit 1
elif [ ! -x "$(which acme-tiny)" ]; then
    echo "$APP_NAME: 'acme-tiny' executable not found" >&2
    exit 1
fi

function showUsage() {
    echo "Usage:"
    echo "  $APP_NAME --all"
    echo "  $APP_NAME DOMAIN_NAME..."
}

# read parameters
DOMAINS=""
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
        echo "Copyright (C) 2016 Daniel Rudolf"
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
        DOMAINS="$(find /etc/ssl/acme/live/ -mindepth 1 -printf "%f ")"
    elif [ -z "$DOMAINS" ]; then
        DOMAINS="$1"
    else
        DOMAINS+=" $1"
    fi

    shift
done
if [ -z "$DOMAINS" ]; then
    echo "$APP_NAME: You must either pass --all or a domain name" >&2
    showUsage
    exit 1
fi

# renew domains
EXIT_CODE=0
IFS=' '; for DOMAIN in $DOMAINS; do
    echo "# Renewing '$DOMAIN'..."
    DATE="$(date --utc +'%FT%TZ')"

    if [ ! -d "/etc/ssl/acme/live/$DOMAIN" ]; then
        echo "WARNING: No certificate to renew found; skipping..." >&2
        EXIT_CODE=1
        continue
    fi

    echo "Prepare target dir..."
    sudo -u acme -- mkdir -p "/etc/ssl/acme/archive/$DOMAIN/$DATE"

    echo "Copy CSR..."
    sudo -u acme -- cp "/etc/ssl/acme/live/$DOMAIN/csr.pem" "/etc/ssl/acme/archive/$DOMAIN/$DATE/"

    exec 3>&1
    sudo -u acme -- acme-tiny \
        --account-key "/etc/ssl/acme/account.key" \
        --csr "/etc/ssl/acme/archive/$DOMAIN/$DATE/csr.pem" \
        --acme-dir "/etc/ssl/acme/challenges" 2>&3 \
        | sudo -u acme -- tee "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" > /dev/null
    exec 3>&-

    if [ "$(head -n 1 "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem")" != "-----BEGIN CERTIFICATE-----" ]; then
        echo "ERROR: Invalid certificate '/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem'" >&2
        exit 1
    fi

    echo "Copy chain.pem..."
    sudo -u acme -- cp "/etc/ssl/acme/intermediate.pem" "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem"

    echo "Create fullchain.pem..."
    cat "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" \
        | sudo -u acme -- tee "/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem" > /dev/null

    echo "Copy private key..." # requires root
    cp -p "/etc/ssl/acme/live/$DOMAIN/key.pem" "/etc/ssl/acme/archive/$DOMAIN/$DATE/"

    echo "Deploy new certificate..."
    sudo -u acme -- rm "/etc/ssl/acme/live/$DOMAIN"
    sudo -u acme -- ln -s "/etc/ssl/acme/archive/$DOMAIN/$DATE/" "/etc/ssl/acme/live/$DOMAIN"
    echo "Certificate renewed!"

    echo
done
