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

    my $issue_state_file = 'last-issues-state.json';
    
    warn "Checking if it's time to process issues";
    my $seconds_between_checks = $self->get('announce_poll') || 20;
    warn "OK, seconds_between_checks will be $seconds_between_checks";
    return if time - $self->get('announce_poll') < $seconds_between_checks;
    warn "Yeah, it's time.";

    warn "OK, going ahead";
    use Data::Dump;
    warn "channels_and_projects : ", 
        Data::Dump::dump( $self->channels_and_projects );

    # Grab details of the issues we know about already:
    # Have to handle storing & loading old issue state myself - I don't know
    # why, but the bot storage doesn't want to work for this.
    open my $fh, '<', $issue_state_file
        or die "Failed to open $issue_state_file - $!";
    my $json;
    { local $/; $json = <$fh> }
    close $fh;
    my $seen_issues = $json ? JSON::from_json($json) : {};

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
    my $store_json = JSON::to_json($seen_issues);
    warn "Storing updated seen_issues: $store_json";
    # Store the updated issue details:
    open my $storefh, '>', $issue_state_file
        or die "Failed to write to $issue_state_file - $!";
    print {$storefh} $store_json;
    close $storefh;
    return;

}

