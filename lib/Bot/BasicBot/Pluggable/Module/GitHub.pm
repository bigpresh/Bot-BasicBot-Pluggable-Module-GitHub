package Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module';

# This module is intended to be used as a base by the B::B::P::M::GitHub::*
# modules, and provides some shared functionality (reading the default project
# for a channel from the bot's store, etc).
#
# It should not be loaded directly by the bot; load the desired modules you
# want.

use strict;
use Net::GitHub::V2;

our $VERSION = '0.04';

# We'll cache suitably-configured Net::GitHub objects for each channel.
my %net_github;

# Given a channel name or a user/project, return a suitably-configured 
# Net::GitHub::V2 object.
# If a channel name is given, we'll look up the default project stored for that
# channel; if a user/project is given, we'll just use that.
# We'll then see if we have authentication details stored to use, and use them
# if appropriate.
sub ng {
    my ($self, $channelorproject) = @_;


    # Work out the repo we're using - we may have been given "user/repo", or, if
    # we were given a channel name, look up the default repo for that channel
    my ($user, $project);
    if ($channelorproject =~ m{/}) {
        ($user, $project) = split '/', $channelorproject, 2;
    } else {
        my $chanprojects = $self->project_for_channel($channelorproject) || [];
        ($user, $project) = split '/', @$chanprojects[0], 2;
    }
    
    return unless $user && $project;

    if (my $ng = $net_github{"$user/$project"}) {
        return $ng;
    }

    my %ngparams = (
        owner => $user,
        repo  => $project,
    );
    # If authentication is needed, add that in too:
    if (my $auth = $self->auth_for_project("$user/$project")) {
        my ($auth_user, $token) = split /:/, $auth, 2;
        $ngparams{login} = $auth_user;
        $ngparams{pass} = $token;
        $ngparams{always_Authorization} = 1;
    }

    return $net_github{"$user/$project"} = Net::GitHub::V2->new(%ngparams);
}


# Find all of the GitHub projects for a given channel
sub projects_for_channel {
    my ($self, $channel) = @_;

    my $projects_for_channel =
        $self->store->get('GitHub', 'projects_for_channel');
    return $projects_for_channel->{$channel};
}
# Alias for backwards compatibility
sub github_project {
    my $self = shift;
    my $projects = $self->projects_for_channel(@_);
    return @$projects[0] if $projects;
    return undef;
}

# Accept a search term and return the first project that matches
sub search_projects {
    my ($self, $channel, $search) = @_;
    my $projects = $self->projects_for_channel($channel);
    return unless $projects;

    for (@$projects) {
        return $_ if $_ =~ /$search/i;
    }
}

# Find auth details to use to access a channel's project
sub auth_for_project {
    my ($self, $project) = @_;

    my $auth_for_project = 
        $self->store->get('GitHub', 'auth_for_project');

    if ($auth_for_project->{$project}) {
        return $auth_for_project->{$project};
    } else {
        # Return the default auth, if set
        return $self->store->get('GitHub', 'default_auth');
    }
}

# For each channel the bot is in, call projects_for_channel() to find out what 
# projects are appropriate for that channel, and return a hashref of 
# channel => projects (leaving out channels for which no project is defined)
sub channels_and_projects {
    my $self = shift;
    my %projects_for_channel; 
    for my $channel ($self->bot->channels) {
        if (my $projects = $self->projects_for_channel($channel)) {
            $projects_for_channel{$channel} = $projects;
        }
    }
    return \%projects_for_channel;
}

