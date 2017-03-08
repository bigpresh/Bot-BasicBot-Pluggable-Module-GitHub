package Bot::BasicBot::Pluggable::Module::GitHub::IssueSearch;
use strict;
use WWW::Shorten::GitHub;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
use LWP::Simple ();
use List::Util 'min';
use JSON;

sub help {
    return <<HELPMSG;
Search issues

find [1-4] [open|closed|merged] <issue|pr> query [in <project>]
HELPMSG
}

sub _dehih {
    my $r = shift;
    $r =~ s/^(.)(.*)$/$1\cB\cB$2/g;
    $r
}

sub said {
    my ($self, $mess, $pri) = @_;

    return unless $pri == 2;

    return if $mess->{who} =~ /^Not-/;
    return if $mess->{body} =~ m{://git};
    my $body = $mess->{body};

    my $readdress = $mess->{channel} ne 'msg' && $body =~ s/\s+@\s+(\S+)[.]?\s*$// ? $1 : '';

    if ($body =~ /^find \s+
			  (?: (?<count> \d+) \s+ )?
			  (?:(?<status> open | closed | merged ) \s+)?
			  (?<type> issue | pr | pull \s+ request )s? \s+
			  (?: (?: with | matching ) \s+ )?
			  (?<expr> \S+ (?:\s+\S+)* ) /xi) {
	my $realcount = $+{count} || 1;
	my $count = min 3, $realcount;
	my $expr = $+{expr};
	my $type = $+{type};
	$type = 'pr' if $type =~ /^p/i;
	my $status = $+{status};
        my $project;
	if ($expr =~ s/\s+ in \s+ (?<project> \S+) \s* $//xi) {
	    $project = $+{project};
	}
	$project ||= $self->github_project($mess->{channel});
	$expr = "is:\L$status\E $expr" if $status;
	$expr =~ s{ (?:^|\s) \K ( -? ) \[ ( .+? ) \] (?=\s|$) }{
	    join ' ', map {
		$1 . 'label:' . ($_ =~ /\s/ ? qq{"$_"} : $_)
	    } split ',', $2
	}gex;
	my $orig_expr = $expr;
	my $search_type = 'issues';
	if ('pr' eq lc $type && $expr !~ /\b is:pr \b/xi) {
	    $expr = "is:pr $expr";
	    $search_type = 'pulls';
	}
	if ($project !~ m{/}) {
	    if ($self->github_project($mess->{channel}) =~ m{^(.*?)/} ) {
		$project = "$1/$project";
	    } else {
		return;
	    }
	}
        return unless $project;
        my $ng = $self->ng($project) or return;
	warn "sending search repo:$project $expr";
	my $res = $ng->search->issues({q => "repo:$project $expr"});
	unless ($res && $res->{items}) {
	    warn "no result for query $expr.";
	    return;
	}
	my @ret;
	while ($count-- && @{$res->{items}}) {
	    my $issue = shift @{$res->{items}};
	    my $pr;
	    if (!exists $issue->{error} && $issue->{pull_request}) {
		$pr = $ng->pull_request->pull($issue->{number});
		if (exists $pr->{error}) {
		    $pr = undef;
		}
	    }
            if (exists $issue->{error}) {
                push @ret, $issue->{error};
                next;
            }
            push @ret, sprintf "%s \cC43%d\cC (\cC59%s\cC) by \cB%s\cB - \cC73%s\cC%s \{%s\cC\}",
		(exists $issue->{pull_request} ? "\cC29Pull request" : "\cC52Issue"),
                $issue->{number},
                $issue->{title},
		_dehih($issue->{user}{login}),
                makeashorterlink($issue->{html_url}),
		($issue->{labels}&&@{$issue->{labels}}?" [".(join",",map{$_->{name}}@{$issue->{labels}})."]":""),
$pr&&$pr->{merged_at}?"\cC46merged on ".($pr->{merged_at}=~s/T.*//r):
$issue->{closed_at}?"\cC55closed on ".($issue->{closed_at}=~s/T.*//r):"\cC52".$issue->{state}." since ".($issue->{created_at}=~s/T.*//r);
	}
	if (@ret) {
	    my $info;
	    my $sen;
	    if (@{$res->{items}}) {
		$sen = "and \cB" . ($res->{total_count}-@ret) . "\cB more: " . makeashorterlink("https://github.com/$project/$search_type?q=".($orig_expr=~y/ /+/r));
	    }
	    if (@ret > 1) {
		$info = join "\n", "\c_Issues matching\c_" . ($sen ? " ( $sen )" : ""), @ret;
	    } else {
		$info = join ' ', "\c_Matching issue:\c_", @ret, $sen;
	    }
	    if ($readdress) {
		my %hash = %$mess;
		$hash{who} = $readdress;
		$hash{address} = 1;
		$self->reply(\%hash, $info);
		return 1;
	    }
	    return $info;
	} else {
	    return "Nothing found...";
	}
    }
    return;
}

1;

