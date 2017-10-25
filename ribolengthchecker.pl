#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);

require "epn-options.pm";
require "ribo.pm";

my $usage = "perl ribolengthchecker.pl <fasta file> <output file name root>";
if(scalar(@ARGV) != 2) { 
  die $usage;
}

my ($fasta_file, $out_root) = (@ARGV);

my $nbound = 10;

#########################################################
# Command line and option processing using epn-options.pm
#
# opt_HH: 2D hash:
#         1D key: option name (e.g. "-h")
#         2D key: string denoting type of information 
#                 (one of "type", "default", "group", "requires", "incompatible", "preamble", "help")
#         value:  string explaining 2D key:
#                 "type":         "boolean", "string", "integer" or "real"
#                 "default":      default value for option
#                 "group":        integer denoting group number this option belongs to
#                 "requires":     string of 0 or more other options this option requires to work, each separated by a ','
#                 "incompatible": string of 0 or more other options this option is incompatible with, each separated by a ','
#                 "preamble":     string describing option for preamble section (beginning of output from script)
#                 "help":         string describing option for help section (printed if -h used)
#                 "setby":        '1' if option set by user, else 'undef'
#                 "value":        value for option, can be undef if default is undef
#
# opt_order_A: array of options in the order they should be processed
# 
# opt_group_desc_H: key: group number (integer), value: description of group for help output
my %opt_HH = ();      
my @opt_order_A = (); 
my %opt_group_desc_H = ();

# Add all options to %opt_HH and @opt_order_A.
# This section needs to be kept in sync (manually) with the &GetOptions call below
$opt_group_desc_H{"1"} = "basic options";
#     option            type       default               group   requires incompat    preamble-output                                   help-output    
opt_Add("-h",           "boolean", 0,                        0,    undef, undef,      undef,                                            "display this help",                                  \%opt_HH, \@opt_order_A);
opt_Add("-b",           "boolean", 10,                       1,    undef, undef,      "number of positions to look for indels",         "number of positions to look for indels at the 5' and 3' boundaries",  \%opt_HH, \@opt_order_A);
opt_Add("-v",           "boolean", 0,                        1,    undef, undef,      "be verbose",                                     "be verbose; output commands to stdout as they're run", \%opt_HH, \@opt_order_A);
opt_Add("-n",           "integer", 0,                        1,    undef, undef,      "use <n> CPUs",                                   "use <n> CPUs", \%opt_HH, \@opt_order_A);
#opt_Add("-i",           "string",  undef,                    1,    undef, undef,      "use model info file <s> instead of default",     "use model info file <s> instead of default", \%opt_HH, \@opt_order_A);
#opt_Add("-k",           "boolean", 0,                        1,    undef, undef,      "keep all intermediate files",                    "keep all intermediate files that are removed by default", \%opt_HH, \@opt_order_A);

# This section needs to be kept in sync (manually) with the opt_Add() section above
my %GetOptions_H = ();
my $usage    = "Usage: ribocheck_length.pl [-options] <fasta file to annotate> <output file name root>\n";
$usage      .= "\n";
my $synopsis = "ribocheck_length.pl :: classify lengths of ribosomal RNA sequences";
my $options_okay = 
    &GetOptions('h'            => \$GetOptions_H{"-h"}, 
                'f'            => \$GetOptions_H{"-f"},
                'v'            => \$GetOptions_H{"-v"});
#                'i=s'          => \$GetOptions_H{"-i"},
#                'k'            => \$GetOptions_H{"-k"},

my $total_seconds     = -1 * ribo_SecondsSinceEpoch(); # by multiplying by -1, we can just add another ribo_SecondsSinceEpoch call at end to get total time
my $executable        = $0;
my $date              = scalar localtime();
my $version           = "0.01";
my $model_version_str = "0p01"; # models are unchanged since version 0.02
my $releasedate       = "Oct 2017";
my $package_name      = "ribotyper";

# make *STDOUT file handle 'hot' so it automatically flushes whenever we print to it
select *STDOUT;
$| = 1;

# print help and exit if necessary
if((! $options_okay) || ($GetOptions_H{"-h"})) { 
  ribo_OutputBanner(*STDOUT, $package_name, $version, $releasedate, $synopsis, $date);
  opt_OutputHelp(*STDOUT, $usage, \%opt_HH, \@opt_order_A, \%opt_group_desc_H);
  if(! $options_okay) { die "ERROR, unrecognized option;"; }
  else                { exit 0; } # -h, exit with 0 status
}

