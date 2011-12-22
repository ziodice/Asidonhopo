package Asidonhopo;
use strict;
use warnings;

use feature 'say';

# We want database access, configuration files, POE
# with IRC component and ANSI color sequences for
# screen-logging.
use DBI;
use URI;
use XML::Feed;
use Config::Any;
use Term::ANSIColor qw(:pushpop :constants);
use Module::Pluggable search_path => ['Asidonhopo::Command'], require => 1;
require POE::Component::IRC::Common;
use POE qw(
    Component::IRC::State
    Component::IRC::Plugin::NickReclaim
    Component::IRC::Plugin::NickServID
    Component::IRC::Plugin::AutoJoin
    Component::IRC::Plugin::Connector
    Component::IRC::Plugin::CTCP
    Component::IRC::Plugin::Logger
    Component::IRC::Plugin::FollowTail
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
        print $example_file "# Basic bot data\n";
        print $example_file "nick: SuperBot_nick\n";
        print $example_file "username: mybotuser\n";
        print $example_file "ircname: 'My SuperBot (IRC bot)'\n";
        print $example_file "server: '127.0.0.1'\n";
        print $example_file "channels:\n";
        print $example_file "  - '#channel'\n";
        print $example_file "  - '#another'\n";
        print $example_file "nickservkey: key\n";
        print $example_file "logdir: ./log\n";
        print $example_file "# Tail this file for updates\n";
        print $example_file "tailfile: file_to_tail\n";
        print $example_file "dbfile: my.db\n";
        print $example_file "# Uncomment this to track an RSS feed\n";
        print $example_file "#feed: 'http://127.0.0.1/feed'\n";
        print $example_file "# Command prefix\n";
        print $example_file "cmd: '!'\n";
        print $example_file "# Admin info\n";
        print $example_file "admin: yournick\n";
        print $example_file "# You can add new blocks, too\n";
        print $example_file "control:\n";
        print $example_file "  - name: accname\n";
        print $example_file "    mask: 'nick!user\@host'\n";
        print $example_file "    key: 'yourkey'\n";
        print $example_file "# remove this or it won't work\n";
        print $example_file "unconfigured: yes\n";
        close $example_file;
        notice 1, $example_file_name;
    }
}

sub is_bot_admin
{
    my $self = shift;
    my $mask = shift;
    for (@{$self->{config}{control}})
    {
        return 1 if ($mask =~ /$_->{mask}/);
    }
    return 0;
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
        $self->{dbh}->do(q{CREATE TABLE posts (id INTEGER PRIMARY KEY, uuid VARCHAR(30) UNIQUE )});
        $self->{dbh}->do(q{CREATE TABLE seen (id INTEGER PRIMARY KEY, nick VARCHAR(30) UNIQUE, state INTEGER, msg VARCHAR(500) )});
        $self->{dbh}->do(q{CREATE TABLE msg (id INTEGER PRIMARY KEY, timespec INTEGER, sender VARCHAR(30), recipient VARCHAR(30), text VARCHAR(300))});
        $self->{dbh}->commit;
        exit 1;
    }
    unless ( -e $self->{config}{tailfile} ) {
        open my $tmp, '>', $self->{config}{tailfile};
        print $tmp '';
        close $tmp;
    }
    $self->{trigger_get} = $self->{dbh}->prepare(
        q{SELECT speech FROM triggers WHERE ? REGEXP trigger}
    ) or (fatalerror 3);
    $self->{blog_find} = $self->{dbh}->prepare(
        q{SELECT id FROM posts WHERE uuid = ?}
    ) or (fatalerror 3);
    $self->{blog_add} = $self->{dbh}->prepare(
        q{INSERT INTO posts (uuid) VALUES (?)}
    ) or (fatalerror 3);
    $self->{seen_add} = $self->{dbh}->prepare(
        q{INSERT INTO seen (nick, time, state, p1, p2) VALUES (?,?,?,?,?)}
    ) or (fatalerror 3);
    $self->{seen_del} = $self->{dbh}->prepare(
        q{DELETE FROM seen WHERE nick = ?}
    ) or (fatalerror 3);
    $self->{seen_check} = $self->{dbh}->prepare(
        q{SELECT time, state, p1, p2 FROM seen WHERE nick = ?}
    ) or (fatalerror 3);
    $self->{msg_add} = $self->{dbh}->prepare(
        q{INSERT INTO msg (timespec, sender, recipient, text) VALUES (?,?,?,?)}
    ) or (fatalerror 3);
    $self->{msg_check} = $self->{dbh}->prepare(
        q{SELECT id, timespec, sender, recipient, text FROM msg WHERE recipient = ?}
    ) or (fatalerror 3);
    $self->{msg_del} = $self->{dbh}->prepare(
        q{DELETE FROM msg WHERE id = ?}
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
                'timer',
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
                'irc_tail_input',
                'irc_dcc_start',
                'irc_dcc_chat',
                'irc_dcc_done',
                'irc_dcc_error',
                'keepalive',
            ]
        ]
    );
    return $self;
}

