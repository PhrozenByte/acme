ACME Issue & Renew
==================

[`acme-issue`](./src/acme-issue) and [`acme-renew`](./src/acme-renew) are two small management scripts for [acme-tiny](https://github.com/diafygi/acme-tiny) to issue TLS certificates with [Let's Encrypt](https://letsencrypt.org/).

The scripts use a very simple directory structure below `/var/local/acme` to manage your certs and to allow a fail-safe auto renewal of certs. All certs and associated files life below `/var/local/acme/archive` inside domain-specific sub-folders. When issuing a new or renewing an existing cert, `acme-issue` will create a directory with the current date and time (e.g. `/var/local/acme/archive/example.com/2021-10-01T04:49:34Z`) and put the necessary files there, namely

* `cert.pem`: The cert signed by the Certificate Authority (CA; Let's Encrypt by default).
* `chain.pem`: Any intermediate certs used by the CA to sign the cert, empty otherwise.
* `fullchain.pem`: The composition of `cert.pem` and `chain.pem`.
* `key.pem`: The private key used. The script will create a new private key for every signing request.
* `csr.pem`: The CSR (Certificate Signing Request) used to issue the cert.

In the course of signing a cert, acme-tiny will communicate with your CA using the [ACME protocol](https://en.wikipedia.org/wiki/Automated_Certificate_Management_Environment). It uses `HTTP-01` challenges to verify that you're actually authorized to issue certs for the requested domains. To do so it creates challenge files that your webserver must publish below `http://example.com/.well-known/acme-challenge/`. These files are created in `/var/local/acme/challenges`. Make sure that your webserver publishes all files within this directory at the mentioned URL.

`acme-issue` will always check whether it actually succeeded and the files contain valid certs. If `acme-issue` fails, it simply leaves the files there and bails. If it succeeds, it will copy `cert.pem`, `chain.pem`, `fullchain.pem` and `key.pem` to a matching sub-folder below `/var/local/acme/live` for your services to use. Point your software to the files in this directory (e.g. `/var/local/acme/live/example.com/cert.pem`) and you're ready to go! When renewing certs (e.g. with cron), remember to also restart your services, so that they actually pick up the new cert.

Before signing certs you must create a ACME account private key. The scripts' config is stored below `/etc/acme`. Simply create a `account.key` there by executing `openssl genrsa 4096 > /etc/acme/account.key`. If you're there you can also take a look at the scripts' [`/etc/acme/config.env`](./conf/config.env). It is highly recommended to leave contact information with your CA (variable `ACME_ACCOUNT_CONTACT`) there. This is even mandatory for some CAs. acme-tiny can sign certs with any ACME-capable CA, it just defaults to Let's Encrypt. If you want to switch to another CA, simply change the `ACME_DIRECTORY_URL` variable in `config.env`. You can also change the associated group of private key files there (variable `TLS_KEY_GROUP`).

Usage
-----

Use `acme-issue` to issue a new cert for a domain and optional domain aliases, or renew a single existing cert:

```
Usage:
  acme-issue [--force] DOMAIN_NAME [DOMAIN_ALIAS...]
  acme-issue --renew DOMAIN_NAME

Options:
  -r, --renew  renew an existing certificate
  -f, --force  issue a new certificate even though there is another
               certificate for this DOMAIN_NAME

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
  acme-renew [OPTIONS...] --all
  acme-renew [OPTIONS...] DOMAIN_NAME...

Options:
  -a, --all      renew all certificates
  -r, --retry    retry if renewal fails
  -v, --verbose  explain what is being done
  -q, --quiet    suppress status information

Help options:
  -h, --help     display this help and exit
      --version  output version information and exit

Environment:
  ACME_ACCOUNT_KEY_FILE  path to your ACME account private key
  ACME_ACCOUNT_CONTACT   contact details for your account
  ACME_DIRECTORY_URL     ACME directory URL of the CA to use
  TLS_KEY_GROUP          associated group for TLS key files
```

Setup
-----

`acme-issue` and `acme-renew` both require [OpenSSL](https://www.openssl.org/) and [acme-tiny](https://github.com/diafygi/acme-tiny).

The scripts were written to work with [GNU Bash](https://www.gnu.org/software/bash/) (any more or less recent version), but *SHOULD* work with other advanced shells, too. If you want to make `acme-issue` and `acme-renew` compatible with your favorite shell, please go ahead and let me know, I very much appreciate it!

Below you'll find all steps required to set up `acme-issue` and `acme-renew`. However, you **MUST** read, understand and edit these commands to fit your setup. **DO NOT EXECUTE THEM AS-IS!**

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
chmod +x /usr/local/bin/acme-{issue,renew}

# install monthly renewable cronjob
cat > /etc/cron.monthly/acme <<EOF
#!/bin/sh
sudo -u acme -- acme-renew --all --verbose --retry
# add commands to restart/reload services using these certs
EOF
chmod +x /etc/cron.monthly/acme
```
