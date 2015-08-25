# Configuring Sendmail to use a smart host relay service

We are going to use exmail.qq.com as the smart host relay service on
FreeBSD 10.

## run the commands as root

```
pkg install sendmail+tls+sasl2 stunnel ca_root_nss
mkdir /etc/mail/auth
chmod 700 /etc/mail/auth
cd /etc/mail/certs
openssl dhparam -out dh.param 1024
cd /etc/mail
make              # this will create a file `hostname`.mc if it doesn't already exist
```

## edit /etc/mail/mailer.conf

```
sendmail        /usr/local/sbin/sendmail
send-mail       /usr/local/sbin/sendmail
mailq           /usr/local/sbin/sendmail
newaliases      /usr/local/sbin/sendmail
hoststat        /usr/local/sbin/sendmail
purgestat       /usr/local/sbin/sendmail
```

## edit and add in /etc/mail/\`hostname\`.mc

```
FEATURE(authinfo, `hash -o /etc/mail/auth/authinfo.db')
define(SMART_HOST, `[localhost]')
define(RELAY_MAILER_ARGS, `TCP $h 25465')
define(ESMTP_MAILER_ARGS, `TCP $h 25465')

MASQUERADE_AS(your.domain)
FEATURE(masquerade_envelope)

LOCAL_RULE_1
R$* <Tab> $@ SENDER
dnl
```

## edit /etc/mail/auth/authinfo

```
AuthInfo:127.0.0.1 "U:SENDER@your.domain" "P:password" "M:LOGIN PLAIN"
```

## edit /usr/local/etc/stunnel/stunnel.conf

```
debug = warning
chroot = /var/tmp/stunnel/
setuid = stunnel
setgid = stunnel
pid = /pid
verify = 2
CAfile = /usr/local/share/certs/ca-root-nss.crt

[ssmtp-client]
client = yes
accept = 127.0.0.1:25465
connect = smtp.exmail.qq.com.:465
```

## append in /etc/rc.conf

```
stunnel_enable="YES"
```

## run the commands as root

```
mkdir /var/tmp/stunnel
chown stunnel:stunnel /var/tmp/stunnel
ln -s /var/tmp/stunnel/pid /var/run/stunnel.pid
cd /etc/mail
makemap hash /etc/mail/auth/authinfo < /etc/mail/auth/authinfo
make install
service stunnel restart
service sendmail restart
```

## test

```
echo "This is a test" | mailx -s "TEST" test@domain.com
```

## REFERENCES

- https://www.freebsd.org/doc/handbook/outgoing-only.html
- http://lists.freebsd.org/pipermail/freebsd-questions/2004-February/035329.html
- http://rdist.root.org/2010/11/08/configure-outgoing-email-from-freebsd-with-sendmail/
- http://www.sendmail.com/sm/open_source/docs/m4/masquerading_relaying.html
- http://www.harker.com/sendmail/debug.ruleset.html
- http://www.oreilly.com/openbook/linag2/book/ch18.html#AUTOID-14923
