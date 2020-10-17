#!/usr/bin/perl
use strict 'vars';
use warnings;
use Data::Dumper::Perltidy;

for my $arg (@ARGV) {
my $id = pack('L', $arg);
for my $replay (<*/*.replay>) {
	my $shit = `dd if=$replay bs=128 count=1 status=none`;
	if (substr($shit, 0, 1) == 2) {
		$shit =~ /($arg)/s;
		print "$replay\n" if $1;
	}
	else {
		print "$replay\n" if index($shit, $id) > 0;
	}
}
}

__END__

2:{SHAVITREPLAYFORMAT}{FINAL}
H��8C[U:1:122588796]���D���E����V$B�p}����D���E���:�!B��*R�D���E� at finder.pl line 11.
$VAR1 = [];
4:{SHAVITREPLAYFORMAT}{FINAL}
bhop_antiquity_final-A�B|�N�2D�"���OÚ�aB	m��e�D�b���O�
-`B���� at finder.pl line 11.
