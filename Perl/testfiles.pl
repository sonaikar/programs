#!/usr/bin/perl

#use strict;
use Getopt::Long;
use Data::Dumper;
use Cwd;

my $pwd = cwd;
print $pwd."\n";

my $path = 'c:';
my %dir_list;

sub read_directory($);
sub list_files($);

list_directory($path);  

foreach my $x (keys %dir_list)
{
  list_files($x);
}

foreach my $x (sort keys %dir_list)
{
 print "\n Directory $x contains $dir_list{$x} files. ";
}

sub list_directory($)
{
   my $dir = shift; 
   if(! $dir)
   {
    $dir = cwd ;
   } 
   
   opendir DD, $dir or die "Cannot open the directory: $!";  
   while($_ = readdir(DD))
    {
      next if  ($_ eq "." or $_ eq "..");
      if ( -d $_ && $_ =~  /^(1\d{3})/)
	 {
	     #print "\n Directory exists $_ in $dir \n";
	     $dir_list{$_} = 1 ; 
	 }
    }      
 close DD;
}

sub list_files($)
{
     my $dir = shift;
     my $count = 0 ;

    opendir DD, $dir or die "Cannot open the directory: $!";  
    while($_ = readdir(DD))
	{
	    next if  ($_ eq "." or $_ eq "..");
	    #print "$_ \n";
	    $\="\t";	
	    print -s _ if -r _ and -f _;
            $count ++;
	}
     $dir_list{$dir}=$count;
     close DD;
 }
 
  

