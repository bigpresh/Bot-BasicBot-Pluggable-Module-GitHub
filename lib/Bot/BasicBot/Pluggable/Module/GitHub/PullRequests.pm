# A quick Bot::BasicBot::Pluggable module to fetch a count of open pull requests
# for a GitHub project.
#
# David Precious <davidp@preshweb.co.uk>

package Bot::BasicBot::Pluggable::Module::GitHub::PullRequests;
use strict;
use Bot::BasicBot::Pluggable::Module::GitHub;
use base 'Bot::BasicBot::Pluggable::Module::GitHub';
use LWP::Simple ();
use LWP::UserAgent;
use JSON;

sub help {
    return <<HELPMSG;
Monitors outstanding pull requests on a GitHub project.

Allows use of a !pr command to fetch the current count of open pull requests
including a tally by user.

Usage: !pr user/project, or just !pr for the default project, configured by
setting the 'github_project' setting using the Vars module (or by directly
setting the user_github_project setting in the bot's store).
HELPMSG
}


sub said {
    my ($self, $mess, $pri) = @_;
    
    return unless $pri == 2;

    if ($mess->{body} =~ /^!pr (?: \s+ (\S+))?/xi) {
        my $search = $1;

        my $project = $+{project} || $self->github_project($mess->{channel});
        return unless $project;

        # Search through all the projects to see if the search word matches
        my $project = $self->search_projects($mess->{channel}, $search)
                            || $project;

        if (!$project) {
            $self->reply(
                $mess, 
                "No project(s) to check; either specify"
                . " a project, e.g. '!pr username/project', or use the Vars"
                . " module to configure the github_project setting for this"
                . " module to set the default project to check."
            );
            return 1;
        }

        my $prs = $self->_get_pull_request_count($project);
        $self->say(
            channel => $mess->{channel},
            body => "Open pull requests for $project : $prs",
        );
        return 1; # "swallow" this message
    }
    return 0; # This message didn't interest us
}


sub _get_pull_request_count {
    my ($self, $project) = @_;

    my $url = "http://github.com/api/v2/json/pulls/" . $project;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $url);

    # Auth if necessary
    if (my $auth = $self->auth_for_project($project)) {
        my ($user, $token) = split /:/, $auth, 2;
        $req->authorization_basic("$user/token", "$token");
    }

    my $res = $ua->request($req) or return "Unknown - error fetching $url";

    my $pulls = JSON::from_json($res->content)
        or return "Unknown - error parsing API response";

    my %pulls_by_author;
    $pulls_by_author{$_}++
        for map { $_->{issue_user}{login} } @{ $pulls->{pulls} };
    my $msg = scalar @{ $pulls->{pulls} } . " pull requests open (";
    $msg .= join(", ", 
        map  { "$_:$pulls_by_author{$_}" }
        sort { $pulls_by_author{$b} <=> $pulls_by_author{$a} }
        keys  %pulls_by_author 
    );
    $msg .= ")";
    return $msg;
}

1;

