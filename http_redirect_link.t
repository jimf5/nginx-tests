#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for redirect page link.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite/)
    ->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  host;

        location / { }

        location /return301 {
            return 301 /redirect;
        }

        location /return302 {
            absolute_redirect off;
            return 302 /redirect;
        }

        location /return307 {
            port_in_redirect off;
            return 307 /redirect;
        }

        location /return308 {
            server_name_in_redirect on;
            port_in_redirect off;
            return 308 /redirect;
        }
    }
}

EOF

$t->run()->plan(4);

###############################################################################

my $p = port(8080);

like(http_get('/return301'),
    qr|301 Moved Permanently.*<a href="http://localhost:$p/redirect">|s,
    '/return301 includes link to /redirect');
like(http_get('/return302'), qr|302 Found.*<a href="/redirect">|s,
    '/return302 includes link to /redirect');
like(http_get('/return307'),
    qr|307 Temporary Redirect.*<a href="http://localhost/redirect">|s,
    '/return307 includes link to /redirect');
like(http_get('/return308'),
    qr|308 Permanent Redirect.*<a href="http://host/redirect">|s,
    '/return308 includes link to /redirect');

###############################################################################