# check that number of command line args is correct
if(scalar(@ARGV) != 2) {   
  print "Incorrect number of command line arguments.\n";
  print $usage;
  print "\nTo see more help on available options, do ribotyper.pl -h\n\n";
  exit(1);
}
my ($seq_file, $out_root) = (@ARGV);

# set options in opt_HH
opt_SetFromUserHash(\%GetOptions_H, \%opt_HH);

# validate options (check for conflicts)
opt_ValidateSet(\%opt_HH, \@opt_order_A);

###################################################################
# Preliminary checks:
# 1. RIBODIR, INFERNALDIR, and ESLDIR environment variables must be defined
# 2. RIBODIR/ribotyper.pl must exist and be executable
# 3. INFERNALDIR/cmalign must exist and be executable
# 4. ESLDIR/esl-sfetch must exist and be executable
# 5. RIBOCHECKDIR/ribocheck.$model_version_str.modelinfo must exist
#    and in the proper format
# 6. RIBODIR/ must contain CM files listed in ribocheck_length.$model_version_str.modelinfo

# 1. RIBODIR, INFERNALDIR and ESLDIR environment variables must be defined
my $env_ribotyper_dir = verify_env_variable_is_valid_dir("RIBODIR");
my $env_infernal_dir  = verify_env_variable_is_valid_dir("INFERNALDIR");
my $env_easel_dir     = verify_env_variable_is_valid_dir("ESLDIR");

# 2. RIBODIR/ribotyper.pl must exist and be executable
# 3. INFERNALDIR/cmalign must exist and be executable
# 4. ESLDIR/esl-sfetch must exist and be executable
my %execs_H = (); # key is name of program, value is path to the executable
$execs_H{"ribotyper"}  = $env_ribotyper_dir . "/ribotyper.pl";
$execs_H{"cmalign"}    = $env_infernal_dir . "/cmalign";
$execs_H{"esl-sfetch"} = $env_easel_dir    . "/esl-sfetch";
ribo_ValidateExecutableash(\%execs_H);

# 5. RIBODIR/ribocheck_length.$model_version_str.modelinfo must exist
my $model_version_str = "0p01";
my $ribocheck_modelinfo_file = $env_ribocheck_dir . "/ribochecklength." . $model_version_str . ".modelinfo";
if(! (-e $ribocheck_modelinfo_file)) { 
  die "\nERROR, the ribochecklength modelinfo file $ribocheck_modelinfo_file does not exist.\n";
}
# parse the modelinfo file, this tells us where the CM files are
my @family_order_A     = (); # family names, in order
my %family_modelname_H = (); # key is family name (e.g. "SSU.Archaea") from @family_order_A, value is CM file for that family
my %family_modellen_H  = (); # key is family name (e.g. "SSU.Archaea") from @family_order_A, value is consensus length for that family
my %family_rtkey_HA    = (); # key is family name (e.g. "SSU.Archaea") from @family_order_A, value is array of ribotyper keys 
                             # to align for this family (e.g. ("SSU_rRNA_bacteria", "SSU_rRNA_cyanobacteria"))
parse_modelinfo_file($ribocheck_modelinfo_file, $env_ribocheck_dir, \@family_order_A, \%family_modelname_H, \%family_modellen_H, \%family_rtkey_HA);

# 6. RIBOCHECKDIR/ must contain CM files listed in ribocheck.$model_version_str.modelinfo
my $family;
foreach $family (@family_order_A) { 
  if(! -s $family_modelname_H{$family}) { 
    die "Model file $family_modelname_H{$family} specified in $ribocheck_modelinfo_file does not exist or is empty";
  }
}

# index the fasta file, we'll need the index to fetch with esl-sfetch later
my $ssi_file = $fasta_file . ".ssi";
# remove it if it already exists
if(-e $ssi_file) { 
  unlink $ssi_file; 
}
run_command($execs_H{"esl-sfetch"} . " --index $fasta_file > /dev/null", 0);
if(! -s $ssi_file) { 
  die "ERROR, tried to create $ssi_file, but failed"; 
} 

