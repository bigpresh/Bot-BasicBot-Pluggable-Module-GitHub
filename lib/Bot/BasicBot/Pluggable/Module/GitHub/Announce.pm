# A quick Bot::BasicBot::Pluggable module to announce new/changed issues
# and soon, pushes. 
#
# David Precious <davidp@preshweb.co.uk>
 
package Bot::BasicBot::Pluggable::Module::GitHub::Announce;
use strict;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
use LWP::Simple (); 
use JSON;

our $VERSION = 0.01;
 
sub help {
    return <<HELPMSG;
Announce new/changed issues and pull requests, and, soon, pushes. 
HELPMSG
}


sub tick {
    my $self = shift;
    my $seconds_between_checks = $self->get('announce_poll') || 20;
    return if time - $self->get('announce_poll') < $seconds_between_checks;

    warn "OK, going ahead";
    use Data::Dump;
    warn "channels_and_projects : ", 
        Data::Dump::dump( $self->channels_and_projects );

    # Grab details of the issues we know about already:
    my $seen_issues = $self->get('seen_issues') || {};
    warn "Issues loaded:", Data::Dump::dump($seen_issues);

    # OK, for each channel, pull details of all issues from the API, and look
    # for changes
    my $channels_and_projects = $self->channels_and_projects;
    for my $channel (keys %$channels_and_projects) {
        my $project = $channels_and_projects->{$channel};
        my %notifications;
        warn "Looking for issues for $project for $channel";

        my $issues_json = LWP::Simple::get(
            "https://github.com/api/v2/json/issues/list/$project/open"
        ) or warn "Failed to fetch issues for $project" and return;
        my $issues = JSON::from_json($issues_json)
            or warn "Failed to parse issues for $project" and return;

        # Go through all currently-open issues and look for new/reopened ones
        for my $issue (@{ $issues->{issues} }) {
            my $issuenum = $issue->{number};
            if (my $existing = $seen_issues->{$project}{$issuenum}) {
                if ($existing->{state} eq 'closed') {
                    # It was closed before, but is now in the open feed, so it's
                    # been re-opened
                    push @{ $notifications{reopened} }, 
                        [ $issuenum, $issue->{title} ];
                    $existing->{state} = 'open';
                }
            } else {
                # A new issue we haven't seen before
                push @{ $notifications{opened} },
                    [ $issuenum, $issue->{title} ];
                $seen_issues->{$project}{$issuenum} = {
                    state => 'open',
                    title => $issue->{title},
                };
            }
        }

        # Now, go through ones we already know about - if we knew about them,
        # and they were open, but weren't in the list of open issues we fetched
        # above, they must now be closed
        for my $issuenum (keys %{ $seen_issues->{$project} }) {
            my $existing = $seen_issues->{$project}{$issuenum};
            my $current = grep { 
                $_->{number} == $issuenum 
            } @{ $issues->{issues} };

            if ($existing->{state} eq 'open' && !$current) {
                # It was open before, but isn't in the list now - it must have
                # been closed.
                push @{ $notifications{closed} },
                    [ $issuenum, $existing->{title} ];
                $existing->{state} = 'closed';
            }
        }

        # Announce any changes
        for my $type (keys %notifications) {
            my $s = scalar $notifications{$type} > 1 ? 's':'';

            warn "Would tell $channel about $type issues " 
                . join ',', map { $_->[0] } @{ $notifications{$type} };

            next; # don't spam IRC while finding initial sates

            $self->say(
                channel => $channel,
                body => "Issue$s $type : "
                    . join ', ', map { 
                        sprintf "%d (%s)", @$_
                    } @{ $notifications{$type} }
            );
        }
    }

    #warn "Storing updated issue details: ",
    #    Data::Dump::dump($seen_issues);

    # Store the updated issue details:
    # $self->set('seen_issues', $seen_issues);
    use Storable;
    my $data = Storable::nstore($seen_issues);
    warn "Data to store:", $data;
    $self->set('seen_issues', $data);

}

