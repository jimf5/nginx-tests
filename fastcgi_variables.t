#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Test for fastcgi variables.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi rewrite/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Script-Name $fastcgi_script_name;
        add_header X-Path-Info $fastcgi_path_info;

        location / {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_index index.php;
        }

        location /info {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_split_path_info ^(.+\.php)(.*)$;
        }

        location /try {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_split_path_info ^(.+\.php)(.*)$;
            try_files $fastcgi_script_name =404;
        }

        location /try/ {
            alias %%TESTDIR%%/;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_split_path_info ^(.+\.php)(.*)$;
            try_files $fastcgi_script_name =404;
        }
    }
}

EOF

$t->write_file('try.php', '');
$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/X-Script-Name: \/index\.php/ms, 'script name');
like(http_get('/info.php/path/info'), qr/X-Script-Name: \/info\.php/ms,
	'info script name');
like(http_get('/info.php/path/info'), qr/X-Path-Info: \/path\/info/ms,
	'info path');

TODO:
{
local $TODO = 'not yet' unless $t->has_version('1.29.8');

like(http_get('/try.php/path/info'), qr/X-Path-Info: \/path\/info/ms,
	'info path - try_files');
like(http_get('/try/try.php/path/info'), qr/X-Path-Info: \/path\/info/ms,
	'info path - try_files with alias');
}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	while( $request->Accept() >= 0 ) {
		print CRLF . CRLF;
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