####################################################
# Stage 1: Run ribotyper
####################################################
my $ribotyper_outdir     = $out_root . "-rt";
my $ribotyper_outfile    = $out_root . "ribotyper.out";
my $ribotyper_short_file = $ribotyper_outdir . "/" . $ribotyper_outdir . ".ribotyper.short.out";

# run ribotyper
#run_command($execs_H{"ribotyper"} . " -f --keep $fasta_file $ribotyper_outdir > $ribotyper_outfile", 1);

####################################################
# Stage 2: Run cmalign
####################################################
# for each family to align, run cmalign:
my $nfiles = 0;               # number of fasta files that exist for this sequence directory
my $rtkey_fasta_file = undef; # a ribotyper key fasta file
my $rtkey;                    # a single ribotyper key
my $cat_cmd;                  # a cat command used to pipe the fasta files into cmalign
my $cmalign_stk_file;         # cmalign output alignment
my $cmalign_out_file;         # cmalign output 
my %family_length_class_HHA;  # key 1D is family, key 2D is length class (e.g. 'partial'), value is an array of sequences that 
                              # for this family that belong to this length class
my %out_tbl_HH = ();          # hash of hashes with information for output file
                              # key 1 is sequence name, key 2 is a column name, e.g. pred_cmfrom

foreach $family (@family_order_A) { 
  $nfiles = 0;
  %{$family_length_class_HHA{$family}} = ();
  foreach $rtkey (@{$family_rtkey_HA{$family}}) { 
    $rtkey_fasta_file = $ribotyper_outdir . "/" . $ribotyper_outdir . ".ribotyper." . $rtkey . ".fa";
    if(-s $rtkey_fasta_file) { 
      $nfiles++;
      if($nfiles == 1) { 
        $cat_cmd = "cat ";
      }
      $cat_cmd .= $rtkey_fasta_file . " ";
    }
  }
  if($nfiles > 0) { 
    $cmalign_stk_file = $out_root . ".ribocheck." . $family . ".cmalign.stk";
    $cmalign_out_file = $out_root . ".ribocheck." . $family . ".cmalign.out";
#    run_command("$cat_cmd | " . $execs_H{"cmalign"} . " --outformat pfam --cpu 0 -o $cmalign_stk_file $family_modelname_H{$family} - > $cmalign_out_file", 1);
    # parse cmalign file
    parse_cmalign_file($cmalign_out_file, \%out_tbl_HH);
    # parse alignment file
    parse_stk_file($cmalign_stk_file, $family_modellen_H{$family}, $nbound, \%out_tbl_HH, \%{$family_length_class_HHA{$family}});
  }
}

# realign each length set with cmalign
my $length_class_list_file = undef; # file name for list file for this length class and family
foreach $family (@family_order_A) { 
  foreach my $length_class ("partial", "full-exact", "full-extra", "full-ambig") { 
    if(scalar(@{$family_length_class_HHA{$family}{$length_class}}) > 0) { 
      $length_class_list_file = $out_root . "." . $family . "." . $length_class . ".list";
      $cmalign_stk_file       = $out_root . "." . $family . "." . $length_class . ".stk";
      open(OUT, ">", $length_class_list_file) || die "ERROR, unable to open $length_class_list_file for writing";
      foreach my $seqname (@{$family_length_class_HHA{$family}{$length_class}}) { 
        print OUT $seqname . "\n";
      }
      close(OUT);
      run_command("esl-sfetch -f $fasta_file $length_class_list_file | " . $execs_H{"cmalign"} . " --outformat pfam --cpu 0 -o $cmalign_stk_file $family_modelname_H{$family} - > /dev/null", 1);
    }
  }
}

##############################
# Create output file and exit.
##############################
my $output_file = $out_root . ".ribocheck_length.out";
output_tabular_file($output_file, $ribotyper_short_file, $nbound, \%out_tbl_HH);

#################################################################
# SUBROUTINES
#################################################################

#################################################################
# Subroutine : verify_env_variable_is_valid_dir()
# Incept:      EPN, Wed Oct 25 10:09:28 2017
#
# Purpose:     Verify that the environment variable $envvar exists 
#              and that it is a valid directory. Return directory path.
#              
# Arguments: 
#   $envvar:  environment variable
#
# Returns:    directory path $ENV{'$envvar'}
#
################################################################# 
sub verify_env_variable_is_valid_dir
{
  my ($envvar) = @_;
    
  if(! exists($ENV{"$envvar"})) { 
    die "ERROR, the environment variable $envvar is not set";
  }
  my $envdir = $ENV{"$envvar"};
  if(! (-d $envdir)) { 
    die "ERROR, the directory specified by your environment variable $envvar does not exist.\n"; 
  }    

  return $envdir
}

