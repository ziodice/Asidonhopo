package Asidonhopo::Command::Id;
use strict;
use warnings;

sub id
{
    my $self = shift;
    my $param = shift;
    my $user = shift;
    my $key = shift;
    my $manip = undef;
    for (@{$param->{bot}{config}{control}})
    {
        $manip = $_ if ($_->{name} eq $user);
    }
    unless (defined $manip)
    {
        $param->{bot}{irc}->yield(notice => $param->{nick} =>
            'This is not a valid user.');
        return 0;
    }
    if (not defined $manip->{key})
    {
        $param->{bot}{irc}->yield(notice => $param->{nick} =>
            "Your access is disabled! Please contact $param->{bot}{config}{admin}.");
        return 0;
    }
    # 1 == private message
    if ($param->{bot}->is_bot_admin($param->{who}))
    {
        my $tmp = 0;
        unless ($param->{private})
        {
            $tmp = 1;
            $manip->{key} = undef;
            $param->{bot}{irc}->yield(notice => $param->{whom} =>
                "Public identification attempted for $user; removing key...");
        }
        $param->{bot}{irc}->yield(notice => $param->{nick} =>
            'You are already identified.');
        $param->{bot}{irc}->yield(notice => $param->{nick} =>
            'Removed your access key (attempted public ID)') if $tmp;
        return 0;
    }
    else
    {
        if ($manip->{key} eq $key)
        {
            if ($param->{how} != 1)
            {
                $manip->{key} = undef;
                $param->{bot}{irc}->yield(notice => $param->{whom} =>
                    "Public identification attempted for $user; removing key...");
                return 0;
            }
            else
            {
                $manip->{mask} = $param->{who};
                if ($param->{bot}->is_bot_admin($param->{who}))
                {
                    $param->{bot}{irc}->yield(notice => $param->{nick} =>
                        "Successfully identified as $user.");
                }
                else
                {
                    $param->{bot}{irc}->yield(notice => $param->{nick} =>
                        "ERROR! Something bad happened; you are not identified while you should be. D:");
                }
            }
        }
    }
    return 1;
}

1;
