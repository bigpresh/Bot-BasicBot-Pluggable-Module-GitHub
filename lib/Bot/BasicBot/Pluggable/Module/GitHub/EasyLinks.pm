# A quick Bot::BasicBot::Pluggable module to provide easy links when someone
# mentions an issue / pull request / commit.
#
# Use the vars module to configure the project in question.  (So, this will only
# really be of use to a bot in a single-project-related channel.)
#
# David Precious <davidp@preshweb.co.uk>

package Bot::BasicBot::Pluggable::Module::GitHubLinks;
use strict;
use base 'Bot::BasicBot::Pluggable::Module';
use LWP::Simple ();
use JSON;

sub help {
    return <<HELPMSG;
Provide convenient links to GitHub issues/pull requests/commits etc.

If someone says e.g. "Issue 42", the bot will helpfully provide an URL to view
that issue directly.

The project these relate to must be configured using the vars module to set the
'default project' setting (or directly set user_default_project in the bot's
store).

HELPMSG
}


sub said {
    my ($self, $mess, $pri) = @_;
    
    return unless $pri == 2;

    # Firstly, do nothing if the message doesn't look at all interesting:
    return 0 if $mess->{body} !~ /issue|pr|pull request/i;

    # OK, find out what project is appropriate for this channel (if there isn't
    # one, go no further)
    my $project = $self->github_project($mess->{channel})
        or return 0;

    # Handle issues, first
    if (my ($issue_num) = $mess->{body} =~ m{ (?:Issue|GH) [\s-]* (\d+) }xi) {
        my $issue_url = "https://github.com/$project/issues/$issue_num";
        my $title = URI::Title::title($issue_url);
        return "Issue $issue_num ($title) - $issue_url";
    }

    # Similarly, pull requests:
    if (my($pr_num) = $mess->{body} =~ m{ (?:PR|pull request) [\s-]* (\d+) }xi) 
    {
        my $pull_url = "https://github.com/$project/pull/$pr_num";;
        my $title = URI::Title::title($pull_url);
        return "Pull request $pr_num ($title) - $pull_url";
    }

    
    # OK, it's not something we want to respond to:
    return 0;
}





1;

