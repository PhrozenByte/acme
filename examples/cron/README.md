ACME Issue & Renew - Cronjobs
=============================

Certificate management is a permanent task, not just a repeating task. Thus, automatization is key. Two major tasks arise from certificate management: Certificate renewal and certifacte validation. ACME Issue & Renew fully supports automatization using [cronjobs](https://en.wikipedia.org/wiki/Cron), and has dedicated scripts for both certificate renwal (using `acme-renew`), as well as certificate validation (using `acme-check`).

Please note that all snippets provided below are just examples, thus it might be necessary to adapt them to fit your individual setup.

Certificate renewal
-------------------

[Let's Encrypt](https://letsencrypt.org/) solely and many other Certificate Authorities (CAs) do support so called "short-lived certificates" with a maximum validity of usually 90 days. The most pressing reason why such certificates exist is the fact, that certificate revocation is broken: If a certificate must be revoked (e.g. due to a compromised private key), one can't really be sure that all clients will notice that. The consequences of this issue can be limited by using certificates that won't last for a long period anyway.

Thus, all certificates must be renewed after a maximum period of 90 days. Below you'll find some examples on how to achieve that. They all have in common that they call the `acme-renew` script monthly with the `--all` option, causing the script to renew all managed certificates regularly. Since we're running a cronjob, it's best practice to retry at least once after a failure (option `--retry`) and to remove dangling ACME challenges (option `--clean`). Remember that you must run all scripts using the unprivileged `acme` user.

1. Some Linux distributions provide `/etc/cron.daily`, `/etc/cron.weekly`, and `/etc/cron.monthly` directories to add custom cronjob scripts that run daily, weekly, or monthly respectively. If your Linux distribution supports these directories, simply add a monthly renewal script like the following:
    ```sh
    cat > /etc/cron.monthly/acme-renew <<EOF
    #!/bin/sh
    sudo -u acme -- acme-renew --all --retry --clean --verbose
    EOF
    
    chmod +x /etc/cron.monthly/acme-renew
    ```

2. Otherwise you can always fall back to the basic `/etc/crontab` file. On some Linux distributions you can also use a distinct file in the `/etc/cron.d` directory. Here's how to add a monthly cronjob for the `acme` user to `/etc/crontab`:
    ```sh
    cat >> /etc/crontab <<EOF
    23 4 3 * * acme acme-renew --all --retry --clean --verbose
    EOF
    ```

3. If you'd like to use a more modern alternative to cronjobs, a [Systemd timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) might be your solution. Create such Systemd timer with a matching Systemd service unit like the following:
    ```sh
    cat >> /etc/systemd/system/acme-renew.timer <<EOF
    [Timer]
    OnCalendar=monthly
    Persistent=true
    
    [Install]
    WantedBy=timers.target
    EOF
    
    cat >> /etc/systemd/system/acme-renew.service <<EOF
    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/acme-renew --all --retry --clean --verbose
    User=acme
    EOF
    
    systemctl daemon-reload
    systemctl enable acme-renew.timer
    ```

Certificate validation
----------------------

Sometimes things can go wrong and certificates get invalidated unscheduled. The most pressing issue are certificate revocations: For certain reasons certificates might be revoked at any time, e.g. due to compromised private keys, changing domain ownerships, or just an out of order replacement of old certificates. Furthermore, you're not the only one who might revoke your certificates: Certificate Authorities (CAs) can be required to revoke your certificates, too. For example, if a certificate was issued erroneous, CAs are required to revoke all affected certificates within 24 hours following the CA/Browser Forum (CABF) Baseline Requirements (BR).

Thus, you must expect your certificates to be revoked at basically any time. Below you'll find some examples on how to be prepared. They all have in common that they call the `acme-check` script daily. It's purpose is to verify a certificate's validity by ensuring that the certificate and all its intermediate certificates are valid X.509 certificates, form a complete and trusted chain, have not expired yet, match their supposed type and common name (CN), and have not been revoked. Revocation status is checked using the [OCSP](https://en.wikipedia.org/wiki/Online_Certificate_Status_Protocol) endpoint declared within the certificate. Alternatively, one can add the unique SHA-256 fingerprints of revoked certificates to a file whose path is configured using the `FP_REVOCATION_LIST` setting in `config.env`, or the matching environment variable when running `acme-check` (see `config.env` for details about this file). The `acme-check` script should be invoked using the `--all` option to check all managed certificates. Since we're running a cronjob, it's best practice to retry at least once if the OCSP and/or CRL validation fails (option `--retry`). Optionally you can even automatically renew any certificate that is deemed invalid (option `--renew`), multiple times if necessary (option `--retry-renew`). Note that runtime errors (like a failing OCSP and/or CRL validation due to network issues) never cause auto-renewals. Remember that you must run all scripts using the unprivileged `acme` user.

1. Again, you might use the `/etc/cron.daily`, `/etc/cron.weekly`, and `/etc/cron.monthly` directories of your Linux distribution. In this case, add a daily check script like the following:
    ```sh
    cat > /etc/cron.daily/acme-check <<EOF
    #!/bin/sh
    sudo -u acme -- acme-check --all --retry --renew --retry-renew --verbose
    EOF
    
    chmod +x /etc/cron.daily/acme-check
    ```

2. Otherwise you can use `/etc/crontab` to add a daily cronjob for the `acme` user like the following:
    ```sh
    cat >> /etc/crontab <<EOF
    53 3 * * * acme acme-check --all --retry --renew --retry-renew --verbose
    EOF
    ```

3. If you'd like to use a Systemd timer instead, try the following:
    ```sh
    cat >> /etc/systemd/system/acme-check.timer <<EOF
    [Timer]
    OnCalendar=daily
    Persistent=true
    
    [Install]
    WantedBy=timers.target
    EOF
    
    cat >> /etc/systemd/system/acme-check.service <<EOF
    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/acme-check --all --retry --renew --retry-renew --verbose
    User=acme
    EOF
    
    systemctl daemon-reload
    systemctl enable acme-check.timer
    ```


Reloading renewed certificates
------------------------------

Remember that ACME Issue & Renew isn't responsible for the services using the certificates it obtained, it just manages the certificates. This means that even tough e.g. `acme-renew` just renewed a certificate, it doesn't necessarily mean that the service using this certificate (e.g. the Apache 'httpd' server) will ever use that new certificate. Often you must first restart the service, or at least reload the service's configuration (e.g. using `systemctl reload apache2.service`) so that it picks up the new certificate.

Since how this can be achieved differs wildly from service to service, you're on your own here. The easiest solution is to simply add the commands required to restart or reload the services to the cronjobs introduced earlier. However, this has the major disadvantage that services are restarted or reloaded daily with the `acme-check` cronjob, even tough `acme-check` is just rarely renewing any certificate. Thus, we recommend to let the services deal with restarting themselves, e.g. using an [inotify](https://en.wikipedia.org/wiki/Inotify)-based certs watchdog. Check out the `acme-certs-watchdog/` directory in the `examples/` directory for details about that.
