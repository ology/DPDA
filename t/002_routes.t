use strict;
use warnings;

use Test::More tests => 4;

use DPDA;
use Plack::Test;
use HTTP::Request::Common;
use Ref::Util qw<is_coderef>;

my $app = DPDA->to_app;
ok( is_coderef($app), 'Got app' );

my $test = Plack::Test->create($app);

my $res = $test->request( GET '/overview' );
ok( $res->is_success, '[GET /overview] successful' );

$res = $test->request( GET '/question' );
ok( $res->is_success, '[GET /question] successful' );

$res = $test->request( GET '/chart' );
ok( $res->is_success, '[GET /chart] successful' );
