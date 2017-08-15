#!/bin/bash
# Issue Let's Encrypt SSL certificates using acme-tiny
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
        echo "Copyright (C) 2016-2017 Daniel Rudolf"
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
    --acme-dir "/etc/ssl/acme/challenges" 2>&3 \
    | sudo -u acme -- tee "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" > /dev/null

if ! openssl x509 -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid certificate '/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem'" >&2
    exit 1
fi

# download chain.pem from Let's Encrypt server
# bloody workaround for https://github.com/diafygi/acme-tiny/issues/77
# thanks to Patrick Figel (@patf), see https://github.com/diafygi/acme-tiny/pull/114
echo "Downloading and converting chain.pem..."
INTERMEDIATE_CERT_DER="$(sudo -u acme -- mktemp)"

sudo -u acme -- curl --silent --show-error --fail \
    --output "$INTERMEDIATE_CERT_DER" \
    https://acme-v01.api.letsencrypt.org/acme/issuer-cert

sudo -u acme -- openssl x509 \
    -in "$INTERMEDIATE_CERT_DER" -inform der \
    -out "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" -outform pem

sudo -u acme -- rm "$INTERMEDIATE_CERT_DER"

if ! openssl x509 -in "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" -noout > /dev/null 2>&1; then
    echo "$APP_NAME: Invalid chain '/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem'" >&2
    exit 1
fi

# create fullchain.pem
echo "Creating fullchain.pem..."
cat "/etc/ssl/acme/archive/$DOMAIN/$DATE/cert.pem" "/etc/ssl/acme/archive/$DOMAIN/$DATE/chain.pem" \
    | sudo -u acme -- tee "/etc/ssl/acme/archive/$DOMAIN/$DATE/fullchain.pem" > /dev/null

# symlink target dir in live dir
echo "Deploying certificate..."
[ -h "/etc/ssl/acme/live/$DOMAIN" ] && sudo -u acme -- rm "/etc/ssl/acme/live/$DOMAIN"
sudo -u acme -- ln -s "/etc/ssl/acme/archive/$DOMAIN/$DATE/" "/etc/ssl/acme/live/$DOMAIN"

exec 3>&-
exit 0
