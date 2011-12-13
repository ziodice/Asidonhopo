package Asidonhopo::Command::Quit;
use strict;
use warnings;

sub quit
{
    my $self = shift;
    my $param = shift;
    my $arg = join (' ', @_) // 'Shutdown';
    if ($param->{nick} eq $param->{bot}{config}{admin} and $param->{id})
    {
        $param->{bot}{irc}->call(shutdown => $arg);
        #$param->{bot}{killme} = 1;
        return 1;
    }
    else
    {
        $param->{bot}{irc}->yield(notice => $param->{nick} => 'You are not the bot admin');
        return 0;
    }
}

1;
