#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for headers module with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http dynamic_conf/)
	->write_file_expand('nginx.conf',  << 'EOF');

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
           add_header X-URI $uri;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');

$t->run()->plan(4);

###############################################################################

like(http11_get('/', socket => my $s = http('', start => 1)), qr/X-URI/,
	'conn 1 - URI');

$t->write_file('nginx.conf',
	$t->read_file('nginx.conf') =~ s/X-URI/X-URL/gr)->update();
is(update($t), 1, 'config reloaded');

like(http_get('/'), qr/X-URL/, 'conn 2 - URL');

like(http11_get('/', socket => $s), qr/X-URI/, 'conn 1 - URI still');

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
