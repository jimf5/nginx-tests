#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http eval module with grpc.

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

$t->has(qw/http http_v2 eval/)->write_file_expand('nginx.conf', <<'EOF');

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

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        http2 on;
    }
}

EOF

$t->write_file_expand('dynamic.conf', 'grpc_pass grpc://127.0.0.1:8081;');

$t->write_file('index.html', 'SEE-THIS');

$t->run()->plan(1);

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'location from file');

###############################################################################
