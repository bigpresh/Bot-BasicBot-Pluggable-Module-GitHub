use v5.12;
package Bot::BasicBot::Pluggable::Module::GitHub::HookAnnounce;
use base qw(Bot::BasicBot::Pluggable::Module::GitHub);

# Use GitHub's hooks API to add web hooks so we can be told about pushes,
# issues, pull requests etc and announce them.

# Upon startup, add a hook matching all the event types to hit us, unless
# there's already one there (if there is, maybe delete & recreate it, just in
# case?)

# I guess arranging all the hooks makes us a hooker?

# See http://developer.github.com/v3/repos/hooks/

use POE qw/Component::Server::HTTP/;
use CGI::Simple;
use JSON qw(from_json);

sub help {
    my ($self, $msg) = @_;
    return "GitHub Module for interpreting github service hook postbacks";
}

sub init {
    my $self = shift;
    $self->config({ user_port => 3333, user_url => '/github' });


    # For every repo we're configured to work with, get the list of hooks
    # configured, and add any that are missing via Net::GitHub::V3

    # Configure each hook to hit this server with the event type appended, e.g.:
    # http://hostname:port/bbmp-github-hook?event=issues
    
    POE::Component::Server::HTTP->new(
        Port           => $self->get('user_port'),
        ContentHandler => {
            $self->get('user_url') => sub {
                my ($req, $res) = @_;
                my $cgi = CGI::Simple->new($req->content);
                my $event = $cgi->param('event')
                    or return "Missing event type param";
                my $payload_json = $cgi->param('payload')
                    or return "Missing payload";

                my $payload = JSON::from_json($payload_json)
                    or return "Invalid JSON?";
                
                $self->handle_hook_payload($event, $payload);
            },
        },
    );
}

# Handle a hook being hit.  Receives a payload, the format of which varies
# depending on the type of event.
sub handle_hook_payload {
    my ($self, $event_type, $payload) = @_;
    my $payload = CGI::Simple->new($req->content)->param('payload');
    ...
}

sub commit {
    my ($self, $payload) = @_;
    my @channels = $self->bot->channels;

    for my $commit (@{ $payload->{commits} || [] }) {
        my $hash_id = substr($commit->{id}, 0, 7);
        my $branch = (split(/\//, $payload->{ref}))[2];
        for (@channels){
            $self->bot->notice(
                channel => $_,
                body => "[$payload->{repository}{name}/$branch $hash_id]: ".
                        "($commit->{author}{name}) $commit->{message}",
            );
        }
    }
}

1;
