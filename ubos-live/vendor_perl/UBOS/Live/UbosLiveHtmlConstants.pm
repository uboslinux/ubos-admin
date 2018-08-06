#!/usr/bin/perl
#
# Move bulk HTML constants out of the main code.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::UbosLiveHtmlConstants;

# The CSS
our $css = <<'CSS';
@import url("http://fonts.googleapis.com/css?family=Roboto+Slab:400,700,300,100");
@import url("http://fonts.googleapis.com/css?family=Roboto:400,700,500,300,100,900");

body {
    font-family: Roboto, Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.4;
    font-weight: 400;
    color: #111;
    background-color: #fdfdfd;
}
a,
a:visited {
    color: #111;
}
body, h2, h3, h4, h5, h6, hr {
    margin: 0;
    padding: 0;
}
h1 {
    margin: 20px 0 0 0;
    padding: 0;
}
p, blockquote, pre, ul, ol, dl, li, figure {
    margin: 15px 0;
}
pre {
    overflow: auto;
    font-size: 80%;
}
tt {
    font-size: 80%;
}
table {
    width: 100%;
    border-collapse: collapse;
}
td,
th {
    vertical-align: top;
    border: 1px solid #a0a0a0;
    padding: 3px 10px;
}
tbody > tr > th {
    text-align: left;
}

footer {
    margin-top: 40px;
    padding-top: 0px;
    border-top: 1px solid #808080;
    font-size: 80%;
}
iframe {
    width: 100%;
    border: 1px solid #808080;
    height: 400px;
}

div.devices {
    clear: both;
}

dl.device-details dt,
dl.device-details dd {
    display: inline;
    margin: 0;
    padding: 0;
}
dl.device-details dt:before {
    content: "\00B7";
    margin: 0 10px;
}
dl.device-details dt:first-child:before {
    content: "";
    margin: 0;
}

dl.appconfig {
    clear: both;
}
dl.appconfig dt {
    display: list-item;
    list-style-type: disc;
    list-style-position: inside;
}

div.admin {
    float: right;
    width: 50%;
}
table.admin > tbody > tr > th:nth-child(1) {
    width: 200px;
}
table.network > thead > tr > th:nth-child(1) {
    width: 160px;
}
table.network > thead > tr > th:nth-child(2) {
    width: 100px;
}
table.network > thead > tr > th:nth-child(3) {
    width: 100px;
}
table.network > thead > tr > th:nth-child(4) {
    width: 150px;
}
table.network > thead > tr > th:nth-child(5) {
    width: 120px;
}
table.appconfig > thead > tr > th:nth-child(1) {
    width: 200px;
}
table.appconfig > thead > tr > th:nth-child(2) {
    width: 200px;
}
div.content {
    width: 980px;
    margin: 20px auto;
}
div.staff-icon {
    float: right;
    margin: 0 10px 10px 10px;
    padding: 0 0 10px 40px;
}
p.note {
    margin: 5px 20px 20px 20px;
}
span.note,
span.warn {
    float: left;
    margin: 0 10px 10px 0;
}
.sidenote {
    margin-left: 30px;
    font-size: 10px;
    vertical-align: middle;
    font-weight: normal;
}

div.keys,
div.wifi,
div.site-templates,
div.device {
    background: #f0f0f0;
    border: 1px solid #f0f0f0;
    padding-bottom: 10px;
    margin-top: 30px;
}
div.keys > h2,
div.wifi > h2,
div.site-templates > h2,
div.device > h2 {
    background: #e0e0e0;
    border: 1px solid #e0e0e0;
    padding: 5px 10px;
    margin-bottom: 20px;
}
div.keys div.keys-details,
div.device div.device-details,
div.device div.site,
div.device p.nosites {
    margin: 10px 20px;
    padding: 10px 20px;
    background-color: #fff;
}

div.managed {
    float: right;
    margin: 11px 20px 0 0;
}
a.reveal,
a.hide {
    text-decoration: underline;
}
.hide {
    display: none;
}
span.tt {
    font-family: monospace;
}

CSS

## The Javascript
our $javascript = <<'JAVASCRIPT';
function toggle( id ) {
    var e    = document.getElementById( id );
    var flag = e.style.display == 'block';
    e.style.display = flag ? 'none' : 'block';

    var eReveal = document.getElementsByClassName( id + "-reveal" );
    for( i=0; i<eReveal.length; ++i ) {
        eReveal[i].style.display = flag ? 'inline' : 'none';
    }

    var eHide = document.getElementsByClassName( id + "-hide" );
    for( i=0; i<eHide.length; ++i ) {
        eHide[i].style.display = flag ? 'none' : 'inline';
    }
}

function intPad2( i ) {
    if( i>=10 ) {
        return i;
    } else {
        return "0" + i;
    }
}

function calculateTimeUpdated( updated, id ) {
    if( !updated ) {
        return;
    }
    var parsed = updated.match( /^(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)$/ );
    var e    = document.getElementById( id );
    var now  = new Date();
    var then = new Date( Date.UTC( parsed[1], parsed[2]-1, parsed[3], parsed[4], parsed[5], parsed[6] ));

    var delta = ( now.getTime() - then.getTime()) / 1000;

    var relative;
    if( delta > 13 * 30 * 24 * 60 * 60 ) {
        relative = "more than a year";
    } else if( delta > 11 * 30 * 24 * 60 * 60 ) {
        relative = "about a year";
    } else if( delta > 45 * 24 * 60 * 60 ) {
        relative = "about " + Math.round( delta / ( 30 * 24 * 60 * 60 )) + " months";
    } else if( delta > 72 * 60 * 60 ) {
        relative = "about " + Math.round( delta / ( 24 * 60 * 60 )) + " days";
    } else if( delta > 110 * 60 ) {
        relative = "about " + Math.round( delta / ( 60 * 60 )) + " hours";
    } else if( delta > 50 * 60 ) {
        relative = "about an hour";
    } else if( delta > 90 ) {
        relative = "about " + Math.round( delta / 60 ) + " minutes";
    } else {
        relative = "about a minute";
    }

    e.innerHTML = "Updated:&nbsp;"
                + then.getUTCFullYear()
                + "-"      + intPad2( then.getUTCMonth()+1 )
                + "-"      + intPad2( then.getUTCDate())
                + "&nbsp;" + intPad2( then.getUTCHours())
                + ":"      + intPad2( then.getUTCMinutes())
                + ":"      + intPad2( then.getUTCSeconds())
                + "&nbsp;UTC"
                + " (" + relative + "&nbsp;ago)";
    e.classList.remove( "hide" );
}
JAVASCRIPT

## inlined images
our $staffImage = '<img width=63 height=137 src="data:image/png;base64,UBOS_STAFF_IMAGE_BASE64">';
our $helpImage  = '<img width=24 height=24 src="data:image/png;base64,HELP_IMAGE_BASE64">';

1;
