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

    if ($mess->{body} =~ /^!pr (?: \s+ (\S+))?/xi) {
        my $check_project = $1;
        $check_project ||=  get_default_project(
            $self->get('user_github_project'), $mess->{channel}
        );
        if (!$check_project) {
            $self->reply(
                $mess, 
                "No GitHub project defined"
            );
            return 1;
        }
        for my $project (split /,/, $check_project) {
            my $prs = $self->_get_pull_request_count($project);
            $self->say(
                channel => $mess->{channel},
                body => "Open pull requests for $project : $prs",
            );
        }
        return 1; # "swallow" this message
    }
    return 0; # This message didn't interest us
}





1;

