#!/usr/bin/perl

# (C) Eugene Grebenshchikov

# Tests for http eval module.

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

$t->has(qw/http map proxy rewrite eval/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $host $loc {
        default    dynamic.conf;
        fromdata   'data: proxy_pass http://127.0.0.1:8081;';
    }

    map $uri $error_conf {
        /error/  error.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        eval $loc;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        # named location cannot be inside location block yet
        location @fallback { try_files /404.html =404; }

        eval back.conf;
    }
}

EOF

$t->write_file_expand('dynamic.conf', 'proxy_pass http://127.0.0.1:8081;');
$t->write_file_expand('back.conf', <<'EOF');
set $a 'alias %%TESTDIR%%/;';
location /       { root %%TESTDIR%%; }
location /t/     { alias %%TESTDIR%%/; }
location /t2/    { eval data:$a; }
location /try/   { try_files $uri /index.html; }
location /error/ { eval $error_conf; }
if ($uri = /r/)  { eval 'data: return 204;'; }
EOF

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('404.html', 'SEE-THIS-404');

$t->run()->plan(11);

###############################################################################

like(get('localhost'), qr/SEE-THIS/, 'location from file');
like(get('localhost', '/t/'), qr/SEE-THIS/, 'location from file - alias');
like(get('localhost', '/r/'), qr/ 204 No Content/,
	'location from file - rewrite');

TODO:
{
local $TODO = 'eval from data issue - needs to be fixed';

like(get('localhost', '/t2/'), qr/SEE-THIS/,
	'location from file - eval data variable');
}

like(get('localhost', '/try/'), qr/SEE-THIS/, 'location from file - try_files');

#create a config after run nginx
$t->write_file('error.conf', 'error_page 404 =200 /404.html;');

like(get('localhost', '/error/'), qr/ 200 OK.*SEE-THIS-404/s,
	'location from file - error_page');

$t->write_file('tmp.conf', 'error_page 404 =404 @fallback;');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/error.conf';

like(get('localhost', '/error/'), qr/ 200 OK.*SEE-THIS-404/s,
	'location from cached file - error_page');

select undef, undef, undef, 0.1; # wait for file change to be noticed

like(get('localhost', '/error/'), qr/ 404 Not Found.*SEE-THIS-404/s,
	'location from updated file - error_page - named location');

$t->write_file_expand('tmp.conf', 'proxy_pass http://127.0.0.1:8081/t/;');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file change to be noticed

like(get('localhost'), qr/SEE-THIS/, 'location from updated file - uri');

$t->write_file('tmp.conf', 'return 200');
rename $t->testdir() . '/tmp.conf', $t->testdir() . '/dynamic.conf';
select undef, undef, undef, 0.1; # wait for file change to be noticed

like(get('localhost'), qr/ 500 Internal Server Error/,
	'location from updated file - invalid config');

TODO:
{
local $TODO = 'eval from data issue - needs to be fixed';

like(get('fromdata'), qr/SEE-THIS/, 'location from data');
}

###############################################################################

sub get {
	my ($host, $uri) = @_;

	$uri ||= '/';

	return http("GET $uri HTTP/1.0\nHost: $host\n\n");
}

###############################################################################
