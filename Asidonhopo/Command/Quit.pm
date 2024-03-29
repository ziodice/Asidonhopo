package Asidonhopo::Command::Quit;
use strict;
use warnings;

sub quit
{
    my $self = shift;
    my $param = shift;
    my $arg = join (' ', @_) // 'Shutdown';
    if ($param->{bot}->is_bot_admin($param->{who}))
    {
        $param->{bot}{irc}->call(shutdown => $arg);
        #$param->{bot}{killme} = 1;
        return 1;
    }
    else
    {
        $param->{bot}{irc}->yield(notice => $param->{nick} => 'You are not a bot administrator');
        return 0;
    }
}

1;
