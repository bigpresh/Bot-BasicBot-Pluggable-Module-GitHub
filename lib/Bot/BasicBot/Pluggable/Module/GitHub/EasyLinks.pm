# A quick Bot::BasicBot::Pluggable module to provide easy links when someone
# mentions an issue / pull request / commit.
#
# Use the vars module to configure the project in question.  (So, this will only
# really be of use to a bot in a single-project-related channel.)
#
# David Precious <davidp@preshweb.co.uk>

package Bot::BasicBot::Pluggable::Module::GitHub::EasyLinks;
use strict;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
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

    # Loop through matching things in the message body, assembling quick links
    # ready to return.
    my @return;
    while ($mess->{body} =~ m{ 
        (?:  
            # "Issue 42", "PR 42" or "Pull Request 42"
            (?<thing> (?:issue|gh|pr|pull request) ) 
            \s*
            (?<num> \d+)
        |                
            # Or a commit SHA
            (?<sha> [0-9a-f]{6,})
        )    
        # Possibly with a specific project repo ("user/repo") appeneded
        (?: \s* \@ \s* (?<project> \w+/\w+) )?
        }gxi
    ) {

        my $project = $+{project} || $self->github_project($mess->{channel});
        next unless $project;

        # First, extract what kind of thing we're looking at, and normalise it a
        # little, then go on to handle it.
        my $thing    = $+{thing};
        my $thingnum = $+{num};

        if ($+{sha}) {
            $thing    = 'commit';
            $thingnum = $+{sha};
        }

        # Right, handle it in the approriate way
        if ($thing =~ /Issue|GH/i) {
            my $issue_url = "https://github.com/$project/issues/$thingnum";
            my $title = URI::Title::title($issue_url);
            push @return, "Issue $thingnum ($title) - $issue_url";
        }

        # Similarly, pull requests:
        if ($thing =~ /(?:pr|pull request)/i) {
            my $pull_url = "https://github.com/$project/pull/$thingnum";
            my $title = URI::Title::title($pull_url);
            push @return, "Pull request $thingnum ($title) - $pull_url";
        }

        # If it was a commit:
        if ($thing eq 'commit') {
            my $commit = JSON::from_json(
                LWP::Simple::get(
                    "https://github.com/api/v2/json/commits/show/$project/$thingnum"
                )
            );
            # If we got nothing back, assume it wasn't actually a valid SHA; if we
            # got details, use them
            if ($commit) {
                my $commit = $commit->{commit};  # ugh.

                # OK, take the first line of the commit message as a title:
                my $summary = (split /\n/, $commit->{message} )[0];

                my $commit_url = "https://github.com" . $commit->{url};
                push @return, "Commit $thingnum ($summary) - $commit_url";
            } else {
                warn "No commit details for $project/$thingnum";
            }
        }
    }
    
    return join "\n", @return;
}





1;

