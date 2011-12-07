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
    );
    print LOCALCOLOR RED BOLD, "Error $enum: ";
    say                        "$errors[$enum]";
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
        error 1;
        return undef;
    }

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

sub irc_public
{
}

sub irc_msg
{
}

sub irc_ctcp_action
{
}

sub irc_notice
{
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