# Support configuring project details for a channel (potentially with auth
# details) via a msg.  This is a bit too tricky to just leave the Vars module to
# handle, I think.  (Note that each of the modules which inherit from us will
# get this method; one of them will catch it and handle it.)
sub said {
    my ($self, $mess, $pri) = @_;
    return unless $pri == 2;
    return unless $mess->{address} eq 'msg';
    
    if ($mess->{body} =~ m{
        ^!setgithubprojects \s+
        (?<channel> \#\S+ ) \s+
        (\S+\/\S+)+
    }xi) {
        my $channel = $+{channel};
        my $message = "OK, set projects for $channel: ";
        my $projects_for_channel = 
            $self->store->get('GitHub','projects_for_channel') || {};
        $projects_for_channel->{$channel} = []; #set to empty

        while($mess->{body} =~ m{
                \b(?<project> \S+\/\S+ )
            }gxi)
        {
            my $project = $+{project};
            push(@{$projects_for_channel->{$channel}}, $project);
            # Invalidate any cached Net::GitHub object we might have,
            # so the new settings are used
            delete $net_github{$project};
            $message .= " $project";
        }

        $self->store->set(
            'GitHub', 'projects_for_channel', $projects_for_channel
        );

        return $message;
    } elsif ($mess->{body} =~ /^!setgithubproject/i) {
        return "Invalid usage.   Try '!help github'";
    } elsif ($mess->{body} =~ m{
        ^!setdefaultauth \s+
        (?<auth>  \S+ )
    }xi) {
        $self->store->set('GitHub', 'default_auth', $+{auth});
        return "Set default auth credentials for all projects";
    } elsif ($mess->{body} =~ /^!setdefaultauth/i) {
        return "Invalid usage.   Try '!help github'";
    } elsif ($mess->{body} =~ m{
        ^!setauthforproject \s+
        (?<project> \S+\/\S+) \s+
        (?<auth>  \S+ )
    }xi) {
        my ($project, $auth) = ($+{project}, $+{auth});
        my $auth_for_project =
            $self->store->get('GitHub', 'auth_for_project') || {};
        $auth_for_project->{$project} = $auth;
        $self->store->set(
            'GitHub', 'auth_for_project', $auth_for_project
        );
        return "Set auth credentials for $project";
    } elsif ($mess->{body} =~ /^!setauthforproject/i) {
        return "Invalid usage.   Try '!help github'";
    } elsif ($mess->{body} =~ m{
        ^!addgithubproject \s+
        (?<channel> \#\S+ ) \s+
        (?<project> \S+\/\S+)+
    }xi){
        my ($channel, $project) = ($+{channel}, $+{project});
        my $projects_for_channel = 
            $self->store->get('GitHub','projects_for_channel') || {};
        my $projects = $projects_for_channel->{$channel} || [];

        # Check if project already exists
        for (@$projects){
            return "Project $_ already exists for channel $channel!"
                if $_ eq $project;
        }

        push(@$projects, $project);
        # Invalidate any cached Net::GitHub object we might have,
        # so the new settings are used
        delete $net_github{$project};
        $projects_for_channel->{$channel} = $projects;
        $self->store->set(
            'GitHub', 'projects_for_channel', $projects_for_channel
        );

        return "OK, set project for $channel: $project";
    } elsif ($mess->{body} =~ m{
        ^!deletegithubproject \s+
        (?<channel> \#\S+ ) \s+
        (?<project> \S+\/\S+)+
    }xi) {
        my ($channel, $project) = ($+{channel}, $+{project});
        my $projects_for_channel = 
            $self->store->get('GitHub','projects_for_channel') || {};
        my $projects = $projects_for_channel->{$channel} || [];

        # Check if project already exists
        for (1..@$projects){
            if ($projects->[$_] eq $project){
                delete $projects->[$_];
                delete $net_github{$project};
            }
        }
        $projects_for_channel->{$channel} = $projects;
        $self->store->set(
            'GitHub', 'projects_for_channel', $projects_for_channel
        );

        return "OK, deleted project for $channel: $project";
    } elsif ($mess->{body} =~ /^!showgithubprojects/i){
        my $message;
        my $projects_for_channel = 
            $self->store->get('GitHub','projects_for_channel') || {};
        foreach my $key (keys %$projects_for_channel){
            $message .= "$key: @{$projects_for_channel->{$key}}\n";
        }
        return $message || "No GitHub projects set!";
    }
    return;
}


=head1 NAME

Bot::BasicBot::Pluggable::Module::GitHub - GitHub-related modules for IRC bots running Bot::BasicBot::Pluggable

=head1 DESCRIPTION

A set of modules for L<Bot::BasicBot::Pluggable> bots, providing useful
GitHub-related functionality.

If your team use GitHub and colloborate on IRC, these may well be of interest to
you.  They're already in use on the L<Dancer> project's IRC channel, and
internally at my workplace, UK2.

Most communication with GitHub uses L<Net::GitHub::V2>, and can use
authentication with an API key for private repositories.


=head1 MODULES

The following modules are included - see the documentation for each for more 
details on how to use them.

=over 4

=item L<Bot::BasicBot::Pluggable::Module::GitHub::EasyLinks>

Provide quick URLs to view issues/pull requests etc when someone mentions one -
for example:

  <user> Go have a look at Issue 42
  <bot1> Issue 42 (It doesn't work) https://github.com/....
  <user> I fixed that in 5fcbb01
  <bot1> Commit 5fcbb01 (Retarded logic fail.) - https://github.com/....
 
You can set a default project per-channel, so the above examples will look at
whatever project is set as default for the channel the message was in.
 
You can also explicitly tell it to look at any other GitHub project:
 
  <user> 5fcbb01 @ bigpresh/Bot-BasicBot-Pluggable-Module-GitHub
  <bot1> Commit 5fcbb01 (Retarded logic fail.) - https://github.com/...


=item L<Bot::BasicBot::Pluggable::Module::GitHub::PullRequests>

Monitor pull requests for GitHub projects.

Example:

  <@bigpresh> !pr
  < sophie> Open pull requests for sukria/Dancer : 8 pull requests open
            (felixdo:3, perlpilot:1, jamhed:1, dams:1, ambs:1, JTimothyKing:1)

=item L<Bot::BasicBot::Pluggable::Module::GitHub::Announce>

Announces issues raised/closed for each channel's default project.

Periodically checks on issues for each project, and reports changes, for
example:

  < sophie> Issues closed : 667 (YAML::XS for Session::YAML) by jamhed :
            https://github.com/sukria/Dancer/issues/667


=back

=head1 Loading modules

See the L<Bot::BasicBot::Pluggable> documentation for how to load these modules
into your bot.

Do not load this module directly; load the modules named above individually, to
get just the functionality you require.

This module is intended only to provide a base for the other modules, including
shared functionality and common documentation.


=head1 Configuring the default project repo

The modules above need to know what GitHub project repositories they should
refer to.

The projects are configured with the C<!setgithubprojects> command in a private
message to the bot.

You'll need to be authenticated to the bot in order to set the project
(see L<the auth module|Bot::BasicBot::Pluggable::Module::Auth>).

You set the project with:

  !setgithubprojects #channel user/projectname1 user/projectname2 ...

The default project repo for each channel is always the first one you set.
The user/projectname is mapped to C<projectname> owned by C<user> on GitHub
(in other words, <https://github.com/user/projectname>).

Projects can also be added and removed one by one using C<!addgithubproject> and C<!deletegithubproject> as follows:

    !addgithubproject #channel user/projectname3

    !deletegithubproject #channel user/projectname3

If the project is a private repository which requires authentication, you can
also tell the bot what user and token it should use to authenticate:

  !setauthforproject #channel user/privateproject someuser:githubtokenhere

You can generate/find an API token for your GitHub account at
L<https://github.com/account/admin>

If you have many projects that you want to use the same auth credentials, you can use the C<!setdefaultauth> command to set a default auth to use for all projects that don't have a specific auth set.

    !setdefaultauth user:githubtokenhere

=head1 AUTHOR

David Precious C<<davidp@preshweb.co.uk>>

=head1 ACKNOWLEDGEMENTS

James Ronan C<<james@ronanweb.co.uk>>

=head1 CONTRIBUTING

Contributions are very welcome.


=head1 LICENSE AND COPYRIGHT

Copyright 2011 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut


1; # End of Bot::BasicBot::Pluggable::Module::GitHub
