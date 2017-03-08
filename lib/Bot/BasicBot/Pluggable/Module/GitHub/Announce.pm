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
use YAML qw(LoadFile DumpFile);
use Try::Tiny;
use Bot::BasicBot::Pluggable::MiscUtils qw(util_dehi util_strip_codes);

our $VERSION = 0.02;
 
sub help {
    return <<HELPMSG;
Announce new/changed issues and pull requests
HELPMSG
}

my %issues_cache;
my %issues_lu;
my $old_issues_cache;

sub _map_issue {
    map { +{
	state      => $_->{state},
	id         => $_->{id},
	title      => $_->{title},
	url        => $_->{html_url},
	type       => ($_->{pull_request} ? 'pull' : 'issue'),
	by	       => $_->{user}{login},
	number     => $_->{number},
	updated_at => $_->{updated_at},
    } } @_
}

sub _all_issues {
    my ($ng, $args) = @_;
    my @issues = $ng->issue->repos_issues($args);
    my $page = 1;
    while ($ng->issue->has_next_page) {
	push @issues, $ng->issue->next_page;
	$page++;
    }
    warn ".. @{[scalar @issues]} issues, $page pages"
	if $page > 1;
    @issues
}

sub _merge_issues {
    my ($new, $old) = @_;
    my %idmap = (map { ($_->{id} => 1) } @$new);
    ( @$new,
      (grep { !$idmap{ $_->{id} } } @{ $old || [] })
     )
}

sub _update_issues {
    my ($prjcache, $prjlu, $new) = @_;
    $prjcache->{_issues} = [_merge_issues($new, $prjcache->{_issues})];
    %{ $prjlu } = ( map { ($_->{number} => $_) } @{ $prjcache->{_issues} } );
}

