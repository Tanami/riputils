#!/usr/bin/perl
use strict 'vars';
use warnings;
my @maps = glob('maps/*.bsp');
my $output;
for my $map (@maps) {
	$map =~ m!maps/(.+)\.bsp!;
	$output .= "$1\n";
}
open(MAPCYCLE, '>cfg/mapcycle.txt') or die 'ruh roh';
print MAPCYCLE $output;
close(MAPCYCLE);
print "rebuilt mapcycle.txt\n";
