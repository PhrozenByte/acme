#!/bin/bash
echo "Read, understand and edit this file, don't just execute it!"
exit 1

# download and install latest version of acme-tiny
# all credit goes to those awesome guys!
wget -O /usr/local/bin/acme-tiny https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py
chown +x /usr/local/bin/acme-tiny

# add acme user
adduser --system --home /etc/ssl/acme --no-create-home --disabled-login --disabled-password --group acme
usermod -aG www-data acme
usermod -aG ssl-cert acme

# create acme base dir
mkdir /etc/ssl/acme/{,live,archive}
chown acme:acme /etc/ssl/acme/{,live,archive}

# create Let's Encrypt account key
( umask 027 && openssl genrsa 4096 > /etc/ssl/acme/account.key )
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
mv letsencrypt-issue.sh /usr/local/sbin/letsencrypt-issue
mv letsencrypt-renew.sh /usr/local/sbin/letsencrypt-renew
chmod +x /usr/local/sbin/letsencrypt-{issue,renew}

# install monthly renewable cronjob
cat > /etc/cron.monthly/letsencrypt <<EOF
#!/bin/sh
letsencrypt-renew --all
EOF
chmod +x /etc/cron.monthly/letsencrypt
