# A quick Bot::BasicBot::Pluggable module to provide easy links when someone
# mentions an issue / pull request / commit.
#
# David Precious <davidp@preshweb.co.uk>

package Bot::BasicBot::Pluggable::Module::GitHub::EasyLinks;
use strict;
use WWW::Shorten::GitHub;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
use URI::Title;
use List::Util qw(min max);
use Mojo::DOM;

sub help {
    return <<HELPMSG;
Provide convenient links to GitHub issues/pull requests/commits etc.
If someone says e.g. "Issue 42", the bot will helpfully provide an URL to view
that issue directly.
HELPMSG
}

sub _dehih {
    my $r = shift;
    $r =~ s/^(.)(.*)$/$1\cB\cB$2/g;
    $r
}

sub _strip_codes {
  my $msg = shift;
  $msg =~ s/\c_|\cB|\cC(?:\d{1,2}(?:,\d{1,2})?)?//g;
  $msg
}

my %mass_blocker;
my $mass_stop_user = 30;
my $mass_stop_other = 10;
sub _check_mass {
  my ($who, $channel, $msg) = @_;

  my $hr = $mass_blocker{ $channel } ||= +{};

  my $mr = $hr->{ $msg } ||= +{};

  my $now = time;

  my $user_time = $mr->{$who} || 0;
  my $other_time = $mr->{'@'} || 0;

  $mr->{'@'} = $mr->{$who} = $now;

  my $block = $user_time > $now - $mass_stop_user || $other_time > $now - $mass_stop_other;
  warn "blocking " . substr(_strip_codes($msg),0,14) . ".." . max($now-$user_time,$now-$other_time) if $block;
  !$block

}

sub _expire_mass_blocks {
  my $now = time;
  for my $ch (keys %mass_blocker) {
    for my $msg (keys %{ $mass_blocker{$ch} }) {
      if ($mass_blocker{ $ch }{ $msg }{'@'} < $now - $mass_stop_user) {
	delete $mass_blocker{$ch}{$msg};
      }
    }
  }
}

