#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http eval module with SSL.

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

$t->has(qw/http http_ssl sni proxy rewrite eval/)
    ->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server 127.0.0.1:8444;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        eval  dynamic.conf;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_certificate      localhost.crt;
        ssl_certificate_key  localhost.key;

        add_header  X-SNI ,$ssl_server_name;
    }
}

EOF

$t->write_file('dynamic.conf', my $dynconf = 'proxy_pass https://backend;');

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');

$t->run()->plan(2);

###############################################################################

like(http_get('/'), qr/X-SNI: ,/, 'location from file');

$t->write_file('tmp.conf', $dynconf . 'proxy_ssl_server_name on;');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file update to be noticed

like(http_get('/'), qr/X-SNI: ,backend/, 'location from updated file');

###############################################################################
