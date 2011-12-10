#!/usr/bin/perl
use strict;
use warnings;

use POE;
use Asidonhopo;

my $pid = fork unless shift;

exit if $pid;

if (Asidonhopo->create)
{
    POE::Kernel->run;
}

