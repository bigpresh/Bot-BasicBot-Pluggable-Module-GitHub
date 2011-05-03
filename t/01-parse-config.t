#!perl -T

# Test the config setting parsing.
# Bless the object into a different package which overrides fetching from the
# store.
package MockBot;
sub get {
    return shift->{_fake_config_setting};
};


package main;

use Test::More tests => 4;
use Bot::BasicBot::Pluggable::Module::GitHub;

my $plugin = Bot::BasicBot::Pluggable::Module::GitHub->new;
bless $plugin => 'MockBot';

# First, if we provide an overall project for all channels, we should get it
# back for a random channel:
$plugin->{_fake_config_setting} = 'user/repo';
is($plugin_>github_project('#fake'), 'user/repo', 
    "Configuring repo for all channels works");

# Now, if we configure different projects for different channels, make sure they
# work:
$plugin->{_fake_config_setting} = '#chan1:user1/repo1;#chan2:user2/repo2');
is($plugin->_github_project('#chan1', 'user1/repo1',
    "Per-channel repo works");
is($plugin->_github_project('#chan2', 'user2/repo2',
    "Per-channel repo works");
is ($plugin->_github_project('#fake', undef,
    "Per-channel repo returns nothing for non-matching channel");