#################################################################
# Subroutine : parse_modelinfo_file()
# Incept:      EPN, Fri Oct 20 14:17:53 2017
#
# Purpose:     Parse the modelinfo file, and fill information in
#              @{$family_order_AR}, %{$family_modelname_HR}, %{$family_rtkey_HAR}.
# 
#              
# Arguments: 
#   $modelinfo_file:       file to parse
#   $env_ribocheck_dir:    directory in which CM files should be found
#   $family_order_AR:      reference to array of family names, in order read from file, FILLED HERE
#   $family_modelname_HR:  reference to hash, key is family name, value is path to model, FILLED HERE 
#   $family_modellen_HR:   reference to hash, key is family name, value is consensus model length, FILLED HERE
#   $family_rtkey_HAR:     reference to hash of arrays, key is family name, value is array of 
#                          ribotyper keys that belong to this family
#
# Returns:     void; 
#
################################################################# 
sub parse_modelinfo_file { 
  my $nargs_expected = 6;
  my $sub_name = "parse_modelinfo_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($modelinfo_file, $env_ribocheck_dir, $family_order_AR, $family_modelname_HR, $family_modellen_HR, $family_rtkey_HAR) = @_;

  open(IN, $modelinfo_file) || die "ERROR unable to open model info file $modelinfo_file for reading";

  while(my $line = <IN>) { 
    ## each line has information on 1 family and has at least 4 tokens: 
    ## token 1: Name for output files for this family
    ## token 2: CM file name for this family
    ## token 3: integer, consensus length for the CM for this family
    ## tokens 4 to N: name of ribotyper files with sequences that should be aligned with this model
    #SSU.Archaea RF01959.cm SSU_rRNA_archaea
    #SSU.Bacteria RF00177.cm SSU_rRNA_bacteria SSU_rRNA_cyanobacteria
    chomp $line; 
    if($line !~ /^\#/ && $line =~ m/\w/) { 
      $line =~ s/^\s+//; # remove leading whitespace
      $line =~ s/\s+$//; # remove trailing whitespace
      my @el_A = split(/\s+/, $line);
      if(scalar(@el_A) < 4) { 
        die "ERROR in $sub_name, less than 4 tokens found on line $line of $modelinfo_file";  
      }
      my ($family, $modelname, $modellen, @rtkey_A) = @el_A;
      push(@{$family_order_AR}, $family);
      $family_modelname_HR->{$family} = $env_ribocheck_dir . "/" . $modelname;
      $family_modellen_HR->{$family}  = $modellen;
      @{$family_rtkey_HAR->{$family}} = @rtkey_A;
    }
  }
  close(IN);
  return;
}

#################################################################
# Subroutine:  run_command()
# Incept:      EPN, Mon Dec 19 10:43:45 2016 [ribotyper-v1/ribo.pm]
#
# Purpose:     Runs a command using system() and exits in error 
#              if the command fails. If $be_verbose, outputs
#              the command to stdout. If $FH_HR->{"cmd"} is
#              defined, outputs command to that file handle.
#
# Arguments:
#   $cmd:         command to run, with a "system" command;
#   $be_verbose:  '1' to output command to stdout before we run it, '0' not to
#
# Returns:    amount of time the command took, in seconds
#
# Dies:       if $cmd fails
#################################################################
sub run_command {
  my $sub_name = "run_command()";
  my $nargs_expected = 2;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($cmd, $be_verbose) = @_;
  
  if($be_verbose) { 
    print ("# Running cmd: $cmd\n"); 
  }

  my ($seconds, $microseconds) = gettimeofday();
  my $start_time = ($seconds + ($microseconds / 1000000.));

  system($cmd);

  ($seconds, $microseconds) = gettimeofday();
  my $stop_time = ($seconds + ($microseconds / 1000000.));

  if($? != 0) { 
    die "ERROR in $sub_name, the following command failed:\n$cmd\n";
  }

  return ($stop_time - $start_time);
}

