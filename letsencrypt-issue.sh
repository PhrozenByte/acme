#!/bin/bash
# Issue Let's Encrypt SSL certificates using acme-tiny
# Version 1.6 (build 20200919)
#
# Copyright (C) 2016-2020  Daniel Rudolf <www.daniel-rudolf.de>
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

VERSION="1.6"
BUILD="20200919"

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
    echo "  $APP_NAME [--force] DOMAIN_NAME [DOMAIN_ALIAS...]"
    echo "  $APP_NAME --renew DOMAIN_NAME"
}

# read parameters
RENEW="no"
FORCE="no"
DOMAIN=""
DOMAIN_ALIASES=()
while [ $# -gt 0 ]; do
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        showUsage
        echo
        echo "Options:"
        echo "  -r, --renew   renew a existing certificate"
        echo "  -f, --force   issue a new certificate even though there is another"
        echo "                certificate for this DOMAIN_NAME"
        echo
        echo "Help options:"
        echo "  -h, --help      display this help and exit"
        echo "      --version   output version information and exit"
        exit 0
    elif [ "$1" == "--version" ]; then
        echo "letsencrypt-issue.sh $VERSION ($BUILD)"
        echo "Copyright (C) 2016-2020 Daniel Rudolf"
        echo "License GPLv3: GNU GPL version 3 only <http://gnu.org/licenses/gpl.html>."
        echo "This is free software: you are free to change and redistribute it."
        echo "There is NO WARRANTY, to the extent permitted by law."
        echo
        echo "Written by Daniel Rudolf <http://www.daniel-rudolf.de/>"
        exit 0
    elif [ "$1" == "--renew" ] || [ "$1" == "-r" ]; then
        RENEW="yes"
    elif [ "$1" == "--force" ] || [ "$1" == "-f" ]; then
        FORCE="yes"
    elif [ -z "$DOMAIN" ]; then
        DOMAIN="$1"
    else
        DOMAIN_ALIASES+=( "$1" )
    fi

    shift
done

if [ -z "$DOMAIN" ]; then
    echo "$APP_NAME: You must pass a DOMAIN_NAME" >&2
    showUsage
    exit 1
fi

# check target directory
if [ "$RENEW" == "no" ]; then
    if [ -d "/etc/ssl/acme/archive/$DOMAIN" ] && [ "$FORCE" == "no" ]; then
        echo "$APP_NAME: Conflicting target directory '/etc/ssl/acme/archive/$DOMAIN' found" >&2
        echo "$APP_NAME: Use --force to suppress this error" >&2
        exit 1
    fi
else
    if [ ! -d "/etc/ssl/acme/live/$DOMAIN" ]; then
        echo "$APP_NAME: No certificate to renew found" >&2
        exit 1
    fi
fi

# prepare subjectAltName (SAN)
SAN=""
if [ "$RENEW" == "no" ]; then
    SAN="DNS:$DOMAIN"
    for DOMAIN_ALIAS in "${DOMAIN_ALIASES[@]}"; do
        SAN+=", DNS:$DOMAIN_ALIAS"
    done
else
    if [ ${#DOMAIN_ALIASES[@]} -gt 0 ]; then
        echo "$APP_NAME: You mustn't pass domain aliases when renewing a certificate" >&2
        echo "$APP_NAME: Use --force instead of --renew to issue a new certificate" >&2
        exit 1
    fi

    SAN="$(openssl x509 -noout -text -in "/etc/ssl/acme/live/$DOMAIN/cert.pem" \
        | awk '/X509v3 Subject Alternative Name/ {getline; sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print}')"
fi

# write to fd3 to indent output
exec 3> >(sed 's/^/    /g')

# create target directory
echo "Preparing target directory..."

DATE="$(date --utc +'%FT%TZ')"
sudo -u acme -- mkdir -p "/etc/ssl/acme/archive/$DOMAIN/$DATE"

# generate private key (requires root)
echo "Generating private key..."

( umask 027 && openssl genrsa -out "/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem" 4096 2>&3 )
chmod 640 "/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem"
chown root:ssl-cert "/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem"

if ! openssl rsa -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem" -check -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid private key '/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem'" >&2
    exit 1
fi

# create CSR
echo "Creating CSR..."

OPENSSL_CONFIG="$(sudo -u acme -- mktemp)"
cat "/etc/ssl/openssl.cnf" <(printf "[SAN]\nsubjectAltName=$SAN\n") \
    | sudo -u acme -- tee "$OPENSSL_CONFIG" > /dev/null

sudo -u acme -- openssl req -new -sha256 \
    -key "/etc/ssl/acme/archive/$DOMAIN/$DATE/key.pem" \
    -subj "/" -reqexts SAN -config "$OPENSSL_CONFIG" \
    -out "/etc/ssl/acme/archive/$DOMAIN/$DATE/csr.pem"

sudo -u acme -- rm "$OPENSSL_CONFIG"

if ! openssl req -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/csr.pem" -verify -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid CSR '/etc/ssl/acme/archive/$DOMAIN/$DATE/csr.pem'" >&2
    exit 1
fi

# issue certificate using acme-tiny
echo "Issuing certificate..."

sudo -u acme -- acme-tiny \
    --account-key "/etc/ssl/acme/account.key" \
    --csr "/etc/ssl/acme/archive/$DOMAIN/$DATE/csr.pem" \
    --acme-dir "/etc/ssl/acme/challenges" \
    --disable-check 2>&3 \
    | sudo -u acme -- tee "/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem" > /dev/null

if ! openssl x509 -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem" -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid certificate chain '/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem'" >&2
    exit 1
fi

# split fullchain.pem into cert.pem and chain.pem
echo "Splitting certificate chain..."

SPLIT_FILE=""
SPLIT_MATCH="no"
while IFS= read -r SPLIT_LINE; do
    if [ "$SPLIT_LINE" == "-----BEGIN CERTIFICATE-----" ]; then
        [ -z "$SPLIT_FILE" ] && SPLIT_FILE="cert.pem" || SPLIT_FILE="chain.pem"
        SPLIT_MATCH="yes"
    fi

    if [ "$SPLIT_MATCH" == "yes" ]; then
        echo "$SPLIT_LINE" | sudo -u acme -- tee -a "/etc/ssl/acme/archive/$DOMAIN/$DATE/$SPLIT_FILE" > /dev/null
    fi

    if [ "$SPLIT_LINE" == "-----END CERTIFICATE-----" ]; then
        SPLIT_MATCH="no"
    fi
done < "/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem"

if ! openssl x509 -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid certificate '/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem'" >&2
    exit 1
fi

if [ ! -e "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" ]; then
    sudo -u acme -- touch "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem"
elif ! openssl x509 -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid intermediate certificate(s) '/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem'" >&2
    exit 1
fi

# symlink target dir to live dir
echo "Deploying certificate..."
[ -h "/etc/ssl/acme/live/$DOMAIN" ] && sudo -u acme -- rm "/etc/ssl/acme/live/$DOMAIN"
sudo -u acme -- ln -s "/etc/ssl/acme/archive/$DOMAIN/$DATE/" "/etc/ssl/acme/live/$DOMAIN"

exec 3>&-
exit 0
