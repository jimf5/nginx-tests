#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for proxy_set_header directive with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite dynamic_conf/)
    ->write_file_expand('nginx.conf',  <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
           proxy_pass http://127.0.0.1:8081;
           proxy_set_header X-One one;
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        location / {
           if ($http_x_one) {
               return 200 $http_x_one;
           }
           if ($http_x_two) {
               return 200 $http_x_two;
           }
           return 204;
        }
    }
}

EOF

$t->run()->plan(4);

###############################################################################

like(http11_get('/', socket => my $s = http('', start => 1)), qr/^one$/m,
    'conn 1 - one');

$t->write_file('nginx.conf',
    $t->read_file('nginx.conf') =~ s/One one/Two two/gr);
is(update($t), 1, 'config reloaded');

like(http_get('/'), qr/^two$/m, 'conn 2 - two');

like(http11_get('/', socket => $s), qr/^one$/m, 'conn 1 - one still');

###############################################################################

sub http11_get {
	my ($url, %extra) = @_;

	my $s = http(<<EOF, start => 1, %extra);
GET $url HTTP/1.1
Host: localhost
Connection: keep-alive

EOF

	my $response = '';
	while (my $line = <$s>) {
		$response .= $line;
		last if $line =~ /^\r?\n$/;
	}
	if ($response =~ /Content-Length:\s*(\d+)/i) {
		read($s, $_, $1);
		$response .= $_;
	}
	close $s unless $extra{socket};
	log_in($response);
	return $response;
}

sub update {
	my ($t) = @_;

	$t->update();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /(dynamic conf load)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
