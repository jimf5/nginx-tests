#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Test for proxy module with dynamic configuration reload.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy dynamic_conf/)->plan(4);

my $conf = << 'EOF';

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
            %%PCFG%%
        }
    }
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');

###############################################################################

my $pcfg = <<'EOF';
proxy_read_timeout 1s;
proxy_buffer_size 128;
proxy_buffers 4 128;
EOF
$t->write_file_expand('nginx.conf', $conf =~ s/%%PCFG%%/$pcfg/gr)->run();
like(http11_get('/', socket => my $s = http('', start => 1)),
	qr/^HTTP\/1.. 502 /m, 'conn 1, not ok');

$pcfg = <<'EOF';
proxy_read_timeout 2s;
proxy_buffer_size 4k;
proxy_buffers 4 4k;
EOF
$t->write_file_expand('nginx.conf', $conf =~ s/%%PCFG%%/$pcfg/gr);
is(update($t), 1, 'config reloaded');

like(http_get('/'), qr/SEE-THIS/, 'conn 2 - ok');
like(http11_get('/', socket => $s), qr/^HTTP\/1.. 502 /m,
	'conn 1, not ok still');

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
