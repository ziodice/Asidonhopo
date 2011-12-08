#!/usr/bin/perl
use strict;
use warnings;

use POE;
use Asidonhopo;

my $pid = fork;

exit if $pid;

if (Asidonhopo->create)
{
    POE::Kernel->run;
}

