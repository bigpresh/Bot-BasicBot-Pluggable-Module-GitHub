#!perl -T

# Tests for channel/auth settings handling.
#
# Mock the bot store with known settings, then check we get the right info back.


# Fake bot storage; pretend to be the Store module, to some degree.
# Instantiated with a hashref of settings, stores then in the object, and
# returns them when asked for
package MockStore;
use strict;
sub new { 
    my ($class, $settings) = @_;
    return bless { settings => $settings } => $class; 
}
sub get {
    my ($self, $namespace, $key) = @_;
    return unless $namespace eq 'GitHub';
    return $self->{settings}{$key};
}
sub set {
    my ($self, $namespace, $key, $value) = @_;
    return unless $namespace eq 'GitHub';
    $self->{settings}{$key} = $value;
}


# Subclass to override fetching of config setting from store
package MockBot;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
sub get {
    my ($self,$setting) = @_;
    return $self->{_conf}{$setting};
}
sub store {
    my $self = shift;
    return $self->{_store};
}

# On with the show...
package main;
use strict;
use Bot::BasicBot::Pluggable::Module::GitHub;


package main;
use Test::More tests => 6;

my $plugin = MockBot->new;

# Set some projects for channels, then we can test we get the right info back
$plugin->{_store} = MockStore->new({
    projects_for_channel => {
        '#foo' =>  [ 'someuser/foo' ],
        '#bar' => [ 'bobby/tables', 'tom/drinks' ] ,
    },
    auth_for_project => {
        'bobby/tables' => 'bobby:tables',
    },
});



is_deeply ($plugin->projects_for_channel('#foo'), [ 'someuser/foo' ],
    'Got expected project for a channel'
);

is_deeply ($plugin->projects_for_channel('#bar'),
    [ 'bobby/tables', 'tom/drinks' ],
    'Got expected projects for a channel'
);

is($plugin->projects_for_channel('#fake'), undef,
    'Got undef project for non-configured channel'
);

is($plugin->auth_for_project('bobby/tables'), 'bobby:tables',
    'Got expected auth info for a project'
);
is($plugin->auth_for_project('fake/project'), undef,
    'Got undef auth info for non-configured project'
);

# Test default_auth if set
$plugin->{_store}->set('GitHub', 'default_auth', 'default:auth');

is($plugin->auth_for_project('someuser/foo'), 'default:auth',
    'Got expected default auth info for a project'
);
