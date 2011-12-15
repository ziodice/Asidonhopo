package Asidonhopo::Command::Dcc;
use strict;
use warnings;

sub dcc
{
    my $self = shift;
    my $param = shift;
    my $arg = join (' ', @_) // 'Shutdown';
    if ($param->{bot}->is_bot_admin($param->{who}))
    {
        $param->{bot}{irc}->yield(dcc => $param->{nick} => 'CHAT');
        return 1;
    }
    else
    {
        $param->{bot}{irc}->yield(notice => $param->{nick} => 'You are not a bot administrator');
        return 0;
    }
}

1;
