# Implementation notes on webfinger

To test webfinger, at least one app declaring a webfinger well-known entry
in its manifest, needs to be deployed to a site. At one of those apps, an
account foo@bar needs exist.

Then it can be tested with

curl -v http://site/.well-known/webfinger?resource=acct%3afoo@bar

