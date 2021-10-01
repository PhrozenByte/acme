ACME Issue & Renew
==================

```sh
# download and install latest version of acme-tiny
# all credit goes to these awesome people!
wget -O /usr/local/bin/acme-tiny https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py
chmod +x /usr/local/bin/acme-tiny

# add acme user
adduser --system --home /etc/ssl/acme --no-create-home --disabled-login --disabled-password --group acme
usermod -aG www-data acme
usermod -aG ssl-cert acme

# create acme base dir
mkdir /etc/ssl/acme/{,live,archive}
chown acme:acme /etc/ssl/acme/{,live,archive}

# create Let's Encrypt account key
( umask 027 && openssl genrsa 4096 > /etc/ssl/acme/account.key )
chmod 640 /etc/ssl/acme/account.key
chown acme:acme /etc/ssl/acme/account.key

# create acme-challenge directory
mkdir -p /var/www/html/.well-known/acme-challenge
chown acme:www-data /var/www/html/.well-known/acme-challenge
ln -s /var/www/html/.well-known/acme-challenge/ /etc/ssl/acme/challenges

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
service apache2 reload

# install scripts
mv acme-issue /usr/local/sbin/acme-issue
mv acme-renew /usr/local/sbin/acme-renew
chmod +x /usr/local/sbin/acme-{issue,renew}

# install monthly renewable cronjob
cat > /etc/cron.monthly/acme <<EOF
#!/bin/sh
acme-renew --all --verbose
EOF
chmod +x /etc/cron.monthly/acme
```
