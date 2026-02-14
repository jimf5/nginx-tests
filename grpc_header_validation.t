#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http header validation with grpc module.

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

plan (skip_all => 'not yet') unless $t->has_version('1.29.6');

$t->has(qw/http grpc proxy rewrite/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            grpc_pass grpc://127.0.0.1:8081;
        }
    }
    server {
        listen 127.0.0.1:8081;
        server_name localhost;

        http2 on;

        location /1 {
            add_header 'X-Foo"' bar;
            return 204;
        }
        location /2 {
            add_header 'X-Foo(' bar;
            return 204;
        }
        location /3 {
            add_header 'X-Foo)' bar;
            return 204;
        }
        location /4 {
            add_header 'X-Foo,' bar;
            return 204;
        }
        location /5 {
            add_header 'X-Foo/' bar;
            return 204;
        }
        location /6 {
            add_header 'X-Foo:' bar;
            return 204;
        }
        location /7 {
            add_header 'X-Foo;' bar;
            return 204;
        }
        location /8 {
            add_header 'X-Foo<' bar;
            return 204;
        }
        location /9 {
            add_header 'X-Foo>' bar;
            return 204;
        }
        location /10 {
            add_header 'X-Foo=' bar;
            return 204;
        }
        location /11 {
            add_header 'X-Foo?' bar;
            return 204;
        }
        location /12 {
            add_header 'X-Foo@' bar;
            return 204;
        }
        location /13 {
            add_header 'X-Foo[' bar;
            return 204;
        }
        location /14 {
            add_header 'X-Foo]' bar;
            return 204;
        }
        location /15 {
            add_header 'X-Foo\\' bar;
            return 204;
        }
        location /16 {
            add_header 'X-Foo{' bar;
            return 204;
        }
        location /17 {
            add_header 'X-Foo}' bar;
            return 204;
        }
    }
}

EOF

$t->run()->plan(17);

###############################################################################

my @c = split '', ' "(),/:;<=>?@[\]{}';
for $_ (1..17) {
	like(http_get("/$_"), qr/ 502 Bad Gateway/, "'$c[$_]' not allowed");
}

###############################################################################
