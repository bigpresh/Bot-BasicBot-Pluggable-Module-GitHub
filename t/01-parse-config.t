#!perl -T

# Test the config setting parsing.
package main;
use strict;
use Bot::BasicBot::Pluggable::Module::GitHub;

# Subclass to override fetching of config setting from store
package MockBot;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
sub get {
    return shift->{_fake_config_setting};
}


# On with the show...
package main;
use Test::More tests => 4;

my $plugin = MockBot->new;

# First, if we provide an overall project for all channels, we should get it
# back for a random channel:
$plugin->{_fake_config_setting} = 'user/repo';
is($plugin->github_project('#fake'), 'user/repo', 
    "Configuring repo for all channels works");

# Now, if we configure different projects for different channels, make sure they
# work:
$plugin->{_fake_config_setting} = '#chan1:user1/repo1;#chan2:user2/repo2';
is($plugin->github_project('#chan1'), 'user1/repo1',
    "Per-channel repo works");
is($plugin->github_project('#chan2'), 'user2/repo2',
    "Per-channel repo works");
is ($plugin->github_project('#fake'), undef,
    "Per-channel repo returns nothing for non-matching channel");


