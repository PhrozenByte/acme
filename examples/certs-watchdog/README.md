ACME Issue & Renew - Cert Watchdog
==================================

ACME Issue & Renew is a collection of scripts responsible for managing certificates. This doesn't include managing the services that use these certificates. Thus, even tough e.g. `acme-renew` just renewed a certificate, it doesn't necessarily mean that the service using this certificate (e.g. the Apache 'httpd' server) will ever use that new certificate. Often you must first restart the service, or at least reload the service's configuration (e.g. using `systemctl reload apache2.service`) so that it picks up the new certificate.

One approach to deal with this is a "certificate watchdog": A service running on your system constantly watching for certificate updates whose job is then to restart or reload the services using that certificate. To make things easier for you we've created a simple example script that uses [inotify](https://en.wikipedia.org/wiki/Inotify) to watch for certificate updates, and Systemd's [`sytemctl`](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html) to restart Systemd service units.

The provided [`acme-certs-watchdog` script](./acme-certs-watchdog) accepts three arguments: The first is either `--restart` or `--reload` determining whether the affected Systemd unit should be restarted or reloaded. The second is `SYSTEMD_UNIT` taking the name of the Systemd unit (e.g. `apache2.service`) to restart or reload. The third and all following arguments are paths to ACME directories containing domain certificates (e.g. `/var/local/acme/live/example.com/`). Please note that the script requires both `systemctl` and `inotifywait` to be installed on your system.

To use the `acme-certs-watchdog` script you must first install ACME Issue & Renew on your system. You can then install the `acme-certs-watchdog` script as follows:

```sh
cp ./examples/acme-certs-watchdog /usr/local/bin/acme-certs-watchdog
chmod +x /usr/local/bin/acme-certs-watchdog
```

You must then create a certificate watchdog service per Systemd service using one or more of your certificates. For example, if you're running the Apache 'httpd' server to serve the domains `example.com` and `example.net`, create the `apache2-certs-watchdog.service` unit, and let it start & stop with the `apache2.service` unit. The `apache2-certs-watchdog.service` unit will execute the `acme-certs-watchdog` script, which will automatically reload (1st argument `--reload`) the `apache2.service` unit (2nd argument `'apache2.service'`) when the certs of the `example.com` domain (3rd argument `'/var/local/acme/live/example.com/'`) and `example.net` domain (4th argument `'/var/local/acme/live/example.net/'`) are renewed.

Here's what you need to do on your system to set things up as described:

```sh
cat > /etc/systemd/system/apache2-certs-watchdog.service <<EOF
[Unit]
PartOf=apache2.service
After=apache2.service

[Service]
Type=exec
ExecStart=/usr/local/bin/acme-certs-watchdog --reload apache2.service /var/local/acme/live/example.com/ /var/local/acme/live/example.net/

[Install]
WantedBy=apache2.service
EOF

systemctl daemon-reload
systemctl enable apache2-certs-watchdog.service
systemctl is-active --quiet apache2.service && systemctl restart apache2.service
```
