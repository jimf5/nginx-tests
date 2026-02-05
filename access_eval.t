#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http eval module with access module.

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

$t->has(qw/http access eval/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        eval dynamic.conf;
    }
}

EOF

$t->write_file('dynamic.conf', 'location / { allow all; }');

$t->write_file('index.html', 'SEE-THIS');

$t->run()->plan(2);

###############################################################################

like(http_get('/'), qr/200 OK.*SEE-THIS/s, 'location from file - 200');

$t->write_file('tmp.conf', 'location / { deny all; }');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file change to be noticed

like(http_get('/'), qr/ 403 Forbidden/, 'location from updated file - 403');

###############################################################################
