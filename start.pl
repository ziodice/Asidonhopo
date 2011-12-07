#!/usr/bin/perl
use strict;
use warnings;

use POE;
use Asidonhopo;

if (Asidonhopo->create)
{
    POE::Kernel->run;
}