sub tick {
    my $self = shift;

    my $seconds_between_checks = $self->get('poll_issues_interval') || 60 * 5;
    return if time - $self->get('last_issues_poll') < $seconds_between_checks;
    $self->set('last_issues_poll', time);

    my $announce_for_channel = 
	$self->store->get('GitHub','announce_for_channel') || {};
    my $conf = $self->store->get('GitHub', 'announce_config_flags') || +{};
    my %projects;
    for my $channel (keys %$announce_for_channel) {
	for my $project (@{ $announce_for_channel->{$channel} || [] }) {
	    $projects{$project} = 1;
	}
    }

    unless ($old_issues_cache) {
	if (-f "gh_announce_issues_cache.yml") {
	    ($old_issues_cache) = LoadFile("gh_announce_issues_cache.yml");
	}
	else {
	    $old_issues_cache = {};
	}
    }

    for my $project (sort keys %projects) {
	unless ($issues_cache{$project}) {
	    warn "Loading issues of $project initially..";
	    my $ng = $self->ng($project) or next;
	    $issues_cache{$project} = delete $old_issues_cache->{$project};
	    $issues_cache{$project}{__time__} = time;
	    delete $issues_cache{$project}{_lu};
	    my $prjcache = $issues_cache{$project};
	    my $prjlu = $issues_lu{$project} ||= +{};
	    my $since = @{$prjcache->{_issues} || []} ?
		$prjcache->{_issues}[0]{updated_at} : '';
	    warn ".. " . (scalar @{$prjcache->{_issues} || []}) . " cached.." . ($since ? " since $since .." : '');
	    my @issues = _map_issue(_all_issues($ng, +{ state => 'all', sort => 'updated', ($since ? (since => "$since") : ()) }));
	    _update_issues($prjcache, $prjlu, \@issues);
	    my $heads = $ng->git_data->ref('heads');
	    for my $head (@{$heads||[]}) {
		my $ref = $head->{ref};
		$ref =~ s{^refs/heads/}{};
		$prjcache->{'__heads__'}{$ref} = $head->{object}{sha};
	    }
	    delete $projects{$project};
	}
    }
    DumpFile("gh_announce_issues_cache.yml", \%issues_cache);
    my %messages;
    for my $project (sort keys %projects) {
	next unless $issues_cache{$project};
	my $ng = $self->ng($project) or next;
	my $prjcache = $issues_cache{$project};
	my $prjlu = $issues_lu{$project} ||= +{};
	my $since = @{$prjcache->{_issues}} ?
	    $prjcache->{_issues}[0]{updated_at} : '';
	my @issues = _map_issue(_all_issues($ng, +{ state => 'all', sort => 'updated', ($since ? (since => "$since") : ()) }));
	my %notifications;
	for my $issue (@issues) {
	    my $type;
	    my $details = +{ state => $issue->{state}, by => $issue->{by} };
	    if (my $existing = $prjlu->{ $issue->{number} }) {
		if ($existing->{state} eq $issue->{state}) {
		    # no change
		}
		elsif ($issue->{state} eq 'closed') {
		    # It was open before, but isn't in the list now - it must have
		    # been closed.
		    my $by;
		    my $state = $issue->{state};
		    if ($issue->{type} eq 'pull' ) {
			my $pr = $ng->pull_request->pull($issue->{number});
			if ($pr->{merged}) {
			    $state = 'merged';
			    $by = $pr->{merged_by}{login};
			}
		    }
		    unless (defined $by) {
			my $issue = $ng->issue->issue($issue->{number});
			$by = $issue->{closed_by}{login};
		    }
		    $details = +{ state => $state, by => $by };
		    $type = $state;
		}
		elsif ($issue->{state} eq 'open') {
		    # It was closed before, but is now in the open feed, so it's
		    # been re-opened
		    $type = 'reopened';
		}
	    }
	    elsif ($issue->{state} eq 'open') {
		# A new issue we haven't seen before
		$type = 'opened';
	    }

	    if ($type) {
		$prjcache->{_details}{ $issue->{number} } = $details;
		push @{ $notifications{$type} },
		    [ $issue->{number}, $issue, $details ];
	    }
	}
	_update_issues($prjcache, $prjlu, \@issues);
	my @push_not;
	my $heads = $ng->git_data->ref('heads');
	for my $head (@{$heads||[]}) {
	    my $ref = $head->{ref};
	    $ref =~ s{^refs/heads/}{};
	    my $sha = $head->{object}{sha};
	    my $ex = $prjcache->{'__heads__'}{$ref};
	    if ($ex ne $sha) {
		my $commit = $ng->git_data->commit($sha);
		my $ignore;
		my $re = $conf->{$project}{ignore_branches_re};
		if ($re) {
		    $ignore ||= $ref =~ /$re/;
		}
		unless ($ignore) {
		    if ($commit && !exists $commit->{error}) {
			my $title = ( split /\n+/, $commit->{message} )[0];
			my $url = $commit->{html_url};
			push @push_not, [
			    $ref,
			    ($commit->{author}{login}||$commit->{committer}{login}||$commit->{author}{name}||$commit->{committer}{name}),
			    $title,
			    $project,
			    $url
			   ];
		    }
		    else {
			push @push_not, [$ref,$sha];
		    }
		}
		$prjcache->{'__heads__'}{$ref} = $sha;
	    }
	}
	$messages{$project} = +{ notifications => \%notifications,
				 push_not => \@push_not };
	if (%notifications || @push_not) {
	    warn "Loading issues of $project " . ($since ? "since $since" : '');
	}
    }
    DumpFile("gh_announce_issues_cache.yml", \%issues_cache);
    #    try {
    # OK, for each channel, pull details of all issues from the API, and look
    # for changes
 channel:
    for my $channel (keys %$announce_for_channel) {
        my $dfltproject = $self->github_project($channel) || '';
	my $dfltuser = $dfltproject && $dfltproject =~ m{^([^/]+)} ? $1 : '';
    project:
	for my $project (@{ $announce_for_channel->{$channel} || [] }) {
	    my @bots = grep /^Not-/, $self->bot->pocoirc->channel_list($channel);
	    @bots = grep { $_ ne $self->bot->nick } @bots;
	    my %notifications = %{$messages{$project}{notifications} || +{}};
	    my @push_not = @{$messages{$project}{push_not} || []};
	    if (%notifications || @push_not) {
		warn "Looking for issues for $project for $channel"; warn "`bots: @bots" if @bots;
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
		    my @message = (
			channel => $channel,
			body => "$nt{$t}$s\cC $tc{$type}$type\cC$in: "
			    . join ', ', map { 
				sprintf "\cC43%d\cC (\cC59%s\cC) by \cB%s\cB: \cC73%s\cC", 
				    $_->[0], # issue number
				    $_->[1]{title},
				    util_dehi($_->[2]{by}),
				    makeashorterlink($_->[1]{url})
				} @not
			       );
		    warn "msg: $message[1]: ".util_strip_codes($message[3]) if @not;
		    $self->say(@message) if @not && !@bots;
		}
	    }

	    if (@push_not) {
		my $in = $project eq $dfltproject ? '' : $project =~ m{^\Q$dfltuser\E/(.*)$} ? " in $1" : " in $project";
		my @message = (
		    channel => $channel,
		    body => "New commits$in " . join ', ', map {
			@$_>2 ? (
			    sprintf "on branch %s by \cB%s\cB - \cC59%s\cC: \cC73%s\cC",
			    $_->[0], util_dehi($_->[1]), $_->[2], makeashorterlink('https://github.com/'.$_->[3].'/tree/'.$_->[0]))
			    : sprintf 'branch %s now at %s', @{$_}[0,1]
			} @push_not
		   );
		warn "msg: $message[1]: ".util_strip_codes($message[3]);
		$self->say(@message) unless @bots || $notifications{merged} || $conf->{$project}{no_heads};
	    }
	}
    }
    #}
    #	catch {
    #	    warn "Exception: " .  s/(\sat\s\/.*\sline\s\d+).*/$1/grs;
    #	}

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
			      (?<project> \S+   ) (?:\s+
			      (?<flags> .* ))?
		      }xi) {
        my $announce_for_channel = 
            $self->store->get('GitHub','announce_for_channel') || {};
	my $conf = $self->store->get('GitHub', 'announce_config_flags') || +{};	
        my @projects = @{ $announce_for_channel->{$+{channel}} || [] };
	if (lc $+{action} eq 'del') {
	    @projects = grep { lc $_ ne lc $+{project} } @projects;
	}
	else {
	    unless (grep { lc $_ eq lc $+{project} } @projects) {
		push @projects, $+{project};
	    }
	}
	$announce_for_channel->{$+{channel}} = \@projects;
        $self->store->set(
            'GitHub', 'announce_for_channel', $announce_for_channel
	   );
	if ($+{action} eq 'add' && $+{flags}) {
	    my $flags = " $+{flags}";
	    my $project = "\L$+{project}";
	    while ($flags =~ /\s-(\w+)=(?:(["'])(.*?)\2|(\S+))(?=\s|$)/g) {
		my $key = lc $1;
		my $val = $3 || $4;
		if ($val) {
		    $conf->{$project}{$key} = $val;
		}
		else {
		    delete $conf->{$project}{$key};
		}
	    }
	    delete $conf->{$project}
		unless %{ $conf->{$project} };
	}
	delete $conf->{''};
        $self->store->set(
            'GitHub', 'announce_config_flags', $conf
	   );

        return "OK, $+{action}ed $+{project} for $+{channel}.";

    }
    elsif ($mess->{body} =~ /^!listgithubannounce\s*$/) {
	my $var = $self->store->get('GitHub', 'announce_for_channel') || +{};
	my $conf = $self->store->get('GitHub', 'announce_config_flags') || +{};
	my $ret = '';
	for my $ch (sort keys %$var) {
	    if (@{$var->{$ch}}) {
		$ret .= $ch . ':  ' . join ", ", map {
		    my $ret = $_;
		    my $proj = $_;
		    if ($conf->{$proj}) {
			$ret .= ' ' . join ' ',
			    map { "-$_=".$conf->{$proj}{$_} }
			    grep { $conf->{$proj}{$_} }
			    sort keys %{$conf->{$proj}};
		    }
		    $ret
		} sort @{$var->{$ch}};
		$ret .= "\n";
	    }
	}
	return $ret;
    }
    elsif ($mess->{body} =~ /^!(?:add|del|list)githubannounce/i) {
        return "Invalid usage.   Try '!help github'";
    }
    return;
}

1;
