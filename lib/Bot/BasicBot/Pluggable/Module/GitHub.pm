package Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module';

# This module is intended to be used as a base by the B::B::P::M::GitHub::*
# modules, and provides some shared functionality (reading the default project
# for a channel from the bot's store, etc).
#
# It should not be loaded directly by the bot; load the desired modules you
# want.

use warnings;
use strict;

our $VERSION = '0.01';


sub github_project {
    my ($self, $channel) = @_;

    my $projects = $self->get('user_github_project')
        or return;

    # The user may have provided channel-specific projects definitions in the
    # format:
    #  '#channel1:user/repo;#channel2:user/repo'
    return $projects if ($projects !~ /:/);

    # Or, they may have simply provided a project name which should apply to
    # all channels the bot is in.
    my %repo_for_channel = map {
        split /[:]/
    } split /[;,]/, $projects;
    return $repo_for_channel{$channel};
}


# For each channel the bot is in, call github_project() to find out what project
# is appropriate for that channel, and return a hashref of channel => projet.
sub channels_and_projects {
    my $self = shift;
    my %project_for_channel; 
    for my $channel ($self->channels) {
        if (my $project = $self->github_project($channel)) {
            $project_for_channel{$channel} = $project;
        }
    }
    return \%project_for_channel;
}
        


=head1 NAME

Bot::BasicBot::Pluggable::Module::GitHub - GitHub-related modules for IRC bots running Bot::BasicBot::Pluggable

=head1 MODULES

The following modules are included - see the documentation for each for details
on how to use them.

=over 4

=item L<Bot::BasicBot::Pluggable::Module::GitHub::PullRequests>

Monitor pull requests for GitHub projects.

=item L<Bot::BasicBot::Pluggable::Module::GitHub::EasyLinks>

Provide quick URLs to view issues/pull requests etc.

=back

=head1 Loading modules

See the L<Bot::BasicBot::Pluggable> documentation for how to load these modules
into your bot.

Do not load this module directly; load the modules named above individually.
This module is intended only to provide a base for the other modules, including
shared functionality and common documentation.


=head1 Configuring the default project repo

The modules above need to know what GitHub project repository they should refer
to.

You can configure a project which applies to all channels the bot is in, or
configure a different project for each channel if the bot is in multiple
channels.

The easiest way to change the setting is using the
L<Bot::BasicBot::Pluggable::Module::Vars> module - with that module loaded,
authenticate with the bot (see L<Bot::BasicBot::Pluggable::Module::Auth>) then
send the bot a command like:

    set github_project githubusername/githubprojectname

For example, for this project:

    set gitpub_project bigpresh/Bot-BasicBot-Pluggable-Module-GitHub

Alternatively, you can change the C<user_github_project> setting directly in the
bot's store; see the L<Bot::BasicBot::Pluggable::Store> documentation.


=head1 AUTHOR

David Precious C<<davidp@preshweb.co.uk>>


=head1 LICENSE AND COPYRIGHT

Copyright 2011 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut


1; # End of Bot::BasicBot::Pluggable::Module::GitHub