sub _start
{
    my $self = $_[OBJECT];
    $self->{irc}->yield( register => 'all' );
    $self->{irc}->plugin_add(
        'Connector' => POE::Component::IRC::Plugin::Connector->new(
            delay => 60,
            reconnect => 30,
        ));
    $self->{irc}->plugin_add(
        'NickServID' => POE::Component::IRC::Plugin::NickServID->new(
            Password => "$self->{config}{nick} $self->{config}{nickservkey}",
        ));
    $self->{irc}->plugin_add(
        'AutoJoin' => POE::Component::IRC::Plugin::AutoJoin->new());
    $self->{irc}->plugin_add(
        'NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new());
    $self->{irc}->plugin_add(
        'FollowTail' => POE::Component::IRC::Plugin::FollowTail->new(
            filename => $self->{config}{tailfile},
        ));
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
    $_[KERNEL]->delay(timer => 30);
    $_[KERNEL]->delay(keepalive => 40);
}

sub _stop
{
    exit;
}

sub irc_001
{
}

sub irc_identified
{
    my $self = shift;
    $self->{irc}->yield(join => $_) for @{$self->{config}{channels}};
}

sub see
{
    my $self  = shift;
    my $nick  = shift;
    my $state = shift;
    my $msg   = shift;
    my $p2    = shift;
    $self->{dbh}->begin_work;
    $self->{seen_del}->execute($nick);
    $self->{seen_add}->execute($nick, time, $state, $msg, $p2);
    $self->{dbh}->commit;
}

sub seen
{
    my $self = shift;
    my $nick = shift;
    $self->{seen_check}->execute($nick);
    return $self->{seen_check}->fetchrow_arrayref;
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
    $self->on_activity();
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
    if ($param->{how} & 1)
    {
        $param->{private} = 1;
        $param->{target} = $param->{nick};
    }
    else
    {
        $param->{private} = 0;
        $param->{target} = $param->{whom};
        $self->{msg_check}->execute($param->{nick});
        while ($_ = $self->{msg_check}->fetchrow_arrayref())
        {
            $self->{msg_del}->execute($_->[0]);
            $self->{irc}->yield(privmsg => $param->{whom} =>
                "$_->[3], I have a message for you. $_->[2] said ("
                . gmtime($_->[1])
                . "): $_->[4]"
            );
        }
    }
    $self->seen($param->{nick}, $param->{how}, $param->{what});
    my @cmds = $self->plugins;
    if ($param->{what} =~ /^$self->{config}{cmd}\s*(\w+)(?:\s+(\S.*))?/)
    {
        my $command = $1;
        my $args    = $2 // '';
        for my $mod (@cmds)
        {
            if ($mod->can(lc $command) and not $mod->can($command))
            {
                $self->{irc}->yield(privmsg => $param->{whom} => "$param->{nick}: Try that in lowercase.");
                last;
            }
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

sub timer
{
    $_[OBJECT]{updatenow} = 1;
    $_[KERNEL]->delay(timer => 180) unless $_[OBJECT]{killme};
}

sub keepalive
{
    $_[OBJECT]{irc}->yield(ping => time);
    $_[KERNEL]->delay(keepalive => 40) unless $_[OBJECT]{killme};
}

sub on_activity
{
    my $self = $_[OBJECT];
    if ($self->{updatenow})
    {
        $self->{updatenow} = 0;
        # Just don't specify it and Asidonhopo won't check.
        if (defined $self->{config}{feed})
        {
            my $feed = XML::Feed->parse(URI->new($self->{config}{feed}));
            for ($feed->entries)
            {
                unless ($self->{blog_find}->execute($_->id)
                        and $self->{blog_find}->fetchrow_array())
                {
                    $self->{blog_add}->execute($_->id);
                    my $title = $_->title;
                    my $link  = $_->link;
                    open my $f, '>>', $self->{config}{tailfile};
                    print $f "-!-$title - $link-!-\n";
                }
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

sub irc_tail_input
{
    my $self = $_[OBJECT];
    if ($_[ARG1] =~ /-!-(.*)-!-/) {
        $self->publish_update ($1);
    }
}

sub publish_update
{
    my $self = shift;
    my $update = shift;
    $self->{irc}->yield(privmsg =>
        $_ =>
          POE::Component::IRC::Common::BOLD
        ."Update: "
        . POE::Component::IRC::Common::NORMAL
        .$update)
    for (@{$self->{config}{channels}});
}

sub irc_public
{
    $_[KERNEL]->yield (process_chat => (@_[ARG0..ARG3], 0));
}

# DCC
sub irc_dcc_start
{
    push @{$_[OBJECT]->{dcc}}, $_[ARG0];
}

sub irc_dcc_done
{
    @{$_[OBJECT]->{dcc}} = grep { $_ eq $_[ARG0] ? 0 : 1 } @{$_[OBJECT]->{dcc}};
}

sub irc_dcc_error
{
    @{$_[OBJECT]->{dcc}} = grep { $_ eq $_[ARG0] ? 0 : 1 } @{$_[OBJECT]->{dcc}};
}

sub irc_dcc_chat
{
    my $self = $_[OBJECT];
    my $text = $_[ARG3];
    if ($text =~ /^>(.*)$/)
    {
        $self->{sbuf} = [ split (/\s+/, $1) ];
    }
    elsif ($text =~ /^-(.*)$/)
    {
        if (not defined $self->{sbuf})
        {
            return;
        }
        $self->{irc}->yield(privmsg => $self->{sbuf} => $1);
    }
    elsif ($text =~ /^\*(.*)$/)
    {
        if (not defined $self->{sbuf})
        {
            return;
        }
        $self->{irc}->yield(ctcp => $self->{sbuf} => "ACTION $1");
    }
    elsif ($text =~ /^!(.*)$/)
    {
        if (not defined $self->{sbuf})
        {
            return;
        }
        $self->{irc}->yield(notice => $self->{sbuf} => $1);
    }
    elsif ($text =~ m:^/(.*)$:)
    {
        # Be careful with this
        $self->{irc}->yield(quote => $1);
    }
}
# DCC end

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
