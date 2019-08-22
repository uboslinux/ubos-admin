# Implementation notes on LetsEncrypt

## Preface

There are surprisingly many cases that need to be supported. Ergo
it is not as simple as it may seem.

We say "LKC" ("LetsEncrypt key and cert") as a shorthand for key and cert
issued by LetsEncrypt.

We say "OKC" ("Other key and cert") as a shorthand for key and cert issued
by somebody other than LetsEncrypt (self-issued, or official.)

## Device-Events

The following events may occur that trigger the need to do something
LetsEncrypt-related:

* A Site is deployed; or redeployed; or the redeploy happens as part of a
  system update; or the site is restored from backup

  * The Site JSON makes no mention of TLS at all

    * The Site is currently deployed with LKC
      => Stash LKC

  * The Site JSON contains letsencrypt=true, but either 1) no LKC or
    2) expired LKC

    * The Site is currently not deployed.
      => If there is unexpired stashed LKC, unstash and use it.
         Else: Provision LKC synchronously, or fall back to http

    * The Site is currently deployed without TLS
      => If there is unexpired stashed LKC, unstash and use it.
         Else: Provision LKC synchronously, or fall back to http

    * The Site is currently deployed with OKC
      => If there is unexpired stashed LKC, unstash and use it.
         Else: Provision LKC synchronously, or fall back to http(keep old OKC?)

    * The Site is currently deployed with LKC
      => Keep configuration

  * The Site JSON contains LKC which has not expired

    * The Site is currently not deployed.
      => If there is unexpired stashed LKC, compare expiration dates and
         use the more recent one
         Else: use LKC from Site SJON

    * The Site is currently deployed without TLS
      => If there is unexpired stashed LKC, compare expiration dates and
         use the more recent one
         Else: use LKC from Site SJON

    * The Site is currently deployed with OKC
      => If there is unexpired stashed LKC, compare expiration dates and
         use the more recent one
         Else: use LKC from Site SJON

    * The Site is currently deployed with LKC
      => Compare expiration dates of the currently deployed LKC and the
         one in the Site JSON and use the more recent one

  * The Site JSON contains OKC

    * The Site is currently deployed with LKC
      => Stash LKC

* Undeploy:

  * The Site is currently deployed with LKC
    => Stash LKC

* Backup:

  * The Site is currently deployed with LKC
    => Store LCK

* The LetsEncrypt renewal timer expires
  => Renew LCK if needed

## Thoughts

* When the certbot renewal timer triggers, we want to know at least in
  some cases what happened during the certbot run. So let's give certbot
  a callback hook anyway.

* During device migration:

  * a Site that is currently deployed with LKC on the source device, is
    being backed up and then restored on the destination device, again
    with LKC. Because of DNS propagation delays, the destination cannot
    provision a cert from LetsEncrypt for some time. Because of this,
    we need to transmit the cert from the source device to the destination
    device, which then needs to use it.

  * That also needs to add the imported cert to the list of certs
    regularly checked for renewal.

* Need a mutex between the certbot.service invocation and running
  (certain variations of) ubos-admin

* We cannot use "certbot certificates" because it will only look at active
  (non-stashed) certificates.

## Design decisions

* We don't store any keys or certs in the Site JSONs at /ubos/lib/sites/*.json

* We add keys and certs upon public export of the Site JSON via:

  * ubos-admin showsite
  * ubos-admin listsites
  * ubos-admin backup

  by finding them in the directory where Apache uses them.

* Apache uses the certs in /etc/letsencrypt/live for LetsEncrypt,
  and for all others, we use "$sslDir/$siteId.{key,crt}". This is
  so that Apache uses the updated cert when certbot.service has
  renewed it, without needing to do anything beyond what certbot does
  already.

* When receiving letsencrypt certs via deploy or restore, we put them
  into /etc/letsencrypt and hope that certbot doesn't notice our
  sleight of hand.

* When modifying a site with valid LKC in a way that it is not used
  any more (redeploy http, redeploy with OKC, undeploy), we stash the
  LKC so that when testing with frequent deploy/undeploys, LetsEncrypt
  does not rate limit us.

* When deploying, redeploying or restoring a LetsEncrypt site that has
  LKC in the Site JSON, and also in /etc/letsencrypt (stash or non-stash),
  we compare the expiration dates on the certs, and use the one that
  is most recent. Even if the Site JSON has a different one.

## Definitions

* "Stashing LKC": move the key, cert, and related data out of the
  control of certbot so it will be saved, but certbot won't try and
  renew
* "Unstashing LKC": move the key, cert, and related data from the
  stack back under the control of certbot, so certbot will renew.
  However, we silently delete rather unstash a cert that is expired.
* "Restoring LKC": copy the key and cert from the Site JSON into
  control of certbot; add certbot metadata, so that certbot will renew
* "Store LKC": copy key and cert from letsencrypt into exported
  Site JSON
