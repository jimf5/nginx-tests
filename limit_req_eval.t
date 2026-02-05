#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for http eval module with limit req module.

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

my $t = Test::Nginx->new();

# plan(skip_all => 'no eval support yet') unless $t->has_version('1.29.6');

$t->has(qw/http limit_req eval/)->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=zone:1m   rate=1r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        eval dynamic.conf;
    }
}

EOF

$t->write_file('dynamic.conf', 'limit_req  zone=zone  burst=1  nodelay;');

$t->write_file('index.html', '');

$t->run()->plan(5);

###############################################################################

like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 1/1 - ok');
like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 2/1 - ok (burst=1)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 3/1 - rejected');

$t->write_file('tmp.conf', 'limit_req  zone=zone  burst=2  nodelay;');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file change to be noticed

like(http_get('/'), qr/^HTTP\/1.. 200 /m, 'req 3/1 (updated) - ok (burst=2)');
like(http_get('/'), qr/^HTTP\/1.. 503 /m, 'req 4/1 (updated) - rejected');

###############################################################################
