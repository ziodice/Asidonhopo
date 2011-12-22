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
            if ($nick eq $param->{bot}{irc}->nick_name())
            {
                $param->{bot}{irc}->yield(ctcp => $param->{whom} =>
                    "ACTION discards some spam from $param->{nick}.");
            }
            elsif ($nick eq $param->{bot}{irc}->nick_name())
            {
                $param->{bot}{irc}->yield(privmsg => $param->{whom} =>
                    "$param->{nick}: No.");
            }
            else
            {
                $param->{bot}{irc}->yield(privmsg => $param->{whom} =>
                    "$param->{nick}: OK, I'll tell $nick.");
                $param->{bot}{msg_add}->execute(time, $param->{nick}, $nick, $arg);
            }
        }
    }
    return 1;
}

1;
