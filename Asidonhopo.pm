package Asidonhopo;
use strict;
use warnings;

use feature 'say';

# We want database access, configuration files, POE
# with IRC component and ANSI color sequences for
# screen-logging.
use DBI;
use Config::Any;
use Term::ANSIColor qw(:pushpop :constants);
use Module::Pluggable search_path => ['Asidonhopo::Command'], require => 1;
use POE qw(
    Component::IRC::State
    Component::IRC::Plugin::NickReclaim
    Component::IRC::Plugin::NickServID
    Component::IRC::Plugin::AutoJoin
    Component::IRC::Plugin::Connector
    Component::IRC::Plugin::CTCP
    Component::IRC::Plugin::Logger
);

sub error
{
    my $enum = shift;
    my @errors =
    (
        'No configuration file found',
        'Unconfigured configuration file',
        'Database could not be opened',
        'Could not prepare statement',
        'No database file exists, populating...',
    );
    print LOCALCOLOR RED BOLD, "Error $enum: ";
    say                        "$errors[$enum]";
}

sub fatalerror
{
    &error;
    exit 1;
}

sub warning
{
    my $wnum = shift;
    my @warnings =
    (
        'Configuration file should be findable',
    );
    print LOCALCOLOR YELLOW BOLD, "Warning $wnum: ";
    say                           "$warnings[$wnum]";
}

sub notice
{
    my $nnum = shift;
    my @notices =
    (
        "Creating example configuration file in $_[0]",
        "Created example configuration file in $_[0]",
    );
    print LOCALCOLOR BLUE BOLD, "Notice $nnum: ";
    say                         "$notices[$nnum]";
}

sub empty_config_error
{
    my $example_file_name = "config.yaml";
    error 0;
    if ( -e $example_file_name )
    {
        warning 0;
    }
    else
    {
        notice 0, $example_file_name;
        open my $example_file, '>', $example_file_name;
        print $example_file "---\n";
        print $example_file "nick: SuperBot_nick\n";
        print $example_file "username: mybotuser\n";
        print $example_file "ircname: 'My SuperBot (IRC bot)'\n";
        print $example_file "server: '127.0.0.1'\n";
        print $example_file "channels:\n";
        print $example_file "  - '#channel'\n";
        print $example_file "  - '#another'\n";
        print $example_file "nickservkey: key\n";
        print $example_file "logdir: ./log\n";
        print $example_file "cmd: '!'\n";
        print $example_file "admin: yournick\n";
        print $example_file "# remove this or it won't work\n";
        print $example_file "unconfigured: yes\n";
        close $example_file;
        notice 1, $example_file_name;
    }
}

sub create
{
    my $self = { };
    bless $self, shift;
    # Just take the first config file...
    my $config_pair = Config::Any->load_stems({
            use_ext => 1,
            stems => ['config']})->[0];
    if (not defined $config_pair)
    {
        $self->empty_config_error;
        return undef;
    }
    $self->{config} = (values %$config_pair)[0];

    if ($self->{config}{unconfigured})
    {
        fatalerror 1;
        return undef;
    }
    if (not -e $self->{config}{dbfile} )
    {
        error 4;
        $self->{createdb} = 1;
    }

    $self->{dbh} = DBI->connect(
        "dbi:SQLite:dbname=$self->{config}{dbfile}",
        "",
        "",
        {
            AutoCommit => 1,
        },
    ) or (fatalerror 2);
    $self->{dbh}->do("PRAGMA foreign_keys = ON");
    if ($self->{createdb})
    {
        $self->{dbh}->begin_work;
        $self->{dbh}->do(q{CREATE TABLE triggers (id INTEGER PRIMARY KEY, trigger VARCHAR(300) UNIQUE, speech VARCHAR(300) )});
        $self->{dbh}->commit;
        exit 1;
    }
    $self->{trigger_get} = $self->{dbh}->prepare(
        q{SELECT speech FROM triggers WHERE ? REGEXP trigger}
    ) or (fatalerror 3);

    $self->{irc} = POE::Component::IRC::State->spawn
    (
        nick     => $self->{config}{nick},
        username => $self->{config}{username},
        ircname  => $self->{config}{ircname},
        server   => $self->{config}{server},
        alias    => 'ircbot',
        use_ssl  => 1,
    );

    POE::Session->create
    (
        object_states =>
        [
            $self =>
            [
                '_start',
                '_stop',
                'process_chat',
                'irc_001',
                'irc_public',
                'irc_ctcp_action',
                'irc_join',
                'irc_kick',
                'irc_msg',
                'irc_nick',
                'irc_notice',
                'irc_part',
                'irc_quit',
                'irc_topic',
                'irc_identified',
            ]
        ]
    );
    return $self;
}

