
# META OPERATOR cat

## IMPLEMENTATION
	
	  my ($args, $left, $right) = @_;
	  my ($f) = @$args;
	  my $i = -1;
	  ++$i while $i+1 < @$right && $$right[$i+1][0] eq 'cat';
	  ($left, [cat_multi_op($f, $i > -1 ? map $$_[1], @$right[0..$i] : ()),
	           @$right[$i+1..$#{$right}]]);

# META OPERATOR file_data_closure

## IMPLEMENTATION
	
	  my ($name, $f) = @{$_[0]};
	  my $c    = "file-closure://$name";
	  my $file = resource_write $c;
	  my $fh   = sni @$f;
	  sforward $fh, $file;
	  close $file;
	  close $fh;
	  $fh->await;
	  nuke_on_exit $c;
	  add_quoted_resource $c;
	  ();

# META OPERATOR inline_checkpoint

## IMPLEMENTATION
	
	  my ($args, $left, $right) = @_;
	  my ($file) = @$args;
	  ([], [checkpoint_op($file, $left), @$right]);

# META OPERATOR memory_data_closure

## IMPLEMENTATION
	
	  my ($name, $f) = @{$_[0]};
	  my $data;
	  my $fh = sni @$f;
	  1 while saferead $fh, $data, 8192, length $data;
	  close $fh;
	  $fh->await;
	  add_closure_key $name, $data;
	  ();

# META OPERATOR stderr_monitor_transform

## IMPLEMENTATION
	
	  my ($args, $left) = @_;
	  my ($interval) = @$args;
	  [map {;$$left[$_], stderr_monitor_op($_, json_encode $$left[$_], $interval)}
	        0..$#{$left}];
