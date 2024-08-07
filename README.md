ACME Issue & Renew
==================

[`acme-issue`](./src/acme-issue), [`acme-renew`](./src/acme-renew) and [`acme-check`](./src/acme-check) (formerly known as `letsencrypt-issue` and `letsencrypt-renew`) are a collection of small management scripts for [acme-tiny](https://github.com/diafygi/acme-tiny) to issue TLS certificates with [Let's Encrypt](https://letsencrypt.org/).

The scripts use a very simple directory structure below `/var/local/acme` to manage your certs and to allow a fail-safe auto renewal of certs. All certs and associated files life below `/var/local/acme/archive` inside domain-specific sub-folders. When issuing a new or renewing an existing cert, `acme-issue` will create a directory with the current date and time (e.g. `/var/local/acme/archive/example.com/2021-10-01T04:49:34Z`) and put the necessary files there, namely

* `cert.pem`: The cert signed by the Certificate Authority (CA; Let's Encrypt by default).
* `chain.pem`: Any intermediate certs used by the CA to sign the cert, empty otherwise.
* `fullchain.pem`: The composition of `cert.pem` and `chain.pem`.
* `key.pem`: The private key used. The script will create a new private key for every signing request.
* `csr.pem`: The CSR (Certificate Signing Request) used to issue the cert.

In the course of signing a cert, acme-tiny will communicate with your CA using the [ACME protocol](https://en.wikipedia.org/wiki/Automated_Certificate_Management_Environment). It uses `HTTP-01` challenges to verify that you're actually authorized to issue certs for the requested domains. To do so it creates challenge files that your webserver must publish below `http://example.com/.well-known/acme-challenge/`. These files are created in `/var/local/acme/challenges`. Make sure that your webserver publishes all files within this directory at the mentioned URL.

`acme-issue` will always check whether it actually succeeded and the files contain valid certs. If `acme-issue` fails, it simply leaves the files there and bails. If it succeeds, it will copy `cert.pem`, `chain.pem`, `fullchain.pem` and `key.pem` to a matching sub-folder below `/var/local/acme/live` for your services to use. Point your software to the files in this directory (e.g. `/var/local/acme/live/example.com/cert.pem`) and you're ready to go!

When renewing certs using `acme-renew`, remember to also restart your services, so that they actually pick up the new cert. It's usually best to let services deal with restarting themselves, e.g. using an inotify-based certs watchdog. It's recommended to renew all certificates once a month (e.g. using a cronjob).

Additionally you can use `acme-check` to check validity of managed certificates (e.g. whether a certificate was revoked). If a certificate is deemed invalid by `acme-check`, you should renew it (`acme-check` allows you to do that automatically). You should check certificate validity regularly (e.g. daily using a cronjob).

Before signing certs you must create a ACME account private key. The scripts' config is stored below `/etc/acme`. Simply create a `account.key` there by executing `openssl genrsa 4096 > /etc/acme/account.key`. If you're there you can also take a look at the scripts' [`/etc/acme/config.env`](./conf/config.env). It is highly recommended to leave contact information with your CA (variable `ACME_ACCOUNT_CONTACT`) there. This is even mandatory for some CAs. acme-tiny can sign certs with any ACME-capable CA, it just defaults to Let's Encrypt. If you want to switch to another CA, simply change the `ACME_DIRECTORY_URL` variable in `config.env`. You can also change the associated group of private key files there (variable `TLS_KEY_GROUP`).

Made with :heart: by [Daniel Rudolf](https://www.daniel-rudolf.de). ACME Issue & Renew is free and open source software, released under the terms of the [MIT license](./LICENSE).

Usage
-----

Use `acme-issue` to issue a new cert for a domain and optional domain aliases, or renew a single existing cert:

```
Usage:
  acme-issue [--force] DOMAIN_NAME [DOMAIN_ALIAS...]
  acme-issue --renew DOMAIN_NAME

Options:
  -r, --renew      renew an existing certificate
  -f, --force      issue a new certificate even though there is another
                   certificate for this DOMAIN_NAME
      --no-verify  don't verify the certificate after issuance

Help options:
  -h, --help     display this help and exit
      --version  output version information and exit

Environment:
  ACME_ACCOUNT_KEY_FILE  path to your ACME account private key
  ACME_ACCOUNT_CONTACT   contact details for your account
  ACME_DIRECTORY_URL     ACME directory URL of the CA to use
  TLS_KEY_GROUP          associated group for TLS key files
```

Use `acme-renew` to renew a single, multiple, or all known certs:

```
Usage:
  acme-renew [--verbose|--quiet] [--retry...] [--clean] --all
  acme-renew [--verbose|--quiet] [--retry...] DOMAIN_NAME...

Options:
  -a, --all        renew all certificates
  -c, --clean      remove dangling challenges on success; requires --all
  -r, --retry      retry if renewal fails; can be passed multiple times
      --no-verify  don't verify the certificate after renewal
  -v, --verbose    explain what is being done
  -q, --quiet      suppress status information

Help options:
  -h, --help     display this help and exit
      --version  output version information and exit

Environment:
  ACME_ACCOUNT_KEY_FILE  path to your ACME account private key
  ACME_ACCOUNT_CONTACT   contact details for your account
  ACME_DIRECTORY_URL     ACME directory URL of the CA to use
  TLS_KEY_GROUP          associated group for TLS key files
```

Use `acme-check` to check validity of a single, multiple, or all known certs:

```
Usage:
  acme-check [--verbose|--quiet] --all
  acme-check [--verbose|--quiet] DOMAIN_NAME...

Options:
  -a, --all          check all certificates
  -r, --renew        renew certificates that are deemed invalid
      --retry-renew  retry if renewal fails; can be passed multiple times
  -v, --verbose      explain what is being done
  -q, --quiet        suppress status information

Help options:
  -h, --help     display this help and exit
      --version  output version information and exit

Environment:
  FP_REVOCATION_LIST     path to a list of revoked certificate fingerprints
  ACME_ACCOUNT_KEY_FILE  path to your ACME account private key
  ACME_ACCOUNT_CONTACT   contact details for your account
  ACME_DIRECTORY_URL     ACME directory URL of the CA to use
  TLS_KEY_GROUP          associated group for TLS key files
```

Setup
-----

`acme-issue`, `acme-renew` and `acme-check` all require [OpenSSL](https://www.openssl.org/) and [acme-tiny](https://github.com/diafygi/acme-tiny).

The scripts were written to work with [GNU Bash](https://www.gnu.org/software/bash/) (any more or less recent version), but *SHOULD* work with other advanced shells, too. If you want to make `acme-issue`, `acme-renew` and `acme-check` compatible with your favorite shell, please go ahead and let me know, I very much appreciate it!

Below you'll find all steps required to set up `acme-issue`, `acme-renew` and `acme-check`. However, you **MUST** read, understand and edit these commands to fit your setup. **DO NOT EXECUTE THEM AS-IS!**

```sh
# download and install latest version of acme-tiny
# all credit goes to these awesome people!
wget -O /usr/local/bin/acme-tiny https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py
chmod +x /usr/local/bin/acme-tiny

# add acme user
adduser --system --home /var/local/acme --no-create-home --disabled-login --disabled-password --group acme
usermod -aG www-data acme

# create acme base and config dir
mkdir /var/local/acme/{,live,archive} /etc/acme
chown acme:acme /var/local/acme/{live,archive}

# create acme-challenge directory
mkdir -p /var/www/html/.well-known/acme-challenge
chown acme:www-data /var/www/html/.well-known/acme-challenge
ln -s /var/www/html/.well-known/acme-challenge/ /var/local/acme/challenges

# configure Apache to serve acme-challenge directory
cat > /etc/apache2/conf-available/acme-challenge.conf <<EOF
Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/
<Directory "/var/www/html/.well-known/acme-challenge/">
    Options None
    AllowOverride None

    ForceType text/plain
    RedirectMatch 404 "^(?!/\.well-known/acme-challenge/[\w-]{43}$)"
</Directory>
EOF
a2enconf acme-challenge
systemctl reload apache2.service

# create config file and set 'ACME_ACCOUNT_CONTACT'
cp ./conf/config.env /etc/acme/config.env
chown acme:acme /etc/acme/config.env
sed -i '/^#ACME_ACCOUNT_CONTACT=""$/a ACME_ACCOUNT_CONTACT="certs@example.com"' /etc/acme/config.env

# create Let's Encrypt account key
( umask 027 && openssl genrsa 4096 > /etc/acme/account.key )
chmod 640 /etc/acme/account.key
chown acme:acme /etc/acme/account.key

# install scripts
cp ./src/acme-issue /usr/local/bin/acme-issue
cp ./src/acme-renew /usr/local/bin/acme-renew
cp ./src/acme-check /usr/local/bin/acme-check
chmod +x /usr/local/bin/acme-{issue,renew,check}

# OPTIONAL: install daily `acme-check` and monthly `acme-renew` cronjobs
# check out the instructions in ./examples/cron/

# OPTIONAL: install and setup certs watchdog script
# check out the instructions and example script in ./examples/certs-watchdog/
```

Upgrade
-------

If you're currently running `letsencrypt-issue` v1.6 or older, you might ask yourself how to upgrade to `acme-issue` v1.8 or later. Simply check the steps below, but as with the install instructions, you **MUST** read, understand and edit these commands to fit your setup. To upgrade later versions of `acme-issue` just replace the `acme-issue`, `acme-renew` and `acme-check` script files with their respective new version.

```sh
# create new base and config dir
mkdir /var/local/acme /etc/acme

# create config file
cp ./conf/config.env /etc/acme/config.env
chown acme:acme /etc/acme/config.env

# RECOMMENDED: set 'ACME_ACCOUNT_CONTACT' config variable
sed -i '/^#ACME_ACCOUNT_CONTACT=""$/a ACME_ACCOUNT_CONTACT="certs@example.com"' /etc/acme/config.env

# OPTIONAL: set 'TLS_KEY_GROUP' config variable
sed -i '/^#TLS_KEY_GROUP=""$/a TLS_KEY_GROUP="ssl-cert"' /etc/acme/config.env

# move account.key
mv /etc/ssl/acme/account.key /etc/acme/account.key

# move live certs one after another (don't just copy/move the existing dir)
mkdir /var/local/acme/live
chown acme:acme /var/local/acme/live

for DOMAIN_PATH in /etc/ssl/acme/live/*; do
    DOMAIN="$(basename "$DOMAIN_PATH")"
    mkdir /var/local/acme/live/"$DOMAIN"
    chown acme:acme /var/local/acme/live/"$DOMAIN"

    cp -p -t /var/local/acme/live/"$DOMAIN"/ \
        "$DOMAIN_PATH"/{key,cert,chain,fullchain}.pem
done

# move cert archive and challenges
mv -t /var/local/acme/ /etc/ssl/acme/{archive,challenges}

# install scripts
cp ./src/acme-issue /usr/local/bin/acme-issue
cp ./src/acme-renew /usr/local/bin/acme-renew
cp ./src/acme-check /usr/local/bin/acme-check
chmod +x /usr/local/bin/acme-{issue,renew,check}

# create symlinks for old scripts
rm -f /usr/local/bin/letsencrypt-{issue,renew}
ln -s /usr/local/bin/acme-issue /usr/local/bin/letsencrypt-issue
ln -s /usr/local/bin/acme-renew /usr/local/bin/letsencrypt-renew

# delete old dir
rm -rf /etc/ssl/acme

# remove old renewable cronjob
rm /etc/cron.monthly/letsencrypt

# OPTIONAL: install daily `acme-check` and monthly `acme-renew` cronjobs
# check out the instructions in ./examples/cron/

# OPTIONAL: install and setup certs watchdog script
# check out the instructions and example script in ./examples/certs-watchdog/
```