sub _start
{
    my $self = shift;
    $self->{irc}->yield( register => 'all' );
    $self->{irc}->plugin_add(
        'Connector' => POE::Component::IRC::Plugin::Connector->new());
    $self->{irc}->plugin_add(
        'NickServID' => POE::Component::IRC::Plugin::NickServID->new(
            Password => "$self->{config}{nick} $self->{config}{nickservkey}",
        ));
    $self->{irc}->plugin_add(
        'AutoJoin' => POE::Component::IRC::Plugin::AutoJoin->new());
    $self->{irc}->plugin_add(
        'NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new());
    $self->{irc}->plugin_add(
        'CTCP' => POE::Component::IRC::Plugin::CTCP->new(
            source     => 'https://github.com/b-code/Asidonhopo',
            version    => 'Asidonhopo IRC bot',
            clientinfo => 'Using POE::Component::IRC::State',
            userinfo   => 'Asidonhopo IRC bot',
            # ...
        ));
    $self->{irc}->plugin_add(
        'Logger' => POE::Component::IRC::Plugin::Logger->new(
            Path         => $self->{config}{logdir},
            Public       => 1,
            Private      => 1,
            DCC          => 1,
            Notices      => 1,
            Sort_by_date => 1,
        ));
    $self->{irc}->yield( connect  => { }   );
}

sub _stop
{
}

sub irc_001
{
}

sub irc_identified
{
    my $self = shift;
    $self->{irc}->yield(join => $_) for @{$self->{config}{channels}};
}

# how, who, whom, what, id?
# how is:
# 0 - public
# 1 - private
# 2 - action
# 3 - notice
sub process_chat
{
    my $self = $_[OBJECT];
    my $param = {
        bot  => $self,
        who  => $_[ARG0],
        self => $self->{irc}->nick_name,
        whom => $_[ARG1][0],
        what => $_[ARG2],
        id   => $_[ARG3] // 1,
        how  => $_[ARG4],
        me   => $self->{irc}->nick_name(),
    };
    $param->{nick} = (split (/!/, $param->{who}))[0];
    my @cmds = $self->plugins;
    if ($param->{what} =~ /^$self->{config}{cmd}\s*(\w+)(?:\s+(\S.*))?/)
    {
        my $command = $1;
        my $args    = $2 // '';
        for my $mod (@cmds)
        {
            next unless $mod->can($command);
            last if $mod->$command($param, split (/\s+/, $args));
        }
    }
    else
    {
        # if it's odd... private
        if ($param->{how} & 1)
        {
            return;
        }
        else
        {
            $param->{what} =~ s/$param->{me}/§me§/g;
            if (substr ($param->{what}, 0, 1) eq '§')
            {
                substr ($param->{what}, 0, 1) = '\§';
            }
            if ($param->{how} == 2)
            {
                $param->{what} = '§' . $param->{what};
            }
            # trigger check
            $self->{trigger_get}->execute($param->{what});
            my $text = $self->{trigger_get}->fetchrow_array;
            if ($text)
            {
                $text =~ s/§nick§/$param->{nick}/g;
                $self->speak ($param->{whom}, $text);
            }
        }
    }
}

sub speak
{
    my $self = shift;
    my $target = shift;
    my $message = shift;
    my @speech = split /§then§/, $message;
    for (@speech)
    {
        if (/^§act§(.*)/)
        {
            $_ = [1, $1];
        }
        else
        {
            $_ = [0, $_];
        }
    }
    for (@speech)
    {
        if ($_->[0])
        {
            $self->{irc}->yield (ctcp => $target => "ACTION $_->[1]");
        }
        else
        {
            $self->{irc}->yield (privmsg => $target => $_->[1]);
        }
    }
}

sub irc_public
{
    $_[KERNEL]->yield (process_chat => (@_[ARG0..ARG3], 0));
}

sub irc_msg
{
    $_[KERNEL]->yield (process_chat => (@_[ARG0..ARG3], 1));
}

sub irc_ctcp_action
{
    $_[KERNEL]->yield (process_chat => (@_[ARG0..ARG3], 2));
}

sub irc_notice
{
    #$_[KERNEL]->yield (process_chat => (@_[ARG0..ARG3], 3));
}

sub irc_join
{
}

sub irc_kick
{
}

sub irc_part
{
}

sub irc_quit
{
}

sub irc_nick
{
}

sub irc_topic
{
}

sub irc_mode
{
}

1;
