ACME Issue & Renew - Cronjobs
=============================

Certificate management is a permanent task, not just a repeating task. Thus, automatization is key. ACME Issue & Renew fully supports automatization of certificate renewals using [cronjobs](https://en.wikipedia.org/wiki/Cron), and has a dedicated script for this task (using `acme-renew`).

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

2. Otherwise you can use the `/etc/cron.d` directory to add a monthly cronjob for the `acme` user like the following:
    ```sh
    cat >> /etc/cron.d/acme <<EOF
    23 4 3 * * acme-renew --all --retry --clean --verbose
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


Reloading renewed certificates
------------------------------

Remember that ACME Issue & Renew isn't responsible for the services using the certificates it obtained, it just manages the certificates. This means that even tough e.g. `acme-renew` just renewed a certificate, it doesn't necessarily mean that the service using this certificate (e.g. the Apache 'httpd' server) will ever use that new certificate. Often you must first restart the service, or at least reload the service's configuration (e.g. using `systemctl reload apache2.service`) so that it picks up the new certificate.

Since how this can be achieved differs wildly from service to service, you're on your own here. The easiest solution is to simply add the commands required to restart or reload the services to the cronjobs introduced earlier.