sub said {
    my ($self, $mess, $pri) = @_;
    
    return unless $pri == 2;

    # return if $mess->{body} =~ m{://git};

    # do not react to other bots, identified by /^Not-/
    return if $mess->{who} =~ /^Not-/;

    # Loop through matching things in the message body, assembling quick links
    # ready to return.
    my @return;
    unless ($mess->{body} =~ m{://git}) {
    match:
    while ($mess->{body} =~ m{ 
        (?:  
            \b
            # "Issue 42", "PR 42" or "Pull Request 42"
            (?<thing> (?:issue|pr|pull request) ) 
            (?:\s+|-)?
	    \#?
            (?<num> \d+)
        |                
	    (?:^|\s+)
	    \#
            (?<hnum> (?!999)\d{3,})
        |                
            # Or a commit SHA
            (?<sha> [0-9a-f]{6,40})
        )    
        # Possibly with a specific project repo ("user/repo") appeneded
        (?: (?: \s* \@ \s* | \s+ in \s+ ) (?<project> \S+/?\S+) )?
	\b
        }gxi
    ) {
        # First, extract what kind of thing we're looking at, and normalise it a
        # little, then go on to handle it.
        my $thing    = $+{thing};
        my $thingnum = $+{num};

        if ($+{sha}) {
            $thing    = 'commit';
            $thingnum = $+{sha};
        } elsif ($+{hnum}) {
            $thing    = 'issue';
            $thingnum = $+{hnum};
	}

        my $project = $+{project} || $self->github_project($mess->{channel});
	if ($project !~ m{/}) {
	    if ($self->github_project($mess->{channel}) =~ m{^(.*?)/} ) {
		$project = "$1/$project";
	    } else {
		return;
	    }
	}
        return unless $project;

        # Get the Net::GitHub::V2 object we'll be using.  (If we don't get one,
        # for some reason, we can't do anything useful.)
        my $ng = $self->ng($project) or return;


        warn "OK, about to try to handle $thing $thingnum for $project";

        # Right, handle it in the approriate way
        if ($thing =~ /Issue|GH|pr|pull request/i) {
            warn "Handling issue $thingnum";
            my $issue = $ng->issue->issue($thingnum);
	    my $pr;
	    if (!exists $issue->{error} && $issue->{pull_request}) {
		$pr = $ng->pull_request->pull($thingnum);
		if (exists $pr->{error}) {
		    $pr = undef;
		}
	    }
            if (exists $issue->{error}) {
                push @return, $issue->{error};
                next match;
            }
            push @return, sprintf "%s \cC43%d\cC (\cC59%s\cC) by \cB%s\cB - \cC73%s\cC%s %s\{%s\cC\}",
		(exists $issue->{pull_request} ? "\cC29Pull request" : "\cC52Issue"),
                $thingnum,
                $issue->{title},
		_dehih($issue->{user}{login}),
                makeashorterlink($issue->{html_url}),
		($issue->{labels}&&@{$issue->{labels}}?" [".(join",",map{$_->{name}}@{$issue->{labels}})."]":""),
		($issue->{milestone} ? "MS:\cB$issue->{milestone}{title}\cB ": ($pr?$self->_pr_branch($ng, $pr):"")),
$pr&&$pr->{merged_at}?"\cC46merged on ".($pr->{merged_at}=~s/T.*//r):
$issue->{closed_at}?"\cC55closed on ".($issue->{closed_at}=~s/T.*//r):"\cC52".$issue->{state}." since ".($issue->{created_at}=~s/T.*//r);
        }

        # Similarly, pull requests:
#        if ($thing =~ /(?:pr|pull request)/i) {
#            warn "Handling pull request $thingnum";
#            # TODO: send a pull request to add support for fetching details of
#            # pull requests to Net::GitHub::V2, so we can handle PRs on private
#            # repos appropriately.
#            my $pull_url = "https://github.com/$project/pull/$thingnum";
#            my $title = URI::Title::title($pull_url);
#            push @return, "Pull request $thingnum ($title) - $pull_url";
#        }

        # If it was a commit:
        if ($thing eq 'commit') {
            warn "Handling commit $thingnum";
#            my $commit = $ng->git_data->commit($thingnum);
	    local $@;
            my $commit = eval { $ng->repos->commit($thingnum) };
	    if (!$commit && $@) {
		$commit = +{ error => $@ };
	    }
	    if ($commit->{commit}) {
		if ($commit->{html_url}) {
		    $commit->{commit}{html_url} = $commit->{html_url};
		}
		$commit->{commit}{sha} //= $commit->{sha};
		$commit = $commit->{commit};
	    }
            if ($commit && !exists $commit->{error}) {
                my $title = ( split /\n+/, $commit->{message} )[0];
                my $url = $commit->{html_url};
                
                # Currently, the URL given doesn't include the host, but that
                # might perhaps change in future, so play it safe:
#                $url = "https://github.com$url" unless $url =~ /^http/;
#		$url =~ s{https://api.github.com/repos/(.*?)/commits/}{https://github.com/$1/commit/};
                push @return, sprintf "Commit \cC43$thingnum\cC (\cC59%s\cC) by \cB%s\cB on %s - \cC73%s\cC %s",
                    $title,
		    _dehih($commit->{author}{login}||$commit->{committer}{login}||$commit->{author}{name}||$commit->{committer}{name}),
		    ($commit->{author}{date}=~s/T.*//r),
                    makeashorterlink($url),
		    $self->_commit_branch($commit, $commit->{sha}),
		    ;
            } else {
                # We purposefully don't show a message on IRC here, as we guess
                # what might be a SHA, so we could be annoying saying that we
                # didn't match a commit when someone said a word that just
                # happened to look like it could be the start of a SHA.
                warn "No commit details for $thingnum \@ $project/$thingnum" . ($commit && ref $commit ? ": $commit->{error}" : "");
            }
        }
    }
    }

    unless (@return) {
    match:
    while ($mess->{body} =~ m{ 
            \b
	    https?://github.com/(?<project> \S+/\S+)/
	    	(?:
		    (?<thing> (?: issues|pull ))/
		    (?<num> \d+)
		    (?:
			(?:
			    (?:
				/commits/ (?<sha> [0-9a-f]{6,40})
			    |
				/files
			    )
			    (?: [?] [^#\s] +)? (?<stop> [#] diff\S* )?
			)
		    |
			(?<details> /? [#] \S* )
		    )?
		|
		    commit/ (?<sha> [0-9a-f]{6,40})
		    (?: [?] [^#\s]+ )? (?<stop> [#] diff\S* )?
		|
		    (?<thing> blob)/
		    (?<num> [^?#\s] +)
		    (?: [?] [^#\s]+ )? (?<stop> [#] L\S* )
		)
	    \b
        }gxi
    ) {
        my $thing    = $+{thing};
        my $thingnum = $+{num};

        if ($+{sha}) {
            $thing    = 'commit';
            $thingnum = $+{sha};
        }

        my $project = $+{project};
        return unless $project;

        # Get the Net::GitHub::V2 object we'll be using.  (If we don't get one,
        # for some reason, we can't do anything useful.)
        my $ng = $self->ng($project) or return;
	my $stop = $+{stop};
	my $details = $+{details};
	$details =~ s/.*[#]// if $details;


        warn "OK, about to try to handle $thing $thingnum for $project";

	# link to lines inside a blob/diff
	if ($stop) {
	    return unless $stop =~ s/([LR])(\d+)(?:-\1(\d+))?$//;
	    my ($lr, $line, $line2) = ($1, $2, $3);
	    next unless $line;
	    $line2 = $line unless defined $line2;
	    my $req = ($thing eq 'commit' || $thing eq 'blob')
		? HTTP::Request->new( GET => "https://github.com/$project/$thing/$thingnum")
		: HTTP::Request->new( GET => "https://github.com/$project/$thing/$thingnum/files") ;
	    $req->accept_decodable;
	    my $res = $ng->_make_request($req);
	    my $dom = Mojo::DOM->new($res->decoded_content);
	    my @lines = map {
		map {
		    my $x = $_;
		    $x->descendant_nodes->grep(sub{ $_->type ne "text" })->map('strip');
		    $x->all_text(0)
		} $dom->find("$stop$lr$_")->map('parent')->map('find', '.blob-code-inner')->flatten->each
	    } $line..$line2;
	    if (@lines) {
		my $tag = "$lr$line";
		my $ret = $lines[0];
		if ($line2 > $line) {
		    $tag .= "-$line2";
		    $ret = join ' ', map { /^\s*(.*?)\s*$/ ? $1 : $_ } @lines;
		    if (length $ret > 400) {
			(substr $ret, 290 - 3 - 3 - length $tag) = '...';
		    }
		}
		push @return, "$tag: $ret";
	    }
	    next;
	}

	# link to a issue comment
	elsif ($details) {
	    next unless $details =~ /issue(comment)?-(\d+)$/;
	    my ($comment, $id) = ($1, $2);
            warn "Handling issue $thingnum $details";
            my $issue = $ng->issue->issue($thingnum);
            if (exists $issue->{error}) {
                push @return, $issue->{error};
                next match;
            }

	    my $stitle = $issue->{title};
	    if (length $stitle > 25) {
		(substr $stitle, 23) = '...';
	    }
	    my ($pre_ret, $suff_ret);
	    my @lines;
	    # issue text
	    unless ($comment) {
		next unless $id eq $issue->{id};
		@lines = split /\R/, $issue->{body};
		$pre_ret = sprintf "%s \cC43%d\cC (%s) by \cB%s\cB -\cC ",
		    (exists $issue->{pull_request} ? "Pull request" : "Issue"),
		    $thingnum,
		    $stitle,
		    _dehih($issue->{user}{login});
		$suff_ret = "";
	    }
	    else {
		my $comment = $ng->issue->comment($id);
		if (exists $comment->{error}) {
		    push @return, $comment->{error};
		    next match;
		}
		@lines = split /\R/, $comment->{body};
		$pre_ret = sprintf "%s \cC43%d\cC (%s) comment by \cB%s\cB -\cC ",
		    (exists $issue->{pull_request} ? "Pull request" : "Issue"),
		    $thingnum,
		    $stitle,
		    _dehih($comment->{user}{login});
		$suff_ret = " \cBon\cB ".($comment->{created_at}=~s/T.*//r);
	    }
	    while (@lines && $lines[0] =~ /^>/) {
		shift @lines;
	    }
	    my $text = join ' ', map { /^\s*(.*?)\s*$/ ? $1 : $_ } @lines;
	    my $maxlen = 290 - (length $pre_ret) - (length $suff_ret);
	    $text =~ s{\b(https?://github\.com/\S+)}{makeashorterlink($1)}ge;
	    if (length $text > $maxlen) {
		(substr $text, $maxlen - 3) = '...';
	    }
	    $text =~ s{\w+://\S+\.\.\.$}{...};
	    push @return, "$pre_ret$text$suff_ret";
	}

        # Right, handle it in the approriate way
        elsif ($thing ne 'commit') {
            warn "Handling issue $thingnum";
            my $issue = $ng->issue->issue($thingnum);
	    my $pr;
	    if (!exists $issue->{error} && $issue->{pull_request}) {
		$pr = $ng->pull_request->pull($thingnum);
		if (exists $pr->{error}) {
		    $pr = undef;
		}
	    }
            if (exists $issue->{error}) {
                push @return, $issue->{error};
                next match;
            }
            push @return, sprintf "%s \cC43%d\cC (\cC59%s\cC) by \cB%s\cB - \cC73%s\cC%s %s\{%s\cC\}",
		(exists $issue->{pull_request} ? "\cC29Pull request" : "\cC52Issue"),
                $thingnum,
                $issue->{title},
		_dehih($issue->{user}{login}),
                $project,
		($issue->{labels}&&@{$issue->{labels}}?" [".(join",",map{$_->{name}}@{$issue->{labels}})."]":""),
		($issue->{milestone} ? "MS:\cB$issue->{milestone}{title}\cB ": ($pr?$self->_pr_branch($ng, $pr):"")),
$pr&&$pr->{merged_at}?"\cC46merged on ".($pr->{merged_at}=~s/T.*//r):
$issue->{closed_at}?"\cC55closed on ".($issue->{closed_at}=~s/T.*//r):"\cC52".$issue->{state}." since ".($issue->{created_at}=~s/T.*//r);
        }

        # If it was a commit:
        elsif ($thing eq 'commit') {
            warn "Handling commit $thingnum";
            my $commit = $ng->git_data->commit($thingnum);
            if ($commit && !exists $commit->{error}) {
                my $title = ( split /\n+/, $commit->{message} )[0];
                my $url = $commit->{html_url};
                
                push @return, sprintf "Commit \cC43$thingnum\cC (\cC59%s\cC) by \cB%s\cB on %s - \cC73%s\cC %s",
                    $title,
		    _dehih($commit->{author}{login}||$commit->{committer}{login}||$commit->{author}{name}||$commit->{committer}{name}),
		    ($commit->{author}{date}=~s/T.*//r),
                    $project,
		    $self->_commit_branch($commit, $commit->{sha}),
		    ;
            } else {
                # We purposefully don't show a message on IRC here, as we guess
                # what might be a SHA, so we could be annoying saying that we
                # didn't match a commit when someone said a word that just
                # happened to look like it could be the start of a SHA.
                warn "No commit details for $thingnum \@ $project/$thingnum";
            }
        }
    }
    }
    
    @return = grep { _check_mass($mess->{who}, $mess->{channel}, $_) } @return;
    _expire_mass_blocks();
    return join "\n", @return;
}





1;

