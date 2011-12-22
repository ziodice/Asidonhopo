package Asidonhopo::Command::Tell;
use strict;
use warnings;

sub tell
{
    shift; # class name
    my $param = shift;
    my $nick = shift;
    # NOTE: This has been split with /\s+/ so it also
    # replaces whitespace in the message.
    # So it's a nice side-effect :)
    my $arg = join (' ', @_);
    if ($param->{how} == 0)
    {
        if (defined $nick and ($arg // '') ne '')
        {
            $param->{bot}{msg_add}->execute(time, $param->{nick}, $nick, $arg);
        }
    }
    return 1;
}

1;
