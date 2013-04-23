package UR::Service::WebServer;

use strict;
use warnings;

use UR;
use UR::Service::WebServer::Server;
use IO::File;

class UR::Service::WebServer {
    has => [
        host => { is => 'String',
                    default_value => 'localhost',
                    doc => 'IP address to listen on' },
        port => { is => 'Integer',
                    default_value => undef,
                    doc => 'TCP port to listen on' },
    ],
    has_optional => [
        server  => { is => 'HTTP::Server::PSGI', calculate_from => ['host','port'], is_constant => 1,
                    calculate => q(
                        return UR::Service::WebServer::Server->new(
                            host => $host,
                            port => $port,
                            timeout => $self->timeout,
                            server_ready => sub { $self->_announce() },
                        );
                    ), },
        timeout => { is => 'Integer',
                        default_value => undef,
                        doc => 'Timeout for read and write events' },
        idle_timeout => { is => 'Integer', default_value => undef,
                        doc => 'Exit the event loop after being idle for this many seconds' },
        routers => { is => 'UR::Service::WebServer::Router', is_many => 1 },
    ],
};

sub _announce {
    my $self = shift;

    my $sock = $self->server->listen_sock;
    $self->status_message(sprintf('Listening on http://%s:%d/', $sock->sockhost, $sock->sockport));
    return 1;
}

sub run {
    my($self, $cb) = @_;

    $cb ||= sub {
        my $self = shift;
        my @routers = $self->routers;
        foreach (@routers) {
            my $rv = $_->route(@_);
            return $rv if $rv;
        }
        return [ 404, [ 'Content-Type' => 'text/html'], ['Not found']];
    };

    my $wrapped_cb = sub {
        $cb->($self, @_);
    };

    my $timeout = $self->idle_timeout;
    local $SIG{'ALRM'} = sub { die "alarm\n" };
    eval {
        alarm($timeout);
        $self->server->run($wrapped_cb);
    };
    alarm(0);
    die $@ unless $@ eq "alarm\n";
}

my %mime_types = (
    'js'    => 'application/javascript',
    'html'  => 'text/html',
    'css'   => 'text/css',
    '*'     => 'text/plain',
);
sub _mime_type_for_filename {
    my($self, $pathname) = @_;
    my($ext) = ($pathname =~ m/\.(\w+)$/);
    return $mime_types{$ext} || $mime_types{'*'};
}
sub _file_opener_for_directory {
    my($self, $dir) = @_;
    return sub {
        (my $pathname = shift) =~ s#/?\.\.##g;  # Remove .. - don't want them escaping the given directory tree
        return IO::File->new( join(',', $dir, $pathname), 'r');
    };
    
}
sub file_handler_for_directory {
    my($self, $dir, $does_streaming) = @_;

    my $opener = $self->_file_opener_for_directory($dir);

    return sub {
        my($self, $pathname) = @_;

        my $fh = $opener->($pathname);
        unless($fh) {
            return [ 404, [ 'Content-Type' => 'text/html'], ['Not found']];
        }
        my $type = $self->_mime_type_for_filename($pathname);
        if ($does_streaming) {
            return [ 200, ['Content-Type' => $type], $fh];
        } else {
            local $/;
            my $buffer = <$fh>;
            return [ 200, ['Content-Type' => $type], [$buffer]];
        }
    };
}

sub delete {
    my $self = shift;
    $self->server->listen_sock->close();
    $self->{server} = undef;
    $self->SUPER::delete(@_);
}

1;