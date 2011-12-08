package Asidonhopo::Command::Help;
use strict;
use warnings;

sub help
{
    shift; # class name
    my $param = shift;
    if ($param->{how} == 0)
    {
        $param->{bot}{irc}->yield(
            privmsg => $param->{whom} =>
            "No help yet! Ask $param->{bot}{config}{admin}."
        );
    }
    return 1;
}

1;
