#!/usr/bin/perl

# (C) Eugene Grebenschikov

# Tests for thread pool with dynamic configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http aio dynamic_conf/)
    ->write_file_expand('nginx.conf',  <<'EOF');

%%TEST_GLOBALS%%

daemon off;

thread_pool aio_thread_pool threads=4;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        aio threads;
        location / { }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');

$t->run()->plan(3);

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'default pool');

$t->write_file('nginx.conf',
    $t->read_file('nginx.conf') =~ s/threads;/threads=aio_thread_pool;/gr);
is(update($t), 1, 'config reloaded');

like(http_get('/'), qr/SEE-THIS/, 'aio_thread_pool');

###############################################################################

sub update {
	my ($t) = @_;

	$t->update();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /(dynamic conf load)/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
