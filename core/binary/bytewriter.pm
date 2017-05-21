# Byte writer.
# Convenience functions that make it easier to write binary data to standard out.
# This library gets added to the perl prefix, so these functions are available in
# perl mappers.

sub ws($)  {print $_[0]; ()}
sub wp($@) {ws pack $_[0], @_[1..$#_]}