#################################################################
# Subroutine : remove_dir_path()
# Incept:      EPN, Mon Nov  9 14:30:59 2009 [ssu-align] 
#
# Purpose:     Given a full path of a file remove the directory path.
#              For example: "foodir/foodir2/foo.stk" becomes "foo.stk".
#
# Arguments: 
#   $fullpath: name of original file
# 
# Returns:     The string $fullpath with dir path removed.
#
################################################################# 
sub remove_dir_path {
  my $sub_name = "remove_dir_path()";
  my $nargs_expected = 1;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my $fullpath = $_[0];

  $fullpath =~ s/^.+\///;

  return $fullpath;
}


#################################################################
# Subroutine : output_tabular_file()
# Incept:      EPN, Mon Oct 23 16:20:55 2017
#
# Purpose:     Output to the tabular output file, by appending 
#              a few columns to the ribotyper 'short' output file.
#
# Arguments: 
#   $out_tbl_file:     file to output to
#   $ribo_short_file:  ribotyper short output file
#   $nbound:           number of positions we checked for indels
#                      at beginning/end of alignment
#   $out_tbl_HHR:      ref to array of lines to output
# Returns:     void
#
################################################################# 
sub output_tabular_file { 
  my $sub_name = "output_tabular_file()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($out_tbl_file, $ribo_short_file, $nbound, $out_tbl_HHR) = @_; 

  # open the ribotyper short output file for input and output file for output
  open(IN, $ribo_short_file)    || die "ERROR unable to open $ribo_short_file for reading";
  open(OUT, ">", $out_tbl_file) || die "ERROR unable to open $out_tbl_file for writing";

  my $line_ctr = 0;
  while(my $line = <IN>) { 
    $line_ctr++;
    if($line !~ m/^\#/ || $line_ctr < 3) { # the $line_ctr < 3 gets the first two header lines
      ##idx  target                          classification         strnd   p/f  unexpected_features
      ##---  ------------------------------  ---------------------  -----  ----  -------------------
      
      #1     gi|631252343|ref|NR_113541.1|   SSU.Archaea            plus   PASS  -
      #2     gi|631253163|ref|NR_114361.1|   SSU.Archaea            plus   PASS  -
      #3     gi|1212229201|ref|NR_148269.1|  SSU.Archaea            plus   PASS  -
      if($line =~ /^(\#?\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(\S+)\n/) { 
        my ($prefix, $suffix) = ($1, $2);
        my $seqname = $prefix;
        $seqname =~ s/^\d+\s+//;
        $seqname =~ s/\s+.*//;
        if($line_ctr == 1) { 
          printf OUT ("$prefix  %6s  %6s  %12s  $suffix\n", "mstart", "mstop", "length_class");
        }
        elsif($line_ctr == 2) { 
          printf OUT ("$prefix  %6s  %6s  %12s  $suffix\n", "------", "------", "------------");
        }
        elsif(exists $out_tbl_HHR->{$seqname}) { 
          printf OUT ("$prefix  %6d  %6d  %12s  $suffix\n", $out_tbl_HHR->{$seqname}{"pred_cmfrom"}, $out_tbl_HHR->{$seqname}{"pred_cmto"}, $out_tbl_HHR->{$seqname}{"length_class"}); 
        }
        else { # this sequence must not have been aligned
          printf OUT ("$prefix  %6s  %6s  %12s  $suffix\n", "-", "-", "-");
        }
      }
      else { 
        die "ERROR unable to parse non-comment line of $ribo_short_file:\n$line\n";
      }
    }
    else { # comment line
      if($line =~ m/Column 6 \[unexpected\_features\]/) { 
        # special case, add the descriptions of the 3 columns that we added:
        printf OUT ("%-33s %s\n", "# Column 6 [mstart]:",       "model start position");
        printf OUT ("%-33s %s\n", "# Column 7 [mstop]:",        "model stop position");
        printf OUT ("%-33s %s\n", "# Column 8 [length_class]:", "classification of length, one of:");
        printf OUT ("%-33s %s\n", "#",                          "'full-exact': spans full model and no 5' or 3' inserts");
        printf OUT ("%-33s %s\n", "#",                          "              and no indels in first or final $nbound model positions");
        printf OUT ("%-33s %s\n", "#",                          "'full-extra': spans full model but has 5' and/or 3' inserts");
        printf OUT ("%-33s %s\n", "#",                          "'full-ambig': spans full model and no 5' or 3' inserts");
        printf OUT ("%-33s %s\n", "#",                          "              but has indel(s) in first and/or final $nbound model positions");
        printf OUT ("%-33s %s\n", "#",                          "'partial:'    does not span full model");
        printf OUT ("%-33s %s\n", "# Column 9 [unexpected_features]:", "unexpected/unusual features of sequence (see below)")
      }
      else { # regurgitate other comment lines
        print OUT $line;
      }
    }
  }
  close(IN);
  return;
}

#################################################################
# subroutine : debug_print_hash
# sub class  : general
# 
# EPN 03.08.05
# 
# purpose : Print to standard output the keys and values of a 
#           given hash
#
# args : (1) $hash_ref 
#            reference to hash to print
#        (2) $hash_name
#            name of hash to print
################################################################# 

sub debug_print_hash
{
  my ($hash_ref, $hash_name) = @_;
    
  print("IN DEBUG PRINT HASH\n");
  print("printing hash : $hash_name\n");
  my $i = 1;
  foreach my $header (sort keys (%{$hash_ref}))
  {
    print("$i KEY    : $header\n");
    print("$i VALUE : $hash_ref->{$header}\n");
    $i++;
  }
  print("finished printing hash : $hash_name\n");
  print("LEAVING DEBUG PRINT HASH\n");
}


#################################################################
# Subroutine : parse_cmalign_file()
# Incept:      EPN, Fri Aug 18 11:32:24 2017
#
# Purpose:     Parse a cmalign file, storing only the start and end 
#              positions in the model in %{$out_tbl_HHR}.
#              
# Arguments: 
#   $cmalign_file: file to parse
#   $out_tbl_HHR:  ref to array of hashes, with output info
#
# Returns:     void; 
#
################################################################# 
sub parse_cmalign_file { 
  my $nargs_expected = 2;
  my $sub_name = "parse_cmalign_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($cmalign_file, $out_tbl_HHR) = @_;

  open(IN, $cmalign_file) || die "ERROR unable to open cmalign file $cmalign_file for reading";

  while(my $line = <IN>) { 
##                                                                           running time (s)                 
##                                                                    -------------------------------          
## idx  seq name   length  cm from    cm to  trunc    bit sc  avg pp  band calc  alignment      total  mem (Mb)
## ---  ---------  ------  -------  -------  -----  --------  ------  ---------  ---------  ---------  --------
#    1  NR_043409    1493        1     1477     no   1501.40   0.987       0.37       0.19       0.56     50.52
#    2  NR_043410    1497        1     1477     no   1541.35   0.989       0.36       0.19       0.55     50.55
#    3  NR_029127    1496        1     1477     no   1568.97   0.987       0.38       0.17       0.55     50.16
    chomp $line; 
    if($line !~ /^\#/) { 
      $line =~ s/^\s+//; # remove leading whitespace
      $line =~ s/\s+$//; # remove trailing whitespace
      my @el_A = split(/\s+/, $line);
      if(scalar(@el_A) != 12) { die "ERROR in $sub_name, unexpected number of tokens on cmalign output file line: $line";  }
      my ($seqname, $cmfrom, $cmto) = ($el_A[1], $el_A[3], $el_A[4]);
      $out_tbl_HHR->{$seqname}{"pred_cmfrom"} = $cmfrom;
      $out_tbl_HHR->{$seqname}{"pred_cmto"}   = $cmto;
    }
  }
  close(IN);
  return;
}

#################################################################
# Subroutine : parse_stk_file()
# Incept:      EPN, Fri Oct 20 15:05:27 2017
#
# Purpose:     Parse a PFAM formatted (one line per seq) alignment
#              and store information in %{$out_tbl_HHR}.
#              
# Arguments: 
#   $stk_file:     file to parse
#   $modellen:     consensus length of the model 
#   $nbound:       number of positions at boundary of model to inspect
#                  when classifying full length sequences as 'exact', 'extra'
#                  or 'ambig'.
#   $out_tbl_HHR:  ref to hash of hashes, with output info, added to here
#   $lenclass_HAR: ref to hash of arrays, key is length class, value is array
#                  of sequences that belong to this class
#
# Returns:     void; 
#
################################################################# 
sub parse_stk_file { 
  my $nargs_expected = 5;
  my $sub_name = "parse_stk_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($stk_file, $modellen, $nbound, $out_tbl_HHR, $lenclass_HAR) = @_;

  # initialize lenclass_HAR for each length class:
  @{$lenclass_HAR->{"partial"}}    = ();
  @{$lenclass_HAR->{"full-exact"}} = ();
  @{$lenclass_HAR->{"full-extra"}} = ();
  @{$lenclass_HAR->{"full-ambig"}} = ();

  # first pass through the file to get the RF line:
  my $line;
  my $rfstr = "";
  open(IN, $stk_file) || die "ERROR unable to open cmalign file $stk_file for reading";
  while($line = <IN>) { 
    if($line =~ m/^#=GC RF\s+(\S+)/) { 
      if($rfstr ne "") { 
        die "ERROR in $sub_name, more than one RF line, alignment is not in Pfam format"; 
      }
      $rfstr = $1;
    }
  }
  close(IN);
  if($rfstr eq "") { 
    die "ERROR in $sub_name, no RF line found, alignment is not in Pfam format"; 
  }

  # make a map of alignment positions to nongap RF positions
  my $rfpos = 0;  # nongap RF position
  my $apos  = 0; # alignment position
  my @rf_A  = split("", $rfstr);
  my $alen  = scalar(@rf_A);
  my @r2a_map_A = (); # [1..rfpos..rflen], r2a_map_A[$rfpos] = $apos, nongap RF position $rfpos maps to alignment position $apos
  my @i_am_rf_A = (); # [1..apos..alen],   i_am_rf_A[$apos]  = 1 if alignment position is a nongap RF position, else 0
  $r2a_map_A[0] = -1; # invalid element
  $i_am_rf_A[0] = -1; # invalid element
  # nongap RF positions go 1..rflen
  # alignment positions go 1..alen
  for($apos = 0; $apos < $alen; $apos++) { 
    if($rf_A[$apos] =~ m/\w/) { # a word character, this is a reference position
      $rfpos++;
      $r2a_map_A[$rfpos] = $apos+1;
      $i_am_rf_A[($apos+1)] = 1;
    }
    else { 
      $i_am_rf_A[($apos+1)] = 0;
    }
  }
  my $apos_first_rfpos = $r2a_map_A[1];
  my $apos_5p_nbound   = $r2a_map_A[$nbound]; 
  my $apos_3p_nbound   = $r2a_map_A[($modellen - $nbound + 1)]; 
  my $apos_final_rfpos = $r2a_map_A[$modellen];
  # $apos_first_rfpos is the alignment position which is the first nongap in the RF string
  # $apos_5p_nbound is the alignment position that is the $nbound'th nongap in the RF string
  # $apos_3p_nbound is the alignment position that is the ($modellen - $nbound + 1)'th nongap in the RF string
  # $apos_final_rfpos is the alignment position that is the final nongap in the RF string

  # second pass through alignment
  open(IN, $stk_file) || die "ERROR unable to open cmalign file $stk_file for reading";
  while($line = <IN>) { 
    if($line !~ m/^#/ && $line =~ m/\w/) { 
      # a sequence line
      if($line =~ /(\S+)\s+(\S+)/) { 
        my ($seqname, $seqstr) = ($1, $2);
        if(! exists $out_tbl_HHR->{$seqname}) { 
          die "ERROR found sequence in alignment $stk_file without an entry in the output table"; 
        }
        if(($out_tbl_HHR->{$seqname}{"pred_cmfrom"} == 1) &&
           ($out_tbl_HHR->{$seqname}{"pred_cmto"}   == $modellen)) { 
          # spans the full model, classify further as:
          # 'exact': has 0 indels in first and final $nbound RF positions 
          # 'extra': has >=1 inserts before first RF position or after final RF position
          # 'ambig': has 0 inserts before first RF position or after final RF position, but
          #          has >= 1 indel in first or final $nbound RF positions
          my @seqstr_A = split("", $seqstr);
          my $i_before_first_rfpos = 0; # number of insertions before RF position 1
          my $i_early              = 0; # number of insertions between RF position 1 and $nbound
          my $d_early              = 0; # number of deletions  between RF position 1 and $nbound
          my $i_after_final_rfpos  = 0; # number of insertions after RF position $modellen
          my $i_late               = 0; # number of insertions between RF position $modellen-$nbound+1 and $modellen
          my $d_late               = 0; # number of insertions between RF position $modellen-$nbound+1 and $modellen
          # count number of insertions before RF position 1
          for($apos = 1; $apos < $apos_first_rfpos; $apos++) { 
            if($seqstr_A[($apos-1)] =~ m/\w/) { 
              $i_before_first_rfpos++;
            }
          }
          # count number of deletions and insertions between RF position 1 and $nbound
          for($apos = $apos_first_rfpos; $apos <= $apos_5p_nbound; $apos++) { 
            if($i_am_rf_A[$apos]) { # nongap RF position
              if($seqstr_A[($apos-1)] !~ m/\w/) { # a gap: a deletion
                $d_early++;
              }
            }
            else { # gap RF position
              if($seqstr_A[($apos-1)] =~ m/\w/) { # nongap: an insertion
                $i_early++;
              }
            }
          }
          # count number of deletions and insertions between RF position ($modellen-$nbound+1) and $modellen
          for($apos = $apos_3p_nbound; $apos <= $apos_final_rfpos; $apos++) { 
            if($i_am_rf_A[$apos]) { # nongap RF position
              if($seqstr_A[($apos-1)] !~ m/\w/) { # a gap: a deletion
                $d_late++;
              }
            }
            else { # gap RF position
              if($seqstr_A[($apos-1)] =~ m/\w/) { # nongap: an insertion
                $i_late++;
              }
            }
          }
          # count number of insertions after RF position $modellen
          for($apos = $apos_final_rfpos+1; $apos <= $alen; $apos++) { 
            if($seqstr_A[($apos-1)] =~ m/\w/) { 
              $i_after_final_rfpos++;
            }
          }
          # classify
          if(($i_before_first_rfpos == 0) && ($d_early == 0) && ($i_early == 0) && 
             ($i_after_final_rfpos  == 0) && ($d_late  == 0) && ($i_late  == 0)) { 
            $out_tbl_HHR->{$seqname}{"length_class"} = "full-exact";
            push(@{$lenclass_HAR->{"full-exact"}}, $seqname);
          }
          elsif(($i_before_first_rfpos != 0) || ($i_after_final_rfpos != 0)) { 
            $out_tbl_HHR->{$seqname}{"length_class"} = "full-extra";
            push(@{$lenclass_HAR->{"full-extra"}}, $seqname);
          }
          else { 
            $out_tbl_HHR->{$seqname}{"length_class"} = "full-ambig";
            push(@{$lenclass_HAR->{"full-ambig"}}, $seqname);
          }
        } # end of if(($out_tbl_HHR->{$seqname}{"pred_cmfrom"} == 1) &&
          # ($out_tbl_HHR->{$seqname}{"pred_cmto"}   == $modellen)) { 
        else { 
          $out_tbl_HHR->{$seqname}{"length_class"} = "partial";
          push(@{$lenclass_HAR->{"partial"}}, $seqname);
        }
      }
    }
  }
  close(IN);
  
  return;
}

#################################################################
# Subroutine : validate_executable_hash()
# Incept:      EPN, Sat Feb 13 06:27:51 2016
#
# Purpose:     Given a reference to a hash in which the 
#              values are paths to executables, validate
#              those files are executable.
#
# Arguments: 
#   $execs_HR: REF to hash, keys are short names to executable
#              e.g. "cmbuild", values are full paths to that
#              executable, e.g. "/usr/local/infernal/1.1.1/bin/cmbuild"
# 
# Returns:     void
#
# Dies:        if one or more executables does not exist#
#
################################################################# 
sub validate_executable_hash { 
  my $nargs_expected = 1;
  my $sub_name = "validate_executable_hash()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($execs_HR) = (@_);

  my $fail_str = undef;
  foreach my $key (sort keys %{$execs_HR}) { 
    if(! -e $execs_HR->{$key}) { 
      $fail_str .= "\t$execs_HR->{$key} does not exist.\n"; 
    }
    elsif(! -x $execs_HR->{$key}) { 
      $fail_str .= "\t$execs_HR->{$key} exists but is not an executable file.\n"; 
    }
  }
  
  if(defined $fail_str) { 
    die "ERROR in $sub_name(),\n$fail_str"; 
  }

  return;
}
