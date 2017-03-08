# A quick Bot::BasicBot::Pluggable module to announce new/changed issues
# and soon, pushes. 
#
# David Precious <davidp@preshweb.co.uk>
 
package Bot::BasicBot::Pluggable::Module::GitHub::Announce;
use strict;
use WWW::Shorten::GitHub;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
use JSON;

our $VERSION = 0.02;
 
sub help {
    return <<HELPMSG;
Announce new/changed issues and pull requests
HELPMSG
}


sub tick {
    my $self = shift;

    my $issue_state_file = 'last-issues-state.json';
    
    my $seconds_between_checks = $self->get('poll_issues_interval') || 60 * 5;
    return if time - $self->get('last_issues_poll') < $seconds_between_checks;
    $self->set('last_issues_poll', time);

    # Grab details of the issues we know about already:
    # Have to handle storing & loading old issue state myself - I don't know
    # why, but the bot storage doesn't want to work for this.
    my $json;
    my $first_run;
    if (-f $issue_state_file) {
    open my $fh, '<', $issue_state_file
        or die "Failed to open $issue_state_file - $!";
    { local $/; $json = <$fh> }
    close $fh;
    } else {
    $first_run = 1;
    }
    my $seen_issues = $json ? JSON::from_json($json) : {};


    # OK, for each channel, pull details of all issues from the API, and look
    # for changes
    my $announce_for_channel = 
	$self->store->get('GitHub','announce_for_channel') || {};
    channel:
    for my $channel (keys %$announce_for_channel) {
        my $dfltproject = $self->github_project($channel) || '';
	my $dfltuser = $dfltproject && $dfltproject =~ m{^([^/]+)} ? $1 : '';
    project:
	for my $project (@{ $announce_for_channel->{$channel} || [] }) {
        warn "Looking for issues for $project for $channel";
        my %notifications;

        my $ng = $self->ng($project) or next project;

        my $issues = $ng->issue->repos_issues({state => 'open'});

        # Go through all currently-open issues and look for new/reopened ones
        for my $issue (@$issues) {
            my $issuenum = $issue->{number};
            my $details = {
                title      => $issue->{title},
                url        => $issue->{html_url},
		type       => ($issue->{pull_request} ? 'pull' : 'issue'),
                by => $issue->{user}{login},
            };

            if (my $existing = $seen_issues->{$project}{$issuenum}) {
                if ($existing->{state} eq 'closed') {
                    # It was closed before, but is now in the open feed, so it's
                    # been re-opened
                    push @{ $notifications{reopened} }, 
                        [ $issuenum, $details ];
                    $existing->{state} = 'open';
                }
            } else {
                # A new issue we haven't seen before
                push @{ $notifications{opened} },
                    [ $issuenum, $details ];
                $seen_issues->{$project}{$issuenum} = {
                    state => 'open',
                    details => $details,
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
            } @$issues;

            if ($existing->{state} eq 'open' && !$current) {
                # It was open before, but isn't in the list now - it must have
                # been closed.
		my $state = 'closed';
		my $by;
		if ($existing->{details}{type} eq 'pull' ) {
		    my $pr = $ng->pull_request->pull($issuenum);
		    if ($pr->{merged}) {
			$state = 'merged';
			$by = $pr->{merged_by}{login};
		    }
		}
		unless (defined $by) {
		    my $issue = $ng->issue->issue($issuenum);
		    $by = $issue->{closed_by}{login};
		}
		$existing->{details}{by} = $by;
                push @{ $notifications{$state} },
                    [ $issuenum, $existing->{details} ];
                $existing->{state} = 'closed';
            }
        }

	my $in = $project eq $dfltproject ? '' : $project =~ m{^\Q$dfltuser\E/(.*)$} ? " in $1" : " in $project";
        # Announce any changes
        for my $type (qw(opened reopened merged closed)) {
	    next unless $notifications{$type};
            my $s = scalar @{$notifications{$type}} > 1 ? 's':'';
	    my %nt = (issue => "\cC52Issue", pull => "\cC29Pull request");
	    my %tc = ('closed' => "\cC55", 'opened' => "\cC52", reopened => "\cC52", merged => "\cC46");
	    for my $t (qw(issue pull)) {
		my @not = grep { $_->[1]{type} eq $t } @{ $notifications{$type} };
		$self->say(
		    channel => $channel,
		    body => "$nt{$t}$s\cC $tc{$type}$type\cC$in: "
			. join ', ', map { 
			    sprintf "\cC43%d\cC (\cC59%s\cC) by \cB%s\cB: \cC73%s\cC", 
			    $_->[0], # issue number
			    @{$_->[1]}{qw(title by)},
			    makeashorterlink($_->[1]{url})
			} @not
		       ) if @not && !$first_run;
	    }
        }

	my $heads = $ng->git_data->ref('heads');
	my @push_not;
	for my $head (@{$heads||[]}) {
	    my $ref = $head->{ref};
	    $ref =~ s{^refs/heads/}{};
	    my $sha = $head->{object}{sha};
	    my $ex = $seen_issues->{'__heads__'.$project}{$ref};
	    if ($ex ne $sha) {
		my $commit = $ng->git_data->commit($sha);
		if ($commit && !exists $commit->{error}) {
		    my $title = ( split /\n+/, $commit->{commit}{message} )[0];
		    my $url = $commit->{html_url};
		    push @push_not, [
			$ref,
			($commit->{author}{login}||$commit->{committer}{login}||$commit->{commit}{author}{name}||$commit->{commit}{committer}{name}),
			$title,
			$project,
			$url
		       ];
		} else {
		    push @push_not, [$ref,$sha];
		}
		$seen_issues->{'__heads__'.$project}{$ref}=$sha;
	    }
	}
	if (@push_not) {
	    my $in = $project eq $dfltproject ? '' : $project =~ m{^\Q$dfltuser\E/(.*)$} ? " in $1" : " in $project";
	    $self->say(
		channel => $channel,
		body => "New commits$in " . join ', ', map {
		    @$_>2 ? (
		    sprintf "on branch %s by \cB%s\cB - \cC59%s\cC: \cC73%s\cC",
		    $_->[0], $_->[1], $_->[2], makeashorterlink('https://github.com/'.$_->[3].'/tree/'.$_->[0]))
			: sprintf 'branch %s now at %s', @{$_}[0,1]
		    } @push_not
		   ) unless $first_run || $notifications{merged};
	}
	
    }}

    my $store_json = JSON::to_json($seen_issues);
    # Store the updated issue details:
    open my $storefh, '>', $issue_state_file
        or die "Failed to write to $issue_state_file - $!";
    print {$storefh} $store_json;
    close $storefh;
    return;

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
        ^!(?<action> add | del )githubannounce \s+
        (?<channel> \#\S+ ) \s+
        (?<project> \S+   )
    }xi) {
        my $announce_for_channel = 
            $self->store->get('GitHub','announce_for_channel') || {};
        my @projects = @{ $announce_for_channel->{$+{channel}} || [] };
	if (lc $+{action} eq 'del') {
	    @projects = grep { lc $_ ne lc $+{project} } @projects;
	} else {
	    unless (grep { lc $_ eq lc $+{project} } @projects) {
		push @projects, $+{project};
	    }
	}
	$announce_for_channel->{$+{channel}} = \@projects;
        $self->store->set(
            'GitHub', 'announce_for_channel', $announce_for_channel
        );

        return "OK, $+{action}ed $+{project} for $+{channel}.";

    } elsif ($mess->{body} =~ /^!(?:add|del)githubannounce/i) {
        return "Invalid usage.   Try '!help github'";
    }
    return;
}
