#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http header validation with http_v2 module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new();

plan (skip_all => 'not yet') unless $t->has_version('1.29.6');

$t->has(qw/http http_v2/)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        http2 on;
     }
}

EOF

$t->write_file('index.html', '');

$t->run()->plan(19);

###############################################################################

for my $c (split '', '"(),/:;<=>?@[\]{}AZ') {
	is(get2("x-foo$c")->{':status'}, 400, "'$c' not allowed");
}

###############################################################################

sub get2 {
	my ($h) = @_;
	my $s = Test::Nginx::HTTP2->new();
	my $sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => $h, value => 'bar', mode => 2 }]});
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers};
}

###############################################################################
