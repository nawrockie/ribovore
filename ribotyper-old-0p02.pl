#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);

require "epn-options.pm";

# make sure the DNAORGDIR environment variable is set
my $ribodir = $ENV{'RIBODIR'};
if(! exists($ENV{'RIBODIR'})) { 
    printf STDERR ("\nERROR, the environment variable RIBODIR is not set, please set it to the directory where you installed the ribotyper scripts and their dependencies.\n"); 
    exit(1); 
}
if(! (-d $ribodir)) { 
    printf STDERR ("\nERROR, the ribotyper directory specified by your environment variable RIBODIR does not exist.\n"); 
    exit(1); 
}    
my $inf_exec_dir      = $ribodir . "/infernal-1.1.2/src/";
my $hmmer_exec_dir    = $ribodir . "/infernal-1.1.2/src/";
my $esl_exec_dir      = $ribodir . "/infernal-1.1.2/easel/miniapps/";
 
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
opt_Add("-f",           "boolean", 0,                        1,    undef, undef,      "forcing directory overwrite",                    "force; if <output directory> exists, overwrite it",  \%opt_HH, \@opt_order_A);
opt_Add("-v",           "boolean", 0,                        1,    undef, undef,      "be verbose",                                     "be verbose; output commands to stdout as they're run", \%opt_HH, \@opt_order_A);
opt_Add("-n",           "integer", 0,                        1,    undef,"--ssualign","use <n> CPUs",                                   "use <n> CPUs", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"2"} = "options for controlling the search algorithm";
#       option               type   default                group  requires incompat                                  preamble-output                  help-output    
opt_Add("--nhmmer",       "boolean", 0,                       2,  undef,   "--cmscan,--ssualign,--hmm,--slow",       "annotate with nhmmer",          "using nhmmer for annotation",    \%opt_HH, \@opt_order_A);
opt_Add("--cmscan",       "boolean", 0,                       2,  undef,   "--nhmmer,--ssualign",                    "annotate with cmsearch",        "using cmscan for annotation",    \%opt_HH, \@opt_order_A);
opt_Add("--ssualign",     "boolean", 0,                       2,  undef,   "--nhmmer,--cmscan,--hmm,--slow",         "annotate with SSU-ALIGN",       "using SSU-ALIGN for annotation", \%opt_HH, \@opt_order_A);
opt_Add("--hmm",          "boolean", 0,                       2,  undef,   "--nhmmer,--ssualign,--slow",             "run in slower HMM mode",        "run in slower HMM mode",         \%opt_HH, \@opt_order_A);
opt_Add("--slow",         "boolean", 0,                       2,  undef,   "--nhmmer,--ssualign,--hmm",              "run in slow CM mode",           "run in slow CM mode, maximize boundary accuracy", \%opt_HH, \@opt_order_A);
opt_Add("--mid",          "boolean", 0,                       2,"--slow",  "--max",                                  "use --mid instead of --rfam",   "with --slow use cmsearch --mid option instead of --rfam", \%opt_HH, \@opt_order_A);
opt_Add("--max",          "boolean", 0,                       2,"--slow",  "--mid",                                  "use --max instead of --rfam",   "with --slow use cmsearch --max option instead of --rfam", \%opt_HH, \@opt_order_A);
opt_Add("--smxsize",         "real", undef,                   2,"--max",   undef,                                    "with --max, use --smxsize <x>", "with --max also use cmsearch --smxsize <x>", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"3"} = "options related to bit score REPORTING thresholds";
#     option                 type   default                group   requires incompat    preamble-output                                 help-output    
opt_Add("--minsc",         "real",   "20.",                   3,  undef,   undef,      "set minimum bit score cutoff for hits to <x>",  "set minimum bit score cutoff for hits to include to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--nominsc",    "boolean",   0,                       3,  undef,   undef,      "turn off minimum bit score cutoff for hits",    "turn off minimum bit score cutoff for hits", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"4"} = "options for controlling which sequences PASS/FAIL (turning on optional failure criteria)";
#     option                 type   default                group   requires incompat    preamble-output                                          help-output    
opt_Add("--minusfail",  "boolean",   0,                        4,  undef,   undef,      "hits on negative (minus) strand FAIL",                 "hits on negative (minus) strand defined as FAILures", \%opt_HH, \@opt_order_A);
opt_Add("--scfail",     "boolean",   0,                        4,  undef,   undef,      "seqs that fall below low score threshold FAIL",        "seqs that fall below low score threshold FAIL", \%opt_HH, \@opt_order_A);
opt_Add("--difffail",   "boolean",   0,                        4,  undef,   undef,      "seqs that fall below low score diff threshold FAIL",   "seqs that fall below low score difference threshold FAIL", \%opt_HH, \@opt_order_A);
opt_Add("--covfail",    "boolean",   0,                        4,  undef,   undef,      "seqs that fall below low coverage threshold FAIL",     "seqs that fall below low coverage threshold FAIL", \%opt_HH, \@opt_order_A);
opt_Add("--multfail",   "boolean",   0,                        4,  undef,   undef,      "seqs that have more than one hit to best model FAIL",  "seqs that have more than one hit to best model FAIL", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"5"} = "options for controlling thresholds for failure/warning criteria";
#     option                 type    default               group   requires incompat    preamble-output                                            help-output    
opt_Add("--lowppossc",     "real",   "0.5",                    5,  undef,   undef,      "set minimum bit per position threshold to <x>",           "set minimum bit per position threshold for reporting suspiciously low scores to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--tcov",          "real",   "0.88",                   5,  undef,   undef,      "set low total coverage threshold to <x>",                 "set low total coverage threshold to <x> fraction of target sequence", \%opt_HH, \@opt_order_A);
opt_Add("--lowpdiff",      "real",   "0.10",                   5,  undef,   "--absdiff","set low per-posn score difference threshold to <x>",      "set 'low'      per-posn score difference threshold to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--vlowpdiff",     "real",   "0.04",                   5,  undef,   "--absdiff","set very low per-posn score difference threshold to <x>", "set 'very low' per-posn score difference threshold to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--absdiff",    "boolean",   0,                        5,  undef,   undef,      "use total score diff threshold, not per-posn",            "use total score difference thresholds instead of per-posn", \%opt_HH, \@opt_order_A);
opt_Add("--lowadiff",      "real",   "100.",                   5,"--absdiff",undef,     "set 'low' total sc diff threshold to <x>",                "set 'low'      total score difference threshold to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--vlowadiff",     "real",   "40.",                    5,"--absdiff",undef,     "set 'very low' total sc diff threshold to <x>",           "set 'very low' total score difference threshold to <x> bits", \%opt_HH, \@opt_order_A);
opt_Add("--maxoverlap", "integer",   "10",                     5,  undef,   undef,      "set maximum allowed model position overlap to <n>",       "set maximum allowed number of model positions to overlap before failue to <n>", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"6"} = "optional input files";
#       option               type   default                group  requires incompat  preamble-output                     help-output    
opt_Add("--inaccept",     "string",  undef,                   6,  undef,   undef,    "read acceptable models from <s>",  "read acceptable domains/models from file <s>", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"7"} = "advanced options";
#       option               type   default                group  requires incompat             preamble-output                               help-output    
opt_Add("--evalues",      "boolean", 0,                       7,  undef,   "--ssualign",        "rank by E-values, not bit scores",           "rank hits by E-values, not bit scores", \%opt_HH, \@opt_order_A);
opt_Add("--skipsearch",   "boolean", 0,                       7,  undef,   "-f",                "skip search stage",                          "skip search stage, use results from earlier run", \%opt_HH, \@opt_order_A);
opt_Add("--noali",        "boolean", 0,                       7,  undef,   "--skipsearch",      "no alignments in output",                    "no alignments in output with --slow, --hmm, or --nhmmer", \%opt_HH, \@opt_order_A);
opt_Add("--samedomain",   "boolean", 0,                       7,  undef,   undef,               "top two hits can be same domain",            "top two hits can be to models in the same domain", \%opt_HH, \@opt_order_A);
opt_Add("--keep",         "boolean", 0,                       7,  undef,   undef,               "keep all intermediate files",                "keep all intermediate files that are removed by default", \%opt_HH, \@opt_order_A);

# This section needs to be kept in sync (manually) with the opt_Add() section above
my %GetOptions_H = ();
my $usage    = "Usage: ribotyper.pl [-options] <fasta file to annotate> <model file> <fam/domain info file> <output directory>\n";
$usage      .= "\n";
my $synopsis = "ribotyper.pl :: detect and classify ribosomal RNA sequences";
my $options_okay = 
    &GetOptions('h'            => \$GetOptions_H{"-h"}, 
                'f'            => \$GetOptions_H{"-f"},
                'v'            => \$GetOptions_H{"-v"},
                'n=s'          => \$GetOptions_H{"-n"},
# algorithm options
                'nhmmer'       => \$GetOptions_H{"--nhmmer"},
                'cmscan'       => \$GetOptions_H{"--cmscan"},
                'ssualign'     => \$GetOptions_H{"--ssualign"},
                'hmm'          => \$GetOptions_H{"--hmm"},
                'slow'         => \$GetOptions_H{"--slow"},
                'mid'          => \$GetOptions_H{"--mid"},
                'max'          => \$GetOptions_H{"--max"},
                'smxsize=s'    => \$GetOptions_H{"--smxsize"},
# options controlling minimum bit score cutoff 
                'minsc=s'     => \$GetOptions_H{"--minsc"},
                'nominsc'     => \$GetOptions_H{"--nominsc"},
                'lowppossc'   => \$GetOptions_H{"--lowppossc"},
# options controlling which sequences pass/fail
                'minusfail'    => \$GetOptions_H{"--minusfail"},
                'scfail'       => \$GetOptions_H{"--scfail"},
                'difffail'     => \$GetOptions_H{"--difffail"},
                'covfail'      => \$GetOptions_H{"--covfail"},
                'multfail'     => \$GetOptions_H{"--multfail"},
# options controlling thresholds for warnings and failures
                'lowppossc'    => \$GetOptions_H{"--lowppossc"},
                'tcov=s'       => \$GetOptions_H{"--tcov"}, 
                'lowpdiff=s'   => \$GetOptions_H{"--lowpdiff"},
                'vlowpdiff=s'  => \$GetOptions_H{"--vlowpdiff"},
                'absdiff'      => \$GetOptions_H{"--absdiff"},
                'lowadiff=s'   => \$GetOptions_H{"--lowadiff"},
                'vlowadiff=s'  => \$GetOptions_H{"--vlowadiff"},
                'maxoverlap'   => \$GetOptions_H{"--maxoverlap"},
# optional input files
                'inaccept=s'   => \$GetOptions_H{"--inaccept"},
# advanced options
                'evalues'      => \$GetOptions_H{"--evalues"},
                'skipsearch'   => \$GetOptions_H{"--skipsearch"},
                'noali'        => \$GetOptions_H{"--noali"},
                'keep'         => \$GetOptions_H{"--keep"},
                'samedomain'   => \$GetOptions_H{"--samedomain"});

my $total_seconds = -1 * seconds_since_epoch(); # by multiplying by -1, we can just add another seconds_since_epoch call at end to get total time
my $executable    = $0;
my $date          = scalar localtime();
my $version       = "0.02";
my $releasedate   = "May 2017";

# make *STDOUT file handle 'hot' so it automatically flushes whenever we print to it
select *STDOUT;
$| = 1;

# print help and exit if necessary
if((! $options_okay) || ($GetOptions_H{"-h"})) { 
  output_banner(*STDOUT, $version, $releasedate, $synopsis, $date);
  opt_OutputHelp(*STDOUT, $usage, \%opt_HH, \@opt_order_A, \%opt_group_desc_H);
  if(! $options_okay) { die "ERROR, unrecognized option;"; }
  else                { exit 0; } # -h, exit with 0 status
}

# check that number of command line args is correct
if(scalar(@ARGV) != 4) {   
  print "Incorrect number of command line arguments.\n";
  print $usage;
  print "\nTo see more help on available options, do dnaorg_annotate.pl -h\n\n";
  exit(1);
}
my ($seq_file, $model_file, $modelinfo_file, $dir_out) = (@ARGV);

# set options in opt_HH
opt_SetFromUserHash(\%GetOptions_H, \%opt_HH);

# validate options (check for conflicts)
opt_ValidateSet(\%opt_HH, \@opt_order_A);

# do some final option checks that are currently too sophisticated for epn-options
if(opt_Get("--evalues", \%opt_HH)) { 
  if((! opt_Get("--nhmmer", \%opt_HH)) && 
     (! opt_Get("--hmm", \%opt_HH)) && 
     (! opt_Get("--slow", \%opt_HH))) { 
    die "ERROR, --evalues requires one of --nhmmer, --hmm or --slow";
  }
}
if(opt_Get("--noali", \%opt_HH)) { 
  if((! opt_Get("--nhmmer", \%opt_HH)) && 
     (! opt_Get("--hmm", \%opt_HH)) && 
     (! opt_Get("--slow", \%opt_HH))) { 
    die "ERROR, --noali requires one of --nhmmer, --hmm or --slow";
  }
}
if(opt_IsUsed("--lowpdiff",\%opt_HH) || opt_IsUsed("--vlowpdiff",\%opt_HH)) { 
  if(opt_Get("--lowpdiff",\%opt_HH) < opt_Get("--vlowpdiff",\%opt_HH)) { 
    die sprintf("ERROR, with --lowpdiff <x> and --vlowpdiff <y>, <x> must be less than <y> (got <x>: %f, y: %f)\n", 
                opt_Get("--lowpdiff",\%opt_HH) < opt_Get("--vlowpdiff",\%opt_HH)); 
  }
}
if(opt_IsUsed("--lowadiff",\%opt_HH) || opt_IsUsed("--vlowadiff",\%opt_HH)) { 
  if(opt_Get("--lowadiff",\%opt_HH) < opt_Get("--vlowadiff",\%opt_HH)) { 
    die sprintf("ERROR, with --lowadiff <x> and --vlowadiff <y>, <x> must be less than <y> (got <x>: %f, y: %f)\n", 
                opt_Get("--lowadiff",\%opt_HH) < opt_Get("--vlowadiff",\%opt_HH)); 
  }
}

my $cmd;                             # a command to be run by run_command()
my $ncpu = opt_Get("-n" , \%opt_HH); # number of CPUs to use with search command (default 0: --cpu 0)
my @to_remove_A = (); # array of files to remove at end
# the way we handle the $dir_out differs markedly if we have --skipsearch enabled
# so we handle that separately
if(opt_Get("--skipsearch", \%opt_HH)) { 
  if(-d $dir_out) { 
    # this is what we expect, do nothing
  }
  elsif(-e $dir_out) { 
    die "ERROR with --skipsearch, $dir_out must already exist as a directory, but it exists as a file, delete it first, then run without --skipsearch";
  }
  else { 
    die "ERROR with --skipsearch, $dir_out must already exist as a directory, but it does not. Run without --skipsearch";
  }
}
else {  # --skipsearch not used, normal case
  # if $dir_out already exists remove it only if -f also used
  if(-d $dir_out) { 
    $cmd = "rm -rf $dir_out";
    if(opt_Get("-f", \%opt_HH)) { run_command($cmd, opt_Get("-v", \%opt_HH)); }
    else                        { die "ERROR directory named $dir_out already exists. Remove it, or use -f to overwrite it."; }
  }
  elsif(-e $dir_out) { 
    $cmd = "rm $dir_out";
    if(opt_Get("-f", \%opt_HH)) { run_command($cmd, opt_Get("-v", \%opt_HH)); }
    else                        { die "ERROR a file named $dir_out already exists. Remove it, or use -f to overwrite it."; }
  }
  # if $dir_out does not exist, create it
  if(! -d $dir_out) { 
    $cmd = "mkdir $dir_out";
    run_command($cmd, opt_Get("-v", \%opt_HH));
  }
}
my $dir_out_tail   = $dir_out;
$dir_out_tail   =~ s/^.+\///; # remove all but last dir
my $out_root   = $dir_out .   "/" . $dir_out_tail   . ".ribotyper";

# make sure the sequence file exists
if(! -s $seq_file) { 
  die "ERROR unable to open sequence file $seq_file"; 
}

#############################################
# output program banner and open output files
#############################################
# output preamble
my @arg_desc_A = ();
my @arg_A      = ();

push(@arg_desc_A, "target sequence input file");
push(@arg_A, $seq_file);

push(@arg_desc_A, "query model input file");
push(@arg_A, $model_file);

push(@arg_desc_A, "model information input file");
push(@arg_A, $modelinfo_file);

push(@arg_desc_A, "output directory name");
push(@arg_A, $dir_out);

output_banner(*STDOUT, $version, $releasedate, $synopsis, $date);
opt_OutputPreamble(*STDOUT, \@arg_desc_A, \@arg_A, \%opt_HH, \@opt_order_A);

my $unsrt_long_out_file  = $out_root . ".unsrt.long.out";
my $unsrt_short_out_file = $out_root . ".unsrt.short.out";
my $srt_long_out_file  = $out_root . ".long.out";
my $srt_short_out_file = $out_root . ".short.out";
my $unsrt_long_out_FH;  # output file handle for unsorted long output file
my $unsrt_short_out_FH; # output file handle for unsorted short output file
my $srt_long_out_FH;    # output file handle for sorted long output file
my $srt_short_out_FH;   # output file handle for sorted short output file
if(! opt_Get("--keep", \%opt_HH)) { 
  push(@to_remove_A, $unsrt_long_out_file);
  push(@to_remove_A, $unsrt_short_out_file);
}
open($unsrt_long_out_FH,  ">", $unsrt_long_out_file)  || die "ERROR unable to open $unsrt_long_out_file for writing";
open($unsrt_short_out_FH, ">", $unsrt_short_out_file) || die "ERROR unable to open $unsrt_short_out_file for writing";
open($srt_long_out_FH,    ">", $srt_long_out_file)    || die "ERROR unable to open $srt_long_out_file for writing";
open($srt_short_out_FH,   ">", $srt_short_out_file)   || die "ERROR unable to open $srt_short_out_file for writing";

##########################
# determine search method
##########################
my $search_method = undef; # can be any of "cmsearch-hmmonly", "cmscan-hmmonly", 
#                                          "cmsearch-slow",    "cmscan-slow", 
#                                          "cmsearch-fast",    "cmscan-fast",
#                                          "nhmmer",           "ssualign"

if   (opt_Get("--nhmmer", \%opt_HH))   { $search_method = "nhmmer"; }
elsif(opt_Get("--cmscan", \%opt_HH))   { $search_method = "cmscan-fast"; }
elsif(opt_Get("--ssualign", \%opt_HH)) { $search_method = "ssualign"; }
else                                   { $search_method = "cmsearch-fast"; }

if(opt_Get("--hmm", \%opt_HH)) { 
  if   ($search_method eq "cmsearch-fast") { $search_method = "cmsearch-hmmonly"; }
  elsif($search_method eq "cmscan-fast")   { $search_method = "cmscan-hmmonly"; }
  else { die "ERROR, --hmm used in error, search_method: $search_method"; }
}
elsif(opt_Get("--slow", \%opt_HH)) { 
  if   ($search_method eq "cmsearch-fast") { $search_method = "cmsearch-slow"; }
  elsif($search_method eq "cmscan-fast")   { $search_method = "cmscan-slow"; }
  else { die "ERROR, --hmm used in error, search_method: $search_method"; }
}

###################################################
# make sure the required executables are executable
###################################################
my %execs_H = (); # hash with paths to all required executables
$execs_H{"cmscan"}          = $inf_exec_dir   . "cmscan";
$execs_H{"cmsearch"}        = $inf_exec_dir   . "cmsearch";
$execs_H{"esl-seqstat"}     = $esl_exec_dir   . "esl-seqstat";
if($search_method eq "nhmmer") { 
  $execs_H{"nhmmer"}          = $hmmer_exec_dir . "nhmmer";
}
if($search_method eq "ssualign") { 
  $execs_H{"ssu-align"}       = $hmmer_exec_dir . "ssu-align";
}
#$execs_H{"esl_ssplit"}    = $esl_ssplit;
validate_executable_hash(\%execs_H);

###########################################################################
###########################################################################
# Step 1: Parse/validate input files and run esl-seqstat to get sequence lengths.
my $progress_w = 74; # the width of the left hand column in our progress output, hard-coded
my $start_secs = output_progress_prior("Parsing and validating input files and determining target sequence lengths", $progress_w, undef, *STDOUT);
###########################################################################
# parse fam file
# variables related to fams and domains
my %family_H = (); # hash of fams,    key: model name, value: name of family model belongs to (e.g. SSU)
my %domain_H = (); # hash of domains, key: model name, value: name of domain model belongs to (e.g. Archaea)
parse_modelinfo_file($modelinfo_file, \%family_H, \%domain_H);

# parse the model file and make sure that there is a 1:1 correspondence between 
# models in the models file and models listed in the model info file
my %width_H = (); # hash, key is "model" or "target", value is maximum length of any model/target
$width_H{"model"} = parse_model_file($model_file, \%family_H);

# determine max width of domain, family, and classification (formed as family.domain)
$width_H{"domain"}         = length("domain");
$width_H{"family"}         = length("fam");
$width_H{"classification"} = length("classification");
my $model;
foreach $model (keys %domain_H) { 
  my $domain_len = length($domain_H{$model});
  my $family_len = length($family_H{$model});
  my $class_len  = $domain_len + $family_len + 1; # +1 is for the '.' separator
  if($domain_len > $width_H{"domain"})         { $width_H{"domain"}         = $domain_len; }
  if($family_len > $width_H{"family"})         { $width_H{"family"}         = $family_len; } 
  if($class_len  > $width_H{"classification"}) { $width_H{"classification"} = $class_len;  }
}

# parse input accept file, if nec
my %accept_H = ();
if(opt_IsUsed("--inaccept", \%opt_HH)) { 
  foreach $model (keys %domain_H) { 
    $accept_H{$model} = 0;
  }    
  parse_inaccept_file(opt_Get("--inaccept", \%opt_HH), \%accept_H);
}
else { # --inaccept not used, all models are acceptable
  foreach $model (keys %domain_H) { 
    $accept_H{$model} = 1;
  }   
} 

# run esl-seqstat to get sequence lengths
my $seqstat_file = $out_root . ".seqstat";
if(! opt_Get("--keep", \%opt_HH)) { 
  push(@to_remove_A, $seqstat_file);
}
run_command($execs_H{"esl-seqstat"} . " --dna -a $seq_file > $seqstat_file", opt_Get("-v", \%opt_HH));
my %seqidx_H = (); # key: sequence name, value: index of sequence in original input sequence file (1..$nseq)
my %seqlen_H = (); # key: sequence name, value: length of sequence, 
                   # value set to -1 after we output info for this sequence
                   # and then serves as flag for: "we output this sequence 
                   # already, if we see it again we know the tbl file was not
                   # sorted properly.
# parse esl-seqstat file to get lengths
my $max_targetname_length = length("target"); # maximum length of any target name
my $max_length_length     = length("length"); # maximum length of the string-ized length of any target
my $nseq                  = 0; # number of sequences read
parse_seqstat_file($seqstat_file, \$max_targetname_length, \$max_length_length, \$nseq, \%seqidx_H, \%seqlen_H); 
$width_H{"target"} = $max_targetname_length;
$width_H{"length"} = $max_length_length;
$width_H{"index"}  = length($nseq);
if($width_H{"index"} < length("#idx")) { $width_H{"index"} = length("#idx"); }

# now that we know the max sequence name length, we can output headers to the output files
output_long_headers($srt_long_out_FH,     \%opt_HH, \%width_H);
output_short_headers($srt_short_out_FH,             \%width_H);
###########################################################################
output_progress_complete($start_secs, undef, undef, *STDOUT);
###########################################################################
###########################################################################

###########################################################################
# Step 2: run search algorithm
# determine which algorithm to use and options to use as well
# as the command for sorting the output and parsing the output
# set up defaults
my $cmsearch_and_cmscan_opts = "";
my $tblout_file = "";
my $sorted_tblout_file = "";
my $searchout_file = "";
my $search_cmd = "";
my $sort_cmd = "";

if($search_method eq "nhmmer") { 
  $tblout_file        = $out_root . ".nhmmer.tbl";
  $sorted_tblout_file = $tblout_file . ".sorted";
  $searchout_file     = $out_root . ".nhmmer.out";
  $search_cmd         = $execs_H{"nhmmer"};
  if(opt_Get("--noali", \%opt_HH)) { $search_cmd .= " --noali"; }
  $search_cmd        .= " --cpu $ncpu --tblout $tblout_file $model_file $seq_file > $searchout_file";
  $sort_cmd           = "grep -v ^\# $tblout_file | sort -k1 > " . $sorted_tblout_file;
}
elsif($search_method eq "ssualign") { 
  $tblout_file        = $out_root . "/" . $dir_out_tail . ".ribotyper.tab";
  $sorted_tblout_file = $tblout_file . ".sorted";
  $searchout_file     = $out_root . ".nhmmer.out";
  $search_cmd         = $execs_H{"ssu-align"} . " --no-align -m $model_file -f $seq_file $out_root > /dev/null";
  $sort_cmd           = "grep -v ^\# $tblout_file | awk ' { printf(\"%s %s %s %s %s %s %s %s %s\\n\", \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9); } ' | sort -k2 > " . $sorted_tblout_file;
}
else { 
  # search_method is "cmsearch-slow", "cmscan-slow', "cmsearch-fast", or "cmscan-fast"
  if($search_method eq "cmsearch-fast" || $search_method eq "cmscan-fast") { 
    $cmsearch_and_cmscan_opts .= " --F1 0.02 --doF1b --F1b 0.02 --F2 0.001 --F3 0.00001 --trmF3 --nohmmonly --notrunc --noali ";
    if($search_method eq "cmscan-fast") { 
      $cmsearch_and_cmscan_opts .= " --fmt 2 ";
    }
  }
  elsif($search_method eq "cmsearch-slow" || $search_method eq "cmscan-slow") { 
    if   (opt_Get("--mid", \%opt_HH)) { 
      $cmsearch_and_cmscan_opts .= " --mid "; 
    }
    elsif(opt_Get("--max", \%opt_HH)) { 
      $cmsearch_and_cmscan_opts .= " --max "; 
      if(opt_IsUsed("--smxsize", \%opt_HH)) { 
        $cmsearch_and_cmscan_opts .= " --smxsize " . opt_Get("--smxsize", \%opt_HH) . " ";
      }
    }
    else { # default for --slow, --mid nor --max used (use cmsearch --rfam)
      $cmsearch_and_cmscan_opts .= " --rfam "; 
    }
    if($search_method eq "cmscan-slow") { 
      $cmsearch_and_cmscan_opts .= " --fmt 2 ";
    }
    if(opt_Get("--noali", \%opt_HH)) { 
      $cmsearch_and_cmscan_opts .= " --noali ";
    }
  }
  else { # $search_method is either "cmsearch-hmmonly", or "cmscan-hmmonly";
    $cmsearch_and_cmscan_opts .= " --hmmonly ";
    if($search_method eq "cmscan-hmmonly") { 
      $cmsearch_and_cmscan_opts .= " --fmt 2 ";
    }
    if(opt_Get("--noali", \%opt_HH)) { 
      $cmsearch_and_cmscan_opts .= " --noali ";
    }
  $search_cmd = $executable; 
  }
  if(($search_method eq "cmsearch-slow") || ($search_method eq "cmsearch-fast") || ($search_method eq "cmsearch-hmmonly")) { 
    $tblout_file        = $out_root . ".cmsearch.tbl";
    $sorted_tblout_file = $tblout_file . ".sorted";
    $searchout_file     = $out_root . ".cmsearch.out";
    $executable         = $execs_H{"cmsearch"};
    $sort_cmd           = "grep -v ^\# $tblout_file | sort -k1 > " . $sorted_tblout_file;
  }
  else { # search_method is "cmscan-slow", "cmscan-fast", or "cmscan-hmmonly"
    $tblout_file        = $out_root . ".cmscan.tbl";
    $sorted_tblout_file = $tblout_file . ".sorted";
    $searchout_file     = $out_root . ".cmscan.out";
    $executable         = $execs_H{"cmscan"};
    if($search_method eq "cmscan-fast") { 
      $sort_cmd = "grep -v ^\# $tblout_file | awk '{ printf(\"%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s\\n\", \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13, \$14, \$15, \$16, \$17); }' | sort -k3 > " . $sorted_tblout_file;
    }
    else { 
      $sort_cmd = "grep -v ^\# $tblout_file | sort -k4 > " . $sorted_tblout_file;
    }
  }
  $search_cmd = $executable . " --cpu $ncpu $cmsearch_and_cmscan_opts --tblout $tblout_file $model_file $seq_file > $searchout_file";
}
if(! opt_Get("--skipsearch", \%opt_HH)) { 
  $start_secs = output_progress_prior("Performing $search_method search ", $progress_w, undef, *STDOUT);
}
else { 
  $start_secs = output_progress_prior("Skipping $search_method search stage (using results from previous run)", $progress_w, undef, *STDOUT);
}
if(! opt_Get("--skipsearch", \%opt_HH)) { 
  run_command($search_cmd, opt_Get("-v", \%opt_HH));
}
else { 
  if(! -s $tblout_file) { 
    die "ERROR with --skipsearch, tblout file ($tblout_file) should exist and be non-empty but it's not";
  }
}
if(! opt_Get("--keep", \%opt_HH)) { 
  push(@to_remove_A, $tblout_file);
  push(@to_remove_A, $sorted_tblout_file);
  if(($search_method ne "nhmmer" || 
      $search_method ne "cmsearch-slow" || 
      $search_method ne "cmscan-slow" || 
      $search_method ne "cmsearch-hmmonly") && 
     (! opt_Get("--noali", \%opt_HH))) { 
    push(@to_remove_A, $searchout_file);
  }
}
output_progress_complete($start_secs, undef, undef, *STDOUT);

###########################################################################
# Step 3: Sort output
$start_secs = output_progress_prior("Sorting tabular search results", $progress_w, undef, *STDOUT);
run_command($sort_cmd, opt_Get("-v", \%opt_HH));
output_progress_complete($start_secs, undef, undef, *STDOUT);
###########################################################################

###########################################################################
# Step 4: Parse sorted output
$start_secs = output_progress_prior("Parsing tabular search results", $progress_w, undef, *STDOUT);
parse_sorted_tbl_file($sorted_tblout_file, $search_method, \%opt_HH, \%width_H, \%seqidx_H, \%seqlen_H, 
                      \%family_H, \%domain_H, \%accept_H, $unsrt_long_out_FH, $unsrt_short_out_FH);
output_progress_complete($start_secs, undef, undef, *STDOUT);
###########################################################################

#######################################################
# Step 5: Add data for sequences with 0 hits and then sort the output files 
#         based on sequence index
#         from original input file
###########################################################################
$start_secs = output_progress_prior("Sorting and finalizing output files", $progress_w, undef, *STDOUT);

# for any sequence that has 0 hits (we'll know these as those that 
# do not have a value of -1 in $seqlen_HR->{$target} at this stage
my $target;
foreach $target (keys %seqlen_H) { 
  if($seqlen_H{$target} ne "-1") { 
    output_one_hitless_target_wrapper($unsrt_long_out_FH, $unsrt_short_out_FH, \%opt_HH, \%width_H, $target, \%seqidx_H, \%seqlen_H);
  }
}

# now close the unsorted file handles (we're done with these) 
# and also the sorted file handles (so we can output directly to them using system())
# Remember, we already output the headers to these files above
close($unsrt_long_out_FH);
close($unsrt_short_out_FH);
close($srt_long_out_FH);
close($srt_short_out_FH);

$cmd = "sort -n $unsrt_short_out_file >> $srt_short_out_file";
run_command($cmd, opt_Get("-v", \%opt_HH));

$cmd = "sort -n $unsrt_long_out_file >> $srt_long_out_file";
run_command($cmd, opt_Get("-v", \%opt_HH));

# reopen them, and add tails to the output files
# now that we know the max sequence name length, we can output headers to the output files
open($srt_long_out_FH,  ">>", $srt_long_out_file)  || die "ERROR unable to open $unsrt_long_out_file for appending";
open($srt_short_out_FH, ">>", $srt_short_out_file) || die "ERROR unable to open $unsrt_short_out_file for appending";
output_long_tail($srt_long_out_FH, \%opt_HH);
output_short_tail($srt_short_out_FH, \%opt_HH);
close($srt_short_out_FH);
close($srt_long_out_FH);

# remove files we don't want anymore, then exit
foreach my $file (@to_remove_A) { 
  unlink $file;
}
output_progress_complete($start_secs, undef, undef, *STDOUT);

printf("#\n# Short (6 column) output saved to file $srt_short_out_file.\n");
printf("# Long (%d column) output saved to file $srt_long_out_file.\n", (opt_Get("--evalues", \%opt_HH) ? 20 : 18));
printf("#\n#[RIBO-SUCCESS]\n");

# cat the output file
#run_command("cat $short_out_file", opt_Get("-v", \%opt_HH));
#run_command("cat $long_out_file", opt_Get("-v", \%opt_HH));
###########################################################################

#####################################################################
# SUBROUTINES 
#####################################################################
# List of subroutines:
#
# Functions for parsing files:
# parse_modelinfo_file:    parse the model info input file
# parse_inaccept_file:      parse the inaccept input file (--inaccept)
# parse_model_file:         parse the model file 
# parse_seqstat_file:       parse esl-seqstat -a output file
# parse_sorted_tbl_file:    parse sorted tabular search results
#
# Helper functions for parse_sorted_tbl_file():
# init_vars:                 initialize variables for parse_sorted_tbl_file()
# set_vars:                  set variables for parse_sorted_tbl_file()
# 
# Functions for output: 
# output_one_target_wrapper: wrapper function for outputting info on one target sequence
#                            helper for parse_sorted_tbl_file()
# output_one_target:         output info on one target sequence
#                            helper for parse_sorted_tbl_file()
# output_short_headers:      output headers for short output file
# output_long_headers:       output headers for long output file
# output_banner:             output the banner with info on the script and options used
# output_progress_prior:     output routine for a step, prior to running the step
# output_progress_complete:  output routine for a step, after the running the step
#
# Miscellaneous functions:
# run_command:              run a command using system()
# validate_executable_hash: validate executables exist and are executable
# seconds_since_epoch:      number of seconds since the epoch, for timings
# debug_print:              print out info of a hit for debugging
# get_monocharacter_string: return string of a specified length of a specified character
# center_string:            center a string inside a string of whitespace of specified length
# determine_if_coverage_is_accurate(): determine if coverage values are accurate based on cmdline options
# get_overlap():            determine the extent of overlap of two regions
# get_overlap_helper():     does actual work to determine overlap
#
#################################################################
# Subroutine : parse_modelinfo_file()
# Incept:      EPN, Mon Dec 19 10:01:32 2016
#
# Purpose:     Parse a model info input file.
#              
# Arguments: 
#   $modelinfo_file: file to parse
#   $family_HR:       ref to hash of family names, key is model name, value is family name
#   $domain_HR:       ref to hash of domain names, key is model name, value is domain name
#
# Returns:     Nothing. Fills %{$family_H}, %{$domain_HR}
# 
# Dies:        Never.
#
################################################################# 
sub parse_modelinfo_file { 
  my $nargs_expected = 3;
  my $sub_name = "parse_modelinfo_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($modelinfo_file, $family_HR, $domain_HR) = @_;

  open(IN, $modelinfo_file) || die "ERROR unable to open model info file $modelinfo_file for reading";

# example line:
# SSU_rRNA_archaea SSU Archaea

  open(IN, $modelinfo_file) || die "ERROR unable to open $modelinfo_file for reading"; 
  while(my $line = <IN>) { 
    if($line !~ m/^\#/ && $line =~ m/\w/) { # skip comment lines and blank lines
      chomp $line;
      my @el_A = split(/\s+/, $line);
      if(scalar(@el_A) != 3) { 
        die "ERROR didn't read 3 tokens in model info input file $modelinfo_file, line $line"; 
      }
      my($model, $family, $domain) = (@el_A);

      if(exists $family_HR->{$model}) { 
        die "ERROR read model $model twice in $modelinfo_file"; 
      }
      $family_HR->{$model} = $family;
      $domain_HR->{$model} = $domain;
    }
  }
  close(IN);

  return;
}

#################################################################
# Subroutine : parse_inaccept_file()
# Incept:      EPN, Wed Mar  1 11:59:13 2017
#
# Purpose:     Parse the 'inaccept' input file.
#              
# Arguments: 
#   $inaccept_file:  file to parse
#   $accept_HR:      ref to hash of names, key is model name, value is '1' if model is acceptable
#                    This hash should already be defined with all model names and all values as '0'.
#
# Returns:     Nothing. Updates %{$accpep_HR}.
# 
# Dies:        Never.
#
################################################################# 
sub parse_inaccept_file { 
  my $nargs_expected = 2;
  my $sub_name = "parse_inaccept_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($inaccept_file, $accept_HR) = @_;

  open(IN, $inaccept_file) || die "ERROR unable to open input accept file $inaccept_file for reading";

# example line (one token per line)
# SSU_rRNA_archaea

  # construct string of all valid model names to use for error message
  my $valid_name_str = "\n";
  my $model;
  foreach $model (sort keys (%{$accept_HR})) { 
    $valid_name_str .= "\t" . $model . "\n";
  }

  open(IN, $inaccept_file) || die "ERROR unable to open $inaccept_file for reading"; 
  while(my $line = <IN>) { 
    chomp $line;
    if($line =~ m/\w/) { # skip blank lines
      my @el_A = split(/\s+/, $line);
      if(scalar(@el_A) != 1) { 
        die "ERROR didn't read 1 token in inaccept input file $inaccept_file, line $line\nEach line should have exactly 1 white-space delimited token, a valid model name"; 
      }
      ($model) = (@el_A);
      
      if(! exists $accept_HR->{$model}) { 
        die "ERROR read invalid model name \"$model\" in inaccept input file $inaccept_file\nValid model names are $valid_name_str"; 
      }
      
      $accept_HR->{$model} = 1;
    }
  }
  close(IN);

  return;
}

#################################################################
# Subroutine : parse_model_file()
# Incept:      EPN, Wed Mar  1 14:46:19 2017
#
# Purpose:     Parse the model file to get model names and
#              validate that there is 1:1 correspondence between
#              model names in the model file and the keys 
#              from %{$family_HR}.
#              
# Arguments: 
#   $model_file:  model file to parse
#   $family_HR:   ref to hash of families for each model, ALREADY FILLED
#                 we use this only for validation
#
# Returns:     Maximum length of any model read from the model file.
# 
# Dies:        If $model_file does not exist or is empty.
#
################################################################# 
sub parse_model_file { 
  my $nargs_expected = 2;
  my $sub_name = "parse_inaccept_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($model_file, $family_HR) = @_;

  if(! -e $model_file) { die "ERROR model file $model_file does not exist"; }
  if(! -s $model_file) { die "ERROR model file $model_file exists but is empty"; }

  # make copy of %{$family_HR} with all values set to '0' 
  my $model;
  my @tmp_family_model_A = ();
  my %tmp_family_model_H = ();
  foreach $model (keys %{$family_HR}) { 
    push(@tmp_family_model_A, $model);
    $tmp_family_model_H{$model} = 0; # will set to '1' when we see it in the model file
  }

  my $model_width = length("model");
  my $name_output = `grep NAME $model_file | awk '{ print \$2 }'`;
  my @name_A = split("\n", $name_output);
  foreach $model (@name_A) { 
    if(! exists $tmp_family_model_H{$model}) { 
      die "ERROR read model \"$model\" from model file $model_file that is not listed in the model info file.";
    }
    $tmp_family_model_H{$model} = 1;
    if(length($model) > $model_width) { 
      $model_width = length($model);
    }
  }

  foreach $model (keys %tmp_family_model_H) { 
    if($tmp_family_model_H{$model} == 0) { 
      die "ERROR model \"$model\" read from model info file is not in the model file.";
    }
  }

  return $model_width;
}

#################################################################
# Subroutine : parse_seqstat_file()
# Incept:      EPN, Wed Dec 14 16:16:22 2016
#
# Purpose:     Parse an esl-seqstat -a output file.
#              
# Arguments: 
#   $seqstat_file:            file to parse
#   $max_targetname_length_R: REF to the maximum length of any target name, updated here
#   $max_length_length_R:     REF to the maximum length of string-ized length of any target seq, updated here
#   $nseq_R:                  REF to the number of sequences read, updated here
#   $seqidx_HR:               REF to hash of sequence indices to fill here
#   $seqlen_HR:               REF to hash of sequence lengths to fill here
#
# Returns:     Nothing. Fills %{$seqidx_HR} and %{$seqlen_HR} and updates 
#              $$max_targetname_length_R, $$max_length_length_R, and $$nseq_R.
# 
# Dies:        If the sequence file has two sequences with identical names.
#              Error message will list all duplicates.
#              If no sequences were read.
#
################################################################# 
sub parse_seqstat_file { 
  my $nargs_expected = 6;
  my $sub_name = "parse_seqstat_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($seqstat_file, $max_targetname_length_R, $max_length_length_R, $nseq_R, $seqidx_HR, $seqlen_HR) = @_;

  open(IN, $seqstat_file) || die "ERROR unable to open esl-seqstat file $seqstat_file for reading";

  my $nread = 0;
  my $targetname_length;
  my $seqlength_length;
  my $targetname;
  my $length;
  my %seqdups_H = ();       # key is a sequence name that exists more than once in seq file, value is number of occurences
  my $at_least_one_dup = 0; # set to 1 if we find any duplicate sequence names

  while(my $line = <IN>) { 
    # = lcl|dna_BP331_0.3k:467     1232 
    # = lcl|dna_BP331_0.3k:10     1397 
    # = lcl|dna_BP331_0.3k:1052     1414 
    chomp $line;
    #print $line . "\n";
    if($line =~ /^\=\s+(\S+)\s+(\d+)/) { 
      $nread++;
      ($targetname, $length) = ($1, $2);
      if(exists($seqidx_HR->{$targetname})) { 
        if(exists($seqdups_H{$targetname})) { 
          $seqdups_H{$targetname}++;
        }
        else { 
          $seqdups_H{$targetname} = 2;
        }
        $at_least_one_dup = 1;
      }
        
      $seqidx_HR->{$targetname} = $nread;
      $seqlen_HR->{$targetname} = $length;

      $targetname_length = length($targetname);
      if($targetname_length > $$max_targetname_length_R) { 
        $$max_targetname_length_R = $targetname_length;
      }

      $seqlength_length  = length($length);
      if($seqlength_length > $$max_length_length_R) { 
        $$max_length_length_R = $seqlength_length;
      }

    }
  }
  close(IN);
  if($nread == 0) { 
    die "ERROR did not read any sequence lengths in esl-seqstat file $seqstat_file, did you use -a option with esl-seqstat";
  }
  if($at_least_one_dup) { 
    my $i = 1;
    my $die_string = "\nERROR, not all sequences in input sequence file have a unique name. They must.\nList of sequences that occur more than once, with number of occurrences:\n";
    foreach $targetname (sort keys %seqdups_H) { 
      $die_string .= "\t($i) $targetname $seqdups_H{$targetname}\n";
      $i++;
    }
    $die_string .= "\n";
    die $die_string;
  }

  $$nseq_R = $nread;
  return;
}

#################################################################
# Subroutine : parse_sorted_tblout_file()
# Incept:      EPN, Thu Dec 29 09:52:16 2016
#
# Purpose:     Parse a sorted tabular output file and generate output.
#              
# Arguments: 
#   $sorted_tbl_file: file with sorted tabular search results
#   $search_method:   search method (one of "cmsearch-hmmonly", "cmscan-hmmonly"
#                                           "cmsearch-slow",    "cmscan-slow", 
#                                           "cmsearch-fast",    "cmscan-fast",
#                                           "nhmmer",           "ssualign")
#   $opt_HHR:         ref to 2D options hash of cmdline option values
#   $width_HR:        hash, key is "model" or "target", value 
#                     is width (maximum length) of any target/model
#   $seqidx_HR:       ref to hash of sequence indices, key is sequence name, value is index
#   $seqlen_HR:       ref to hash of sequence lengths, key is sequence name, value is length
#   $family_HR:       ref to hash of family names, key is model name, value is family name
#   $domain_HR:       ref to hash of domain names, key is model name, value is domain name
#   $accept_HR:       ref to hash of acceptable models, key is model name, value is '1' if acceptable
#   $long_out_FH:     file handle for long output file, already open
#   $short_out_FH:    file handle for short output file, already open
#
# Returns:     Nothing. Fills %{$family_H}, %{$domain_HR}
# 
# Dies:        Never.
#
################################################################# 
sub parse_sorted_tbl_file { 
  my $nargs_expected = 11;
  my $sub_name = "parse_sorted_tbl_file";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($sorted_tbl_file, $search_method, $opt_HHR, $width_HR, $seqidx_HR, $seqlen_HR, $family_HR, $domain_HR, $accept_HR, $long_out_FH, $short_out_FH) = @_;

  # validate search method (sanity check) 
  if(($search_method ne "cmsearch-hmmonly") && ($search_method ne "cmscan-hmmonly") && 
     ($search_method ne "cmsearch-slow")    && ($search_method ne "cmscan-slow") &&
     ($search_method ne "cmsearch-fast")    && ($search_method ne "cmscan-fast") &&      
     ($search_method ne "nhmmer")           && ($search_method ne "ssualign")) { 
    die "ERROR in $sub_name, invalid search method $search_method";
  }

  # determine minimum bit score cutoff
  my $minsc = undef;
  if(! opt_Get("--nominsc", $opt_HHR)) { 
    $minsc = opt_Get("--minsc", $opt_HHR);
  }
  
  # Main data structures: 
  # 'one': current top scoring model for current sequence
  # 'two': current second best scoring model for current sequence 
  #        that overlaps with hit in 'one' data structures
  # 
  # keys for all below are families (e.g. 'SSU' or 'LSU')
  # values are for the best scoring hit in this family to current sequence
  my %one_model_H;  
  my %one_domain_H;  
  my %one_score_H;  
  my %one_evalue_H; 
  my %one_start_H;  
  my %one_stop_H;   
  my %one_strand_H; 
  
  # same as for 'one' data structures, but values are for second best scoring hit
  # in this family to current sequence that overlaps with hit in 'one' data structures
  my %two_model_H;
  my %two_domain_H;  
  my %two_score_H;
  my %two_evalue_H;
  my %two_start_H;
  my %two_stop_H;
  my %two_strand_H;

  # statistics we keep track of per model and strand, used to detect various output statistics and
  # to report 'unexpected features'
  my %nnts_per_model_HH  = ();   # hash; key 1: model name, key 2: strand ("+" or "-") value: number of 
                                 # nucleotides in all hits (no threshold applied) to model for that strand for 
                                 # current target sequence
  my %nhits_per_model_HH = ();   # hash; key 1: model name, key 2: strand ("+" or "-") value: number of 
                                 # hits to model above threshold for that strand for current target sequence
  my %mdl_bd_per_model_HHA = (); # hash; key 1: model name, key 2: strand ("+" or "-") value: an array of model 
                                 # coordinate boundaries for all hits above threshold (sorted by score), 
                                 # each element of the array is a string of the format <d1>-<d2>, 
                                 # where <d1> is the 5' model position boundary of the hit and 
                                 # <d2> is the 3' model position boundary of the hit
  my %seq_bd_per_model_HHA = (); # hash; key 1: model name, key 2: strand ("+" or "-") value: an array of sequence
                                 # coordinate boundaries for all hits above threshold (sorted by score), 
                                 # each element of the array is a string of the format <d1>-<d2>, 
                                 # where <d1> is the 5' sequence position boundary of the hit and 
                                 # <d2> is the 3' sequence position boundary of the hit
                                 # if strand is '+', <d1> <= <d2> and if strand is '-', <d1> >= <d2>

  my $prv_target = undef; # target name of previous line
  my $family     = undef; # family of current model

  open(IN, $sorted_tbl_file) || die "ERROR unable to open sorted tabular file $sorted_tbl_file for reading";

  init_vars(\%one_model_H, \%one_domain_H, \%one_score_H, \%one_evalue_H, \%one_start_H, \%one_stop_H, \%one_strand_H);
  init_vars(\%two_model_H, \%two_domain_H, \%two_score_H, \%two_evalue_H, \%two_start_H, \%two_stop_H, \%two_strand_H);

  my ($target, $model, $domain, $mdlfrom, $mdlto, $seqfrom, $seqto, $strand, $score, $evalue) = 
      (undef, undef, undef, undef, undef, undef, undef, undef, undef, undef);
  my $cur_becomes_one; # set to true for each hit if it is better than our current 'one' hit
  my $cur_becomes_two; # set to true for each hit if it is better than our current 'two' hit
  my $cur_domain_or_model; # domain (default) or model (--samedomain) of current hit
  my $one_domain_or_model; # domain (default) or model (--samedomain) of current 'one' hit
  my $two_domain_or_model; # domain (default) or model (--samedomain) of current 'two' hit
  my $use_evalues = opt_Get("--evalues", $opt_HHR);
  my $nhits_above_thresh = 0; # number of hits above threshold for current sequence

  while(my $line = <IN>) { 
    ######################################################
    # Parse the data on this line, this differs depending
    # on our annotation method
    chomp $line;
    $line =~ s/^\s+//; # remove leading whitespace
    
    if($line =~ m/^\#/) { 
      die "ERROR, found line that begins with #, input should have these lines removed and be sorted by the first column:$line.";
    }
    my @el_A = split(/\s+/, $line);

    if(($search_method eq "cmsearch-fast") || ($search_method eq "cmscan-fast")) { 
      if($search_method eq "cmsearch-fast") {
        if(scalar(@el_A) != 9) { die "ERROR did not find 9 columns in fast cmsearch tabular output at line: $line"; }
        # NC_013790.1 SSU_rRNA_archaea 1215.0  760337  762896      +     ..  ?      2937203
        ($target, $model, $score, $seqfrom, $seqto, $strand) = 
            ($el_A[0], $el_A[1], $el_A[2], $el_A[3], $el_A[4], $el_A[5]);
        $mdlfrom = 1; # irrelevant, but removes uninitialized value warnings
        $mdlto   = 1; # irrelevant, but removes uninitialized value warnings
      }
      else { # $search_method is "cmscan-fast"
        if(scalar(@el_A) != 17) { die "ERROR did not find 9 columns in fast cmscan tabular output at line: $line"; }
        ##idx target name          query name             clan name  score seq from   seq to strand bounds      seqlen olp anyidx afrct1 afrct2 winidx wfrct1 wfrct2
        ##--- -------------------- ---------------------- --------- ------ -------- -------- ------ ------ ----------- --- ------ ------ ------ ------ ------ ------
        # 1    SSU_rRNA_archaea     lcl|dna_BP331_0.3k:467 -          559.8        1     1232      +     []        1232  =       2  1.000  1.000      "      "      "
        ($target, $model, $score, $seqfrom, $seqto, $strand) = 
            ($el_A[2], $el_A[1], $el_A[4], $el_A[5], $el_A[6], $el_A[7]);
        $mdlfrom = 1; # irrelevant, but removes uninitialized value warnings
        $mdlto   = 1; # irrelevant, but removes uninitialized value warnings
      }
    }    
    elsif($search_method eq "cmsearch-hmmonly" || $search_method eq "cmsearch-slow") { 
      ##target name             accession query name           accession mdl mdl from   mdl to seq from   seq to strand trunc pass   gc  bias  score   E-value inc description of target
      ##----------------------- --------- -------------------- --------- --- -------- -------- -------- -------- ------ ----- ---- ---- ----- ------ --------- --- ---------------------
      #lcl|dna_BP444_24.8k:251  -         SSU_rRNA_archaea     RF01959   hmm        3     1443        2     1436      +     -    6 0.53   6.0 1078.9         0 !   -
      if(scalar(@el_A) < 18) { die "ERROR found less than 18 columns in cmsearch tabular output at line: $line"; }
      ($target, $model, $mdlfrom, $mdlto, $seqfrom, $seqto, $strand, $score, $evalue) = 
          ($el_A[0], $el_A[2], $el_A[5], $el_A[6], $el_A[7], $el_A[8], $el_A[9],  $el_A[14], $el_A[15]);
    }
    elsif($search_method eq "cmscan-hmmonly" || $search_method eq "cmscan-slow") { 
      ##idx target name          accession query name             accession clan name mdl mdl from   mdl to seq from   seq to strand trunc pass   gc  bias  score   E-value inc olp anyidx afrct1 afrct2 winidx wfrct1 wfrct2 description of target
      ##--- -------------------- --------- ---------------------- --------- --------- --- -------- -------- -------- -------- ------ ----- ---- ---- ----- ------ --------- --- --- ------ ------ ------ ------ ------ ------ ---------------------
      #  1    SSU_rRNA_bacteria    RF00177   lcl|dna_BP331_0.3k:467 -         -         hmm       37     1301        1     1228      +     -    6 0.53   6.2  974.2  2.8e-296  !   ^       -      -      -      -      -      - -
      # same as cmsearch but target/query are switched
      if(scalar(@el_A) < 27) { die "ERROR found less than 27 columns in cmscan tabular output at line: $line"; }
      ($target, $model, $mdlfrom, $mdlto, $seqfrom, $seqto, $strand, $score, $evalue) = 
          ($el_A[3], $el_A[1], $el_A[7], $el_A[8], $el_A[9], $el_A[10], $el_A[11],  $el_A[16], $el_A[17]);
    }
    elsif($search_method eq "nhmmer") { 
      ## target name            accession  query name           accession  hmmfrom hmm to alifrom  ali to envfrom  env to  sq len strand   E-value  score  bias  description of target
      ###    ------------------- ---------- -------------------- ---------- ------- ------- ------- ------- ------- ------- ------- ------ --------- ------ ----- ---------------------
      #  lcl|dna_BP444_24.8k:251  -          SSU_rRNA_archaea     RF01959          3    1443       2    1436       1    1437    1437    +           0 1036.1  18.0  -
      if(scalar(@el_A) < 16) { die "ERROR found less than 16 columns in nhmmer tabular output at line: $line"; }
      ($target, $model, $mdlfrom, $mdlto, $seqfrom, $seqto, $strand, $score, $evalue) = 
          ($el_A[0], $el_A[2], $el_A[4], $el_A[5], $el_A[6], $el_A[7], $el_A[11],  $el_A[13], $el_A[12]);
    }
    elsif($search_method eq "ssualign") { 
      ##                                                 target coord   query coord                         
      ##                                       ----------------------  ------------                         
      ## model name  target name                    start        stop  start   stop    bit sc   E-value  GC%
      ## ----------  ------------------------  ----------  ----------  -----  -----  --------  --------  ---
      #  archaea     lcl|dna_BP331_0.3k:467            18        1227      1   1508    478.86         -   53
      if(scalar(@el_A) != 9) { die "ERROR did not find 9 columns in SSU-ALIGN tabular output line: $line"; }
      ($target, $model, $seqfrom, $seqto, $mdlfrom, $mdlto, $score) = 
          ($el_A[1], $el_A[0], $el_A[2], $el_A[3], $el_A[4], $el_A[5], $el_A[6]);
      $strand = "+";
      if($seqfrom > $seqto) { $strand = "-"; }
      $evalue = "-";
    }
    else { 
      die "ERROR, $search_method is not a valid method";
    }

    $family = $family_HR->{$model};
    if(! defined $family) { 
      die "ERROR unrecognized model $model, no family information";
    }

    # two sanity checks:
    # make sure we have sequence length information for this sequence
    if(! exists $seqlen_HR->{$target}) { 
      die "ERROR found sequence $target we didn't read length information for in $seqstat_file";
    }
    # make sure we haven't output information for this sequence already
    if($seqlen_HR->{$target} == -1) { 
      die "ERROR found line with target $target previously output, did you sort by sequence name?";
    }
    # finished parsing data for this line
    ######################################################

    ##############################################################
    # Are we now finished with the previous sequence? 
    # Yes, if target sequence we just read is different from it
    # If yes, output info for it, and re-initialize data structures
    # for new sequence just read
    if((defined $prv_target) && ($prv_target ne $target)) { 
      if($nhits_above_thresh > 0) { 
        output_one_target_wrapper($long_out_FH, $short_out_FH, $opt_HHR, $use_evalues, $width_HR, $domain_HR, $accept_HR, 
                                  $prv_target, $seqidx_HR, $seqlen_HR, \%nhits_per_model_HH, \%nnts_per_model_HH, 
                                  \%mdl_bd_per_model_HHA, \%seq_bd_per_model_HHA, 
                                  \%one_model_H, \%one_domain_H, \%one_score_H, \%one_evalue_H, \%one_start_H, \%one_stop_H, \%one_strand_H, 
                                  \%two_model_H, \%one_domain_H, \%two_score_H, \%two_evalue_H, \%two_start_H, \%two_stop_H, \%two_strand_H);
      }
      $nhits_above_thresh   = 0;
      %nhits_per_model_HH   = ();
      %nnts_per_model_HH    = ();
      %mdl_bd_per_model_HHA = ();
      %seq_bd_per_model_HHA = ();
    }
    ##############################################################
    
    ##########################################################
    # Determine if this hit is either a new 'one' or 'two' hit
    $cur_becomes_one     = 0;       # set to '1' below if no 'one' hit exists yet, or this E-value/score is better than current 'one'
    $cur_becomes_two     = 0;       # set to '1' below if no 'two' hit exists yet, or this E-value/score is better than current 'two'
    $domain = $domain_HR->{$model}; # the domain for this model
    $one_domain_or_model = undef;   # top hit's domain (default) or model (if --samedomain)
    $two_domain_or_model = undef;   # second best hit's domain (default) or model (if --samedomain)
    $cur_domain_or_model = (opt_Get("--samedomain", $opt_HHR)) ? $model : $domain;

    # we count all nucleotides in all hits (don't enforce minimum threshold) to each model
    $nnts_per_model_HH{$model}{$strand} += abs($seqfrom - $seqto) + 1;

    # first, enforce our global bit score minimum
    if((! defined $minsc) || ($score >= $minsc)) { 
      # yes, we either have no minimum, or our score exceeds our minimum
      $nhits_above_thresh++;
      # we only count hits above threshold
      $nhits_per_model_HH{$model}{$strand}++;
      if(! exists $mdl_bd_per_model_HHA{$model}{$strand}) { 
        @{$mdl_bd_per_model_HHA{$model}{$strand}} = ();
        @{$seq_bd_per_model_HHA{$model}{$strand}} = ();
      }
      push(@{$mdl_bd_per_model_HHA{$model}{$strand}}, ($mdlfrom . "." . $mdlto)); 
      push(@{$seq_bd_per_model_HHA{$model}{$strand}}, ($seqfrom . "." . $seqto)); 

      if(! defined $one_score_H{$family}) {  # use 'score' not 'evalue' because some methods don't define evalue, but all define score
        $cur_becomes_one = 1; # no current, 'one' this will be it
      }
      else { 
        # determine the domain (default) or model (--samedomain) of top hit and current hit we're looking at
        # if --samedomain, we require that top two hits be different models, not necessarily different domains
        $one_domain_or_model = (opt_Get("--samedomain", $opt_HHR)) ? $one_model_H{$family} : $one_domain_H{$family};
        if($use_evalues) { 
          if(($evalue < $one_evalue_H{$family}) || # this E-value is better than (less than) our current 'one' E-value
             ($evalue eq $one_evalue_H{$family} && $score > $one_score_H{$family})) { # this E-value equals current 'one' E-value, 
            # but this score is better than current 'one' score
            $cur_becomes_one = 1;
          }
        }
        else { # we don't have E-values
          if($score > $one_score_H{$family}) { # score is better than current 'one' score
            $cur_becomes_one = 1;
          }
        }
      }
      # only possibly set $cur_becomes_two to TRUE if $cur_becomes_one is FALSE, and it's not the same model/domain as 'one'
      if((! $cur_becomes_one) && ($cur_domain_or_model ne $one_domain_or_model)) { 
        if(! defined $two_score_H{$family}) {  # use 'score' not 'evalue' because some methods don't define evalue, but all define score
          $cur_becomes_two = 1;
        }
        else { 
          $two_domain_or_model = (opt_Get("--samedomain", $opt_HHR)) ? $two_model_H{$family} : $two_domain_H{$family};
          if($use_evalues) { 
            if(($evalue < $two_evalue_H{$family}) || # this E-value is better than (less than) our current 'two' E-value
               ($evalue eq $two_evalue_H{$family} && $score > $two_score_H{$family})) { # this E-value equals current 'two' E-value, 
              # but this score is better than current 'two' score
              $cur_becomes_two = 1;
            }
          }
          else { # we don't have E-values
            if($score > $two_score_H{$family}) { # score is better than current 'one' score
              $cur_becomes_two = 1;
            }
          }
        }
      }
    } # end of 'if((! defined $minsc) || ($score >= $minsc))'
    # finished determining if this hit is a new 'one' or 'two' hit
    ##########################################################
    
    ##########################################################
    # if we have a new hit, update 'one' and/or 'two' data structures
    if($cur_becomes_one) { 
      # new 'one' hit, update 'one' variables, 
      # but first copy existing 'one' hit values to 'two', if 'one' hit is defined and it's a different model than current $model
      if((defined $one_domain_or_model) && ($one_domain_or_model ne $cur_domain_or_model)) { 
        set_vars($family, \%two_model_H, \%two_domain_H, \%two_score_H, \%two_evalue_H, \%two_start_H, \%two_stop_H, \%two_strand_H, 
                 $one_model_H{$family},  $one_domain_H{$family},  $one_score_H{$family},  $one_evalue_H{$family},  $one_start_H{$family},  $one_stop_H{$family},  $one_strand_H{$family});
      }
      # now set new 'one' hit values
      set_vars($family, \%one_model_H, \%one_domain_H, \%one_score_H, \%one_evalue_H, \%one_start_H, \%one_stop_H, \%one_strand_H, 
               $model, $domain, $score, $evalue, $seqfrom, $seqto, $strand);
    }
    elsif(($cur_becomes_two) && ($one_domain_or_model ne $cur_domain_or_model)) { 
      # new 'two' hit, set it
      # (we don't need to check that 'one_domain_or_model ne cur_domain_or_model' because we did that
      #  above before we set cur_becomes_two to true)
      set_vars($family, \%two_model_H, \%two_domain_H, \%two_score_H, \%two_evalue_H, \%two_start_H, \%two_stop_H, \%two_strand_H, 
               $model, $domain, $score, $evalue, $seqfrom, $seqto, $strand);
    }
    # finished updating 'one' or 'two' data structures
    ##########################################################

    $prv_target = $target;

    # sanity check
    if((defined $one_model_H{$family} && defined $two_model_H{$family}) && ($one_model_H{$family} eq $two_model_H{$family})) { 
      die "ERROR, coding error, one_model and two_model are identical for $family $target";
    }
  }

  # output data for final sequence
  if($nhits_above_thresh > 0) { 
    output_one_target_wrapper($long_out_FH, $short_out_FH, $opt_HHR, $use_evalues, $width_HR, $domain_HR, $accept_HR, 
                              $prv_target, $seqidx_HR, $seqlen_HR, \%nhits_per_model_HH, \%nnts_per_model_HH, 
                              \%mdl_bd_per_model_HHA, \%seq_bd_per_model_HHA, 
                              \%one_model_H, \%one_domain_H, \%one_score_H, \%one_evalue_H, \%one_start_H, \%one_stop_H, \%one_strand_H, 
                              \%two_model_H, \%one_domain_H, \%two_score_H, \%two_evalue_H, \%two_start_H, \%two_stop_H, \%two_strand_H);
  }
  # close file handle
  close(IN);
  
  return;
}

#################################################################
# Subroutine : init_vars()
# Incept:      EPN, Tue Dec 13 14:53:37 2016
#
# Purpose:     Initialize variables to undefined 
#              given references to them.
#              
# Arguments: 
#   $model_HR:   REF to $model variable hash, a model name
#   $domain_HR:  REF to $domain variable hash, domain for model
#   $score_HR:   REF to $score variable hash, a bit score
#   $evalue_HR:  REF to $evalue variable hash, an E-value
#   $start_HR:   REF to $start variable hash, a start position
#   $stop_HR:    REF to $stop variable hash, a stop position
#   $strand_HR:  REF to $strand variable hash, a strand
# 
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub init_vars { 
  my $nargs_expected = 7;
  my $sub_name = "init_vars";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($model_HR, $domain_HR, $score_HR, $evalue_HR, $start_HR, $stop_HR, $strand_HR) = @_;

  foreach my $key (keys %{$model_HR}) { 
    delete $model_HR->{$key};
    delete $domain_HR->{$key};
    delete $score_HR->{$key};
    delete $evalue_HR->{$key};
    delete $start_HR->{$key};
    delete $stop_HR->{$key};
    delete $strand_HR->{$key};
  }
  

  return;
}

#################################################################
# Subroutine : set_vars()
# Incept:      EPN, Tue Dec 13 14:53:37 2016
#
# Purpose:     Set variables defining the top-scoring 'one' 
#              model. If necessary switch the current
#              'one' variable values to 'two' variables.
#              
# Arguments: 
#   $family:    family, key to hashes
#   $model_HR:  REF to hash of $model variables, a model name
#   $domain_HR: REF to $domain variable hash, domain for model
#   $score_HR:  REF to hash of $score variables, a bit score
#   $evalue_HR: REF to hash of $evalue variables, an E-value
#   $start_HR:  REF to hash of $start variables, a start position
#   $stop_HR:   REF to hash of $stop variables, a stop position
#   $strand_HR: REF to hash of $strand variables, a strand
#   $model:     value to set $model_HR{$family} to 
#   $domain:    value to set $domain_HR{$family} to 
#   $score:     value to set $score_HR{$family} to 
#   $evalue:    value to set $evalue_HR{$family} to 
#   $start:     value to set $start_HR{$family} to 
#   $stop:      value to set $stop_HR{$family} to 
#   $strand:    value to set $strand_HR{$family} to 
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub set_vars { 
  my $nargs_expected = 15;
  my $sub_name = "set_vars";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($family, 
      $model_HR, $domain_HR, $score_HR, $evalue_HR, $start_HR, $stop_HR, $strand_HR, 
      $model,    $domain,    $score,    $evalue,    $start,    $stop,    $strand) = @_;

  $model_HR->{$family}  = $model;
  $domain_HR->{$family} = $domain;
  $score_HR->{$family}  = $score;
  $evalue_HR->{$family} = $evalue;
  $start_HR->{$family}  = $start;
  $stop_HR->{$family}   = $stop;
  $strand_HR->{$family} = $strand;

  return;
}

#################################################################
# Subroutine : output_one_target_wrapper()
# Incept:      EPN, Thu Dec 22 13:49:53 2016
#
# Purpose:     Call function to output information and reset variables.
#              
# Arguments: 
#   $long_FH:       file handle to output long data to
#   $short_FH:      file handle to output short data to
#   $opt_HHR:       reference to 2D hash of cmdline options
#   $use_evalues:  '1' if we have E-values, '0' if not
#   $width_HR:      hash, key is "model" or "target", value 
#                   is width (maximum length) of any target/model
#   $domain_HR:     reference to domain hash
#   $accept_HR:     reference to the 'accept' hash, key is "model"
#                   value is '1' if hits to model are "PASS"es '0'
#                   if they are "FAIL"s
#   $target:        target name
#   $seqidx_HR:     hash of target sequence indices
#   $seqlen_HR:     hash of target sequence lengths
#   $nhits_HHR:     reference to hash of num hits per model (key 1), per strand (key 2)
#   $nnts_HHR:      reference to hash of num nucleotides in all hits per model (key 1), per strand (key 2)
#   $mdl_bd_HHAR:   reference to hash of hash of array of model boundaries per hits, per model (key 1), per strand (key 2)
#   $seq_bd_HHAR:   reference to hash of hash of array of sequence boundaries per hits, per model (key 1), per strand (key 2)
#   %one_model_HR:  'one' model
#   %one_domain_HR: 'one' domain
#   %one_score_HR:  'one' bit score
#   %one_evalue_HR: 'one' E-value
#   %one_start_HR:  'one' start position
#   %one_stop_HR:   'one' stop position
#   %one_strand_HR: 'one' strand 
#   %two_model_HR:  'two' model
#   %two_domain_HR: 'two' domain
#   %two_score_HR:  'two' bit score
#   %two_evalue_HR: 'two' E-value
#   %two_start_HR:  'two' start position
#   %two_stop_HR:   'two' stop position
#   %two_strand_HR: 'two' strand 
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_one_target_wrapper { 
  my $nargs_expected = 28;
  my $sub_name = "output_one_target_wrapper";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($long_FH, $short_FH, $opt_HHR, $use_evalues, $width_HR, $domain_HR, $accept_HR, 
      $target, $seqidx_HR, $seqlen_HR, $nhits_HHR, $nnts_HHR, 
      $mdl_bd_HHAR, $seq_bd_HHAR, 
      $one_model_HR, $one_domain_HR, $one_score_HR, $one_evalue_HR, $one_start_HR, $one_stop_HR, $one_strand_HR, 
      $two_model_HR, $two_domain_HR, $two_score_HR, $two_evalue_HR, $two_start_HR, $two_stop_HR, $two_strand_HR) = @_;

  # output to short and long output files
  output_one_target($short_FH, $long_FH, $opt_HHR, $use_evalues, $width_HR, $domain_HR, $accept_HR, $target, 
                    $seqidx_HR->{$target}, $seqlen_HR->{$target}, $nhits_HHR, $nnts_HHR, 
                    $mdl_bd_HHAR, $seq_bd_HHAR, 
                    $one_model_HR, $one_score_HR, $one_evalue_HR, $one_start_HR, $one_stop_HR, $one_strand_HR, 
                    $two_model_HR, $two_score_HR, $two_evalue_HR, $two_start_HR, $two_stop_HR, $two_strand_HR);

  # reset vars
  init_vars($one_model_HR, $one_domain_HR, $one_score_HR, $one_evalue_HR, $one_start_HR, $one_stop_HR, $one_strand_HR);
  init_vars($two_model_HR, $one_domain_HR, $two_score_HR, $two_evalue_HR, $two_start_HR, $two_stop_HR, $two_strand_HR);
  $seqlen_HR->{$target} = -1; # serves as a flag that we output info for this sequence
  
  return;
}

#################################################################
# Subroutine : output_one_hitless_target_wrapper()
# Incept:      EPN, Thu Mar  2 11:35:28 2017
#
# Purpose:     Call function to output information for a target
#              with zero hits.
#              
# Arguments: 
#   $long_FH:       file handle to output long data to
#   $short_FH:      file handle to output short data to
#   $opt_HHR:       reference to 2D hash of cmdline options
#   $width_HR:      hash, key is "model" or "target", value 
#                   is width (maximum length) of any target/model
#   $target:        target name
#   $seqidx_HR:     hash of target sequence indices
#   $seqlen_HR:     hash of target sequence lengths
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_one_hitless_target_wrapper { 
  my $nargs_expected = 7;
  my $sub_name = "output_one_hitless_target_wrapper";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($long_FH, $short_FH, $opt_HHR, $width_HR, $target, $seqidx_HR, $seqlen_HR) = @_;

  # output to short and long output files
  output_one_hitless_target($long_FH,  0, $opt_HHR, $width_HR, $target, $seqidx_HR->{$target}, $seqlen_HR->{$target}); 
  output_one_hitless_target($short_FH, 1, $opt_HHR, $width_HR, $target, $seqidx_HR->{$target}, $seqlen_HR->{$target}); 

  #$seqlen_HR->{$target} = -1; # serves as a flag that we output info for this sequence
  
  return;
}

#################################################################
# Subroutine : output_one_target()
# Incept:      EPN, Tue Dec 13 15:30:12 2016
#
# Purpose:     Output information for current sequence in short 
#              and/or long mode (depending on whether $short_FH 
#              and $long_FH are defined or not).
#              
# Arguments: 
#   $short_FH:      file handle to output short output to (can be undef to not output short output)
#   $long_FH:       file handle to output long output to (can be undef to not output long output)
#   $opt_HHR:       reference to 2D hash of cmdline options
#   $use_evalues:  '1' if we have E-values, '0' if not
#   $width_HR:      hash, key is "model" or "target", value 
#                   is width (maximum length) of any target/model
#   $domain_HR:     reference to domain hash
#   $accept_HR:     reference to the 'accept' hash, key is "model"
#                   value is '1' if hits to model are "PASS"es '0'
#                   if they are "FAIL"s
#   $target:        target name
#   $seqidx:        index of target sequence
#   $seqlen:        length of target sequence
#   $nhits_HHR:     reference to hash of num hits per model (key 1), strand (key 2)
#   $nnts_HHR:      reference to hash of num nucleotides in all hits per model (key 1), strand (key 2)
#   $mdl_bd_HHAR:   reference to hash of hash of array of model boundaries per hits, per model (key 1), per strand (key 2)
#   $seq_bd_HHAR:   reference to hash of hash of array of sequence boundaries per hits, per model (key 1), per strand (key 2)
#   %one_model_HR:  'one' model
#   %one_score_HR:  'one' bit score
#   %one_evalue_HR: 'one' E-value
#   %one_start_HR:  'one' start position
#   %one_stop_HR:   'one' stop position
#   %one_strand_HR: 'one' strand 
#   %two_model_HR:  'two' model
#   %two_score_HR:  'two' bit score
#   %two_evalue_HR: 'two' E-value
#   %two_start_HR:  'two' start position
#   %two_stop_HR:   'two' stop position
#   %two_strand_HR: 'two' strand 
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_one_target { 
  my $nargs_expected = 26;
  my $sub_name = "output_one_target";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($short_FH, $long_FH, $opt_HHR, $use_evalues, $width_HR, $domain_HR, $accept_HR, $target, 
      $seqidx, $seqlen, $nhits_HHR, $nnts_HHR, $mdl_bd_HHAR, $seq_bd_HHAR, 
      $one_model_HR, $one_score_HR, $one_evalue_HR, $one_start_HR, $one_stop_HR, $one_strand_HR, 
      $two_model_HR, $two_score_HR, $two_evalue_HR, $two_start_HR, $two_stop_HR, $two_strand_HR) = @_;

  # debug_print(*STDOUT, "$target:$seqlen:one", $one_model_HR, $one_score_HR, $one_evalue_HR, $one_start_HR, $one_stop_HR, $one_strand_HR);
  # debug_print(*STDOUT, "$target:$seqlen:two", $two_model_HR, $two_score_HR, $two_evalue_HR, $two_start_HR, $two_stop_HR, $two_strand_HR);

  my $have_accurate_coverage = determine_if_coverage_is_accurate($opt_HHR);
  my $have_model_coords      = determine_if_we_have_model_coords($opt_HHR);

  # determine the winning family
  my $wfamily = undef;
  my $better_than_winning = 0;
  foreach my $family (keys %{$one_model_HR}) { 
    # determine if this hit is better than our winning clan
    if(! defined $wfamily) { 
      $better_than_winning = 1; 
    }
    elsif($use_evalues) { 
      if(($one_evalue_HR->{$family} < $one_evalue_HR->{$wfamily}) || # this E-value is better than (less than) our current winning E-value
         ($one_evalue_HR->{$family} eq $one_evalue_HR->{$wfamily} && $one_score_HR->{$family} > $one_score_HR->{$wfamily})) { # this E-value equals current 'one' E-value, but this score is better than current winning score
        $better_than_winning = 1;
      }
    }
    else { # we don't have E-values
      if($one_score_HR->{$family} > $one_score_HR->{$wfamily}) { # score is better than current winning score
        $better_than_winning = 1;
      }
    }
    if($better_than_winning) { 
      $wfamily = $family;
    }
  }
  my $nfams_fail_str = $wfamily; # used only if we FAIL because there's 
                                 # more than one hit to different families for this sequence
  my $nhits = $nhits_HHR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}};

  # determine if we have hits on both strands, and if so, build up failure string
  my $both_strands_fail_str = "";
  # add a '.' followed by <d>, where <d> is number of hits on opposite strand of best hit, if <d> > 0
  my $other_strand = ($one_strand_HR->{$wfamily} eq "+") ? "-" : "+";
  if(exists $nhits_HHR->{$one_model_HR->{$wfamily}}{$other_strand} && 
     $nhits_HHR->{$one_model_HR->{$wfamily}}{$other_strand} > 0) { 
    $nhits += $nhits_HHR->{$one_model_HR->{$wfamily}}{$other_strand};
    $both_strands_fail_str  = "hits_on_both_strands(" . $one_strand_HR->{$wfamily} . ":";
    $both_strands_fail_str .= $nhits_HHR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}} . "_hit(s)"; 
    if($have_accurate_coverage) { 
      $both_strands_fail_str .= "[" . $nnts_HHR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}} . "_nt]";
    }
    $both_strands_fail_str .= ";" . $other_strand . ":";
    $both_strands_fail_str .= $nhits_HHR->{$one_model_HR->{$wfamily}}{$other_strand} . "_hit(s)";
    if($have_accurate_coverage) { 
      $both_strands_fail_str .= "[" . $nnts_HHR->{$one_model_HR->{$wfamily}}{$other_strand} . "_nt])";
    }
  }

  # determine if we have hits that overlap on the model by more than maximum allowed amount
  my $duplicate_model_region_str = "";
  if($have_model_coords) { # we can only do this if search output included model coords
    $nhits = scalar(@{$mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}});
    my $noverlap_allowed = opt_Get("--maxoverlap", $opt_HHR);
    for(my $i = 0; $i < $nhits; $i++) { 
      for(my $j = $i+1; $j < $nhits; $j++) { 
        my $bd1 = $mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[$i];
        my $bd2 = $mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[$j];
        my ($noverlap, $overlap_str) = get_overlap($bd1, $bd2);
        if($noverlap > $noverlap_allowed) { 
          if($duplicate_model_region_str eq "") { 
            $duplicate_model_region_str .= "duplicate_model_region:"; 
          }
          else { 
            $duplicate_model_region_str .= ",";
          }
          $duplicate_model_region_str .= "(" . $overlap_str . ")_hits_" . ($i+1) . "_and_" . ($j+1) . "($bd1,$bd2)";
        }
      }
    }
  }
    
  # determine if hits are out of order between model and sequence
  my $out_of_order_str = "";
  if($have_model_coords) { # we can only do this if search output included model coords
    if($nhits > 1) { 
      my $i;
      my @seq_hit_order_A = (); # array of sequence boundary hit indices in sorted order [0..nhits-1] values are in range 1..nhits
      my @mdl_hit_order_A = (); # array of model    boundary hit indices in sorted order [0..nhits-1] values are in range 1..nhits
      my $seq_hit_order_str = sort_hit_array($seq_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}, \@seq_hit_order_A, 0); # 0 means duplicate values in first array are not allowed
      my $mdl_hit_order_str = sort_hit_array($mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}, \@mdl_hit_order_A, 1); # 1 means duplicate values in first array are allowed
      # check if the hits are out of order we don't just check for equality of the
      # two strings because it's possible (but rare) that there could be duplicates in the model
      # order array (but not in the sequence array), so we need to allow for that.
      my $out_of_order_flag = 0;
      for($i = 0; $i < $nhits; $i++) { 
        my $x = $mdl_hit_order_A[$i];
        my $y = $seq_hit_order_A[$i];
        # check to see if hit $i is same order in both mdl and seq coords
        # or if it is not, it's okay if it is identical to the one that is
        # example: 
        # hit 1 seq 1..10   model  90..99
        # hit 2 seq 11..20  model 100..110
        # hit 3 seq 21..30  model 100..110
        # seq order: 1,2,3
        # mdl order: 1,3,2 (or 1,2,3) we want both to be ok (not FAIL)
        if(($x ne $y) && # hits are not the same order
           ($mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[($x-1)] ne
            $mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[($y-1)])) { # hit is not identical to hit in correct order
          $out_of_order_flag = 1;
        }
      }
      if($out_of_order_flag) { 
        $out_of_order_str = "inconsistent_hit_order:seq_order(" . $seq_hit_order_str . "[";
        for($i = 0; $i < $nhits; $i++) { 
          $out_of_order_str .= $seq_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[$i]; 
          if($i < ($nhits-1)) { $out_of_order_str .= ","; }
        }
        $out_of_order_str .= "]),mdl_order(" . $mdl_hit_order_str . "[";
        for($i = 0; $i < $nhits; $i++) { 
          $out_of_order_str .= $mdl_bd_HHAR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}}[$i]; 
          if($i < ($nhits-1)) { $out_of_order_str .= ","; }
        }
        $out_of_order_str .= "])";
      }
    }
  }

  my $nnts  = $nnts_HHR->{$one_model_HR->{$wfamily}}{$one_strand_HR->{$wfamily}};
  # build up 'other_hits_string' string about other hits in other clans, if any
  my $other_hits_string = "";
  my $nfams = 1;
  foreach my $family (keys %{$one_model_HR}) { 
    if($family ne $wfamily) { 
      if(exists($one_model_HR->{$family})) { 
        if($other_hits_string ne "") { $other_hits_string .= ","; }
        if($use_evalues) { 
          $other_hits_string .= sprintf("%s:%s:%g:%.1f/%d-%d:%s",
                                   $family, $one_model_HR->{$family}, $one_evalue_HR->{$family}, $one_score_HR->{$family}, 
                                   $one_start_HR->{$family}, $one_stop_HR->{$family}, $one_strand_HR->{$family});
        }
        else { # we don't have E-values
          $other_hits_string .= sprintf("%s:%s:%.1f/%d-%d:%s",
                                   $family, $one_model_HR->{$family}, $one_score_HR->{$family}, 
                                   $one_start_HR->{$family}, $one_stop_HR->{$family}, $one_strand_HR->{$family});
        }
        $nfams++;
        $nfams_fail_str .= "+" . $family;
      }
    }
  }
  if(! defined $wfamily) { die "ERROR wfamily undefined for $target"; }
  my $best_coverage = (abs($one_stop_HR->{$wfamily} - $one_start_HR->{$wfamily}) + 1) / $seqlen;
  my $tot_coverage  = $nnts / $seqlen;
  my $one_evalue2print = ($use_evalues) ? sprintf("%8g  ", $one_evalue_HR->{$wfamily}) : "";
  my $two_evalue2print = undef;
  if(defined $two_model_HR->{$wfamily}) { 
    $two_evalue2print = ($use_evalues) ? sprintf("%8g  ", $two_evalue_HR->{$wfamily}) : "";
  }
  
  # if we have a second-best model, determine score difference between best and second-best model
  my $do_ppos_score_diff = 1; # true unless --absdiff option used
  if(opt_IsUsed("--absdiff", $opt_HHR)) { 
    $do_ppos_score_diff = 0;
  }
  my $score_total_diff = undef; # score total difference 
  my $score_ppos_diff  = undef; # score per position difference 
  my $diff_low_thresh  = undef; # bit score difference for 'low difference' warning/failure
  my $diff_vlow_thresh = undef; # bit score difference for 'very low difference 'warning/failure
  my $diff_low_str     = undef; # string that explains low bit score difference warning/failure
  my $diff_vlow_str    = undef; # string that explains very low bit score difference warning/failure

  if(exists $two_score_HR->{$wfamily}) { 
    # determine score difference threshold
    $score_total_diff = ($one_score_HR->{$wfamily} - $two_score_HR->{$wfamily});
    $score_ppos_diff  = $score_total_diff / abs($one_stop_HR->{$wfamily} - $one_start_HR->{$wfamily});
    if($do_ppos_score_diff) { 
      # default: per position score difference, dependent on length of hit
      $diff_low_thresh  = opt_Get("--lowpdiff",  $opt_HHR);
      $diff_vlow_thresh = opt_Get("--vlowpdiff", $opt_HHR);
      $diff_low_str     = $diff_low_thresh . "_bits_per_posn";
      $diff_vlow_str    = $diff_vlow_thresh . "_bits_per_posn";
    }
    else { 
      # absolute score difference, regardless of length of hit
      $diff_low_thresh  = opt_Get("--lowadiff", $opt_HHR); 
      $diff_vlow_thresh = opt_Get("--vlowadiff", $opt_HHR); 
      $diff_low_str     = $diff_low_thresh . "_total_bits";
      $diff_vlow_str    = $diff_vlow_thresh . "_total_bits";
    }
  }

  # Determine if there are any unusual features 
  # and if the sequence PASSes or FAILs.
  # 
  # Possible unusual feature criteria are listed below. 
  # A FAILure occurs if either the criteria is a strict failure criteria
  # or if it is a optional criteria and the relevant command line option is used.
  # 
  # Four strict failure criteria:
  # - no hits (THIS WILL NEVER HAPPEN HERE, THEY'RE HANDLED BY output_one_hitless_target())
  # - number of hits to different families is higher than one (e.g. SSU and LSU hit)
  # - hits to best model on both strands 
  # - hits overlap on model (duplicate model region)
  # 
  # Optional failure criteria, require a specific command line option to cause a failure
  #  but always get printed to unusual_features columns)
  # - winning hit is to unacceptable model (requires --inaccept to FAIL or get reported)
  # - hit is on minus strand (requires --minusfail to FAIL, always reported))
  # - low score, bits per position below threshold (requires --
  # - low coverage (requires --covfail)
  # - score difference between top two models is below $diff_thresh (requires --difffail)
  # - number of this to best model is > 1 (requires --multfail)
  # 
  my $pass_fail = "PASS";
  my $unusual_features = "";

  # check/enforce strict failure criteria
  # hits to more than one family?
  if($nfams > 1) { 
    $pass_fail = "FAIL";
    if($unusual_features ne "") { $unusual_features .= ";"; }
    $unusual_features .= "*hits_to_more_than_one_family($nfams_fail_str);other_family_hits:$other_hits_string";
  }
  # hits on both strands to best model?
  if($both_strands_fail_str ne "") { 
    $pass_fail = "FAIL";
    if($unusual_features ne "") { $unusual_features .= ";"; }
    $unusual_features .= "*" . $both_strands_fail_str;
  }    
  # duplicate model region
  if($duplicate_model_region_str ne "") { 
    $pass_fail = "FAIL";
    if($unusual_features ne "") { $unusual_features .= ";"; }
    $unusual_features .= "*" . $duplicate_model_region_str;
  }    
  if($out_of_order_str ne "") { 
    $pass_fail = "FAIL";
    if($unusual_features ne "") { $unusual_features .= ";"; }
    $unusual_features .= "*" . $out_of_order_str;
  }

  # check/enforce optional failure criteria
  # determine if the sequence hits to an unacceptable model
  if($accept_HR->{$one_model_HR->{$wfamily}} != 1) { 
    $pass_fail = "FAIL";
    $unusual_features .= "*unacceptable_model"
  }
  # determine if sequence is on opposite strand
  if($one_strand_HR->{$wfamily} eq "-") { 
    if($unusual_features ne "") { $unusual_features .= ";"; }
    if(opt_Get("--minusfail", $opt_HHR)) { 
      $pass_fail = "FAIL";
      $unusual_features .= "*";
    }
    $unusual_features .= "opposite_strand";
  }
  # determine if the sequence has a 'low_score'
  # it does if bits per position (of entire sequence not just hit)
  # is below the threshold (--lowppossc) minimum
  my $bits_per_posn = $one_score_HR->{$wfamily} / $seqlen;
  if($bits_per_posn < opt_Get("--lowppossc", $opt_HHR)) { 
    if($unusual_features ne "") { $unusual_features .= ";"; }
    if(opt_Get("--scfail", $opt_HHR)) { 
      $pass_fail = "FAIL";
      $unusual_features .= "*";
    }
    $unusual_features .= sprintf("low_score_per_posn(%.2f<%.2f)", $bits_per_posn, opt_Get("--lowppossc", $opt_HHR));
  }
  # determine if coverage is low
  if($tot_coverage < opt_Get("--tcov", $opt_HHR)) { 
    if($unusual_features ne "") { $unusual_features .= ";"; }
    if(opt_Get("--covfail", $opt_HHR)) { 
      $pass_fail = "FAIL";
      $unusual_features .= "*";
    }
    $unusual_features .= sprintf("low_total_coverage(%.3f<%.3f)", $tot_coverage, opt_Get("--tcov", $opt_HHR));
  }
  # determine if the sequence has a low score difference between the top
  # two domains
  if(exists $two_score_HR->{$wfamily}) { 
    # determine score difference threshold
    $score_total_diff = ($one_score_HR->{$wfamily} - $two_score_HR->{$wfamily});
    $score_ppos_diff  = $score_total_diff / abs($one_stop_HR->{$wfamily} - $one_start_HR->{$wfamily});
    if($do_ppos_score_diff) { 
      # default: per position score difference, dependent on length of hit
      $diff_vlow_thresh = opt_Get("--vlowpdiff", $opt_HHR);
      $diff_low_thresh  = opt_Get("--lowpdiff",  $opt_HHR);
      if($score_ppos_diff < $diff_vlow_thresh) { 
        if($unusual_features ne "") { $unusual_features .= ";"; }
        if(opt_Get("--difffail", $opt_HHR)) { 
          $pass_fail = "FAIL"; 
          $unusual_features .= "*";
        }
        $unusual_features .= sprintf("very_low_score_difference_between_top_two_%s(%.3f<%.3f_bits_per_posn)", (opt_Get("--samedomain", $opt_HHR) ? "models" : "domains"), $score_ppos_diff, $diff_vlow_thresh);
      }
      elsif($score_ppos_diff < $diff_low_thresh) { 
        if($unusual_features ne "") { $unusual_features .= ";"; }
        if(opt_Get("--difffail", $opt_HHR)) { 
          $pass_fail = "FAIL"; 
          $unusual_features .= "*";
        }
        $unusual_features .= sprintf("low_score_difference_between_top_two_%s(%.3f<%.3f_bits_per_posn)", (opt_Get("--samedomain", $opt_HHR) ? "models" : "domains"), $score_ppos_diff, $diff_low_thresh);
      }
    }
    else { 
      # absolute score difference, regardless of length of hit
      $diff_vlow_thresh = opt_Get("--vlowadiff", $opt_HHR);
      $diff_low_thresh  = opt_Get("--lowadiff",  $opt_HHR);
      if($score_total_diff < $diff_vlow_thresh) { 
        if($unusual_features ne "") { $unusual_features .= ";"; }
        if(opt_Get("--difffail", $opt_HHR)) { 
          $pass_fail = "FAIL"; 
          $unusual_features .= "*";
        }
        $unusual_features .= sprintf("very_low_score_difference_between_top_two_%s(%.3f<%.3f_total_bits)", (opt_Get("--samedomain", $opt_HHR) ? "models" : "domains"), $score_total_diff, $diff_vlow_thresh);
      }
      elsif($score_total_diff < $diff_low_thresh) { 
        if($unusual_features ne "") { $unusual_features .= ";"; }
        if(opt_Get("--difffail", $opt_HHR)) { 
          $pass_fail = "FAIL"; 
          $unusual_features .= "*";
        }
        $unusual_features .= sprintf("low_score_difference_between_top_two_%s(%.3f<%.3f_total_bits)", (opt_Get("--samedomain", $opt_HHR) ? "models" : "domains"), $score_total_diff, $diff_low_thresh);
      }
    }
  }
  # determine if there are more than one hit to the best model
  if($nhits > 1) {
    if($unusual_features ne "") { $unusual_features .= ";"; }
    if(opt_Get("--multfail", $opt_HHR)) { 
      $pass_fail = "FAIL";
      $unusual_features .= "*";
    }
    $unusual_features .= "multiple_hits_to_best_model($nhits)";
  }
  if($unusual_features eq "") { $unusual_features = "-"; }


  if(defined $short_FH) { 
    printf $short_FH ("%-*s  %-*s  %-*s  %-5s  %s  %s\n", 
                      $width_HR->{"index"}, $seqidx,
                      $width_HR->{"target"}, $target, 
                      $width_HR->{"classification"}, $wfamily . "." . $domain_HR->{$one_model_HR->{$wfamily}}, 
                      ($one_strand_HR->{$wfamily} eq "+") ? "plus" : "minus", 
                      $pass_fail, $unusual_features);
  }
  if(defined $long_FH) { 
    printf $long_FH ("%-*s  %-*s  %4s  %*d  %3d  %-*s  %-*s  %-*s  %-5s  %6.1f  %4.2f  %s%3d  %5.3f  %5.3f  %*d  %*d  ", 
                     $width_HR->{"index"}, $seqidx,
                     $width_HR->{"target"}, $target, 
                     $pass_fail, 
                     $width_HR->{"length"}, $seqlen, 
                     $nfams, 
                     $width_HR->{"family"}, $wfamily, 
                     $width_HR->{"domain"}, $domain_HR->{$one_model_HR->{$wfamily}}, 
                     $width_HR->{"model"}, $one_model_HR->{$wfamily}, 
                     ($one_strand_HR->{$wfamily} eq "+") ? "plus" : "minus", 
                     $one_score_HR->{$wfamily}, 
                     $bits_per_posn, 
                     $one_evalue2print, 
                     $nhits, 
                     $tot_coverage, 
                     $best_coverage, 
                     $width_HR->{"length"}, $one_start_HR->{$wfamily}, 
                     $width_HR->{"length"}, $one_stop_HR->{$wfamily});
    
    if(defined $two_model_HR->{$wfamily}) { 
      printf $long_FH ("%6.1f  %-*s  %6.1f  %s", 
                       $one_score_HR->{$wfamily} - $two_score_HR->{$wfamily}, 
                       $width_HR->{"model"}, $two_model_HR->{$wfamily}, 
                       $two_score_HR->{$wfamily},
                       $two_evalue2print);
    }
    else { 
      printf $long_FH ("%6s  %-*s  %6s  %s", 
                       "-" , 
                       $width_HR->{"model"}, "-", 
                       "-", 
                       ($use_evalues) ? "       -  " : "");
    }
    
    if($unusual_features eq "") { 
      $unusual_features = "-";
    }
    
    print $long_FH ("$unusual_features\n");
  }

  return;
}

#################################################################
# Subroutine : output_one_hitless_target()
# Incept:      EPN, Thu Mar  2 11:37:13 2017
#
# Purpose:     Output information for current sequence with zero
#              hits in either long or short mode. Short mode if 
#              $do_short is true.
#              
# Arguments: 
#   $FH:            file handle to output to
#   $do_short:      TRUE to output in 'short' concise mode, else do long mode
#   $opt_HHR:       reference to 2D hash of cmdline options
#   $width_HR:      hash, key is "model" or "target", value 
#                   is width (maximum length) of any target/model
#   $target:        target name
#   $seqidx:        index of target sequence
#   $seqlen:        length of target sequence
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_one_hitless_target { 
  my $nargs_expected = 7;
  my $sub_name = "output_one_hitless_target";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $do_short, $opt_HHR, $width_HR, $target, $seqidx, $seqlen) = @_;

  my $pass_fail = "FAIL";
  my $unusual_features = "*no_hits";
  my $nfams = 0;
  my $nhits = 0;

  my $use_evalues = opt_Get("--evalues", $opt_HHR);

  if($do_short) { 
    printf $FH ("%-*s  %-*s  %-*s  %5s  %s  %s\n", 
                $width_HR->{"index"}, $seqidx,
                $width_HR->{"target"}, $target, 
                $width_HR->{"classification"}, "-",
                "-", $pass_fail, $unusual_features);
  }
  else { 
    printf $FH ("%-*s  %-*s  %4s  %*d  %3d  %-*s  %-*s  %-*s  %-5s  %6s  %4s  %s%3s  %5s  %5s  %*s  %*s  ", 
                $width_HR->{"index"}, $seqidx,
                $width_HR->{"target"}, $target, 
                $pass_fail, 
                $width_HR->{"length"}, $seqlen, 
                $nfams,
                $width_HR->{"family"}, "-",
                $width_HR->{"domain"}, "-", 
                $width_HR->{"model"}, "-", 
                "-", 
                "-", 
                "-",
                ($use_evalues) ? "       -  " : "",
                "-",
                "-",
                "-", 
                $width_HR->{"length"}, "-", 
                $width_HR->{"length"}, "-");
    printf $FH ("%6s  %-*s  %6s  %s%s\n", 
                "-" , 
                $width_HR->{"model"}, "-", 
                "-", 
                ($use_evalues) ? "       -  " : "", $unusual_features);
    
  }
  return;
}

#################################################################
# Subroutine : output_short_headers()
# Incept:      EPN, Fri Dec 30 08:51:01 2016
#
# Purpose:     Output column headers to the short output file.
#              
# Arguments: 
#   $FH:        file handle to output to
#   $width_HR:  maximum length of any target name
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_short_headers { 
  my $nargs_expected = 2;
  my $sub_name = "output_short_headers";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $width_HR) = (@_);

  my $index_dash_str  = "#" . get_monocharacter_string($width_HR->{"index"}-1, "-");
  my $target_dash_str = get_monocharacter_string($width_HR->{"target"}, "-");
  my $class_dash_str  = get_monocharacter_string($width_HR->{"classification"}, "-");

  printf $FH ("%-*s  %-*s  %-*s  %5s  %4s  %s\n", 
              $width_HR->{"index"}, "#idx", 
              $width_HR->{"target"}, "target", 
              $width_HR->{"classification"}, "classification", 
              "strnd", "p/f", "unexpected_features");
  printf $FH ("%-*s  %-*s  %-*s  %3s  %4s  %s\n", 
              $width_HR->{"index"},          $index_dash_str, 
              $width_HR->{"target"},         $target_dash_str, 
              $width_HR->{"classification"}, $class_dash_str, 
              "-----", "----", "-------------------");
  return;
}

#################################################################
# Subroutine : output_long_headers()
# Incept:      EPN, Fri Dec 30 08:51:01 2016
#
# Purpose:     Output column headers to the long output file.
#              
# Arguments: 
#   $FH:        file handle to output to
#   $opt_HHR:   ref to 2D options hash
#   $width_HR:  ref to hash, key is "model" or "target", value 
#               is width (maximum length) of any target/model
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_long_headers { 
  my $nargs_expected = 3;
  my $sub_name = "output_long_headers";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $opt_HHR, $width_HR) = (@_);

  my $index_dash_str   = "#" . get_monocharacter_string($width_HR->{"index"}-1, "-");
  my $target_dash_str  = get_monocharacter_string($width_HR->{"target"}, "-");
  my $model_dash_str   = get_monocharacter_string($width_HR->{"model"},  "-");
  my $family_dash_str  = get_monocharacter_string($width_HR->{"family"}, "-");
  my $domain_dash_str  = get_monocharacter_string($width_HR->{"domain"}, "-");
  my $length_dash_str  = get_monocharacter_string($width_HR->{"length"}, "-");

  my $use_evalues = opt_Get("--evalues", $opt_HHR);

  my $best_model_group_width   = $width_HR->{"model"} + 2 + 6 + 2 + 4 + 2 + 3 + 2 + 5 + 2 + 5 + 2 + 5 + 2 + $width_HR->{"length"} + 2 + $width_HR->{"length"};
  my $second_model_group_width = $width_HR->{"model"} + 2 + 6 ;
  if($use_evalues) { 
    $best_model_group_width   += 2 + 8;
    $second_model_group_width += 2 + 8;
  }

  if(length("best-scoring model")               > $best_model_group_width)   { $best_model_group_width   = length("best-scoring model"); }
  if(opt_Get("--samedomain", $opt_HHR)) { 
    if(length("second best-scoring model") > $second_model_group_width) { $second_model_group_width = length("second best-scoring model"); } 
  }
  else { 
    if(length("different domain's best-scoring model") > $second_model_group_width) { $second_model_group_width = length("different domain's best-scoring model"); } 
  }

  my $best_model_group_dash_str   = get_monocharacter_string($best_model_group_width, "-");
  my $second_model_group_dash_str = get_monocharacter_string($second_model_group_width, "-");
  
  # line 1
  printf $FH ("%-*s  %-*s  %4s  %*s  %3s  %*s  %*s  %-*s  %6s  %-*s  %s\n", 
              $width_HR->{"index"},  "#",
              $width_HR->{"target"}, "",
              "", 
              $width_HR->{"length"}, "", 
              "", 
              $width_HR->{"family"}, "", 
              $width_HR->{"domain"}, "", 
              $best_model_group_width, center_string($best_model_group_width, "best-scoring model"), 
              "", 
              $second_model_group_width, center_string($second_model_group_width, (opt_Get("--samedomain", $opt_HHR)) ? "second best-scoring model" : "different domain's best-scoring model"), 
              "");
  # line 2
  printf $FH ("%-*s  %-*s  %4s  %*s  %3s  %*s  %*s  %-*s  %6s  %-*s  %s\n", 
              $width_HR->{"index"},  "#",
              $width_HR->{"target"}, "",
              "", 
              $width_HR->{"length"}, "", 
              "", 
              $width_HR->{"family"}, "", 
              $width_HR->{"domain"}, "", 
              $best_model_group_width, $best_model_group_dash_str, 
              "", 
              $second_model_group_width, $second_model_group_dash_str, 
              "");
  # line 3
  printf $FH ("%-*s  %-*s  %4s  %*s  %3s  %-*s  %-*s  %-*s  %5s  %6s  %s%4s  %3s  %5s  %5s  %*s  %*s  %6s  %-*s  %6s  %s%s\n",  
              $width_HR->{"index"},  "#idx", 
              $width_HR->{"target"}, "target",
              "p/f", 
              $width_HR->{"length"}, "length", 
              "#fm", 
              $width_HR->{"family"}, "fam", 
              $width_HR->{"domain"}, "domain", 
              $width_HR->{"model"},  "model", 
              "strnd",
              "score", 
              ($use_evalues) ? "  evalue  " : "", 
              "b/nt",
              "#ht", 
              "tcov",
              "bcov",
              $width_HR->{"length"}, "bstart",
              $width_HR->{"length"}, "bstop",
              "scdiff",
              $width_HR->{"model"},  "model", 
              "score", 
              ($use_evalues) ? "  evalue  " : "", 
              "unexpected_features");

  # line 4
  printf $FH ("%-*s  %-*s  %4s  %*s  %3s  %*s  %*s  %-*s  %5s  %6s  %s%4s  %3s  %5s  %5s  %*s  %*s  %6s  %-*s  %6s  %s%s\n", 
              $width_HR->{"index"},  $index_dash_str,
              $width_HR->{"target"}, $target_dash_str, 
              "----", 
              $width_HR->{"length"}, $length_dash_str,
              "---", 
              $width_HR->{"family"}, $family_dash_str,
              $width_HR->{"domain"}, $domain_dash_str, 
              $width_HR->{"model"},  $model_dash_str,
              "-----", 
              "------", 
              ($use_evalues) ? "--------  " : "",
              "----",
              "---",
              "-----",
              "-----",
              $width_HR->{"length"}, $length_dash_str,
              $width_HR->{"length"}, $length_dash_str,
              "------", 
              $width_HR->{"model"},  $model_dash_str, 
              "------", 
              ($use_evalues) ? "--------  " : "",
              "-------------------");
  return;
}

#################################################################
# Subroutine : output_short_tail()
# Incept:      EPN, Thu Feb 23 15:29:21 2017
#
# Purpose:     Output explanation of columns to short output file.
#              
# Arguments: 
#   $FH:       file handle to output to
#   $opt_HHR:  reference to options 2D hash
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_short_tail { 
  my $nargs_expected = 2;
  my $sub_name = "output_short_tail";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $opt_HHR) = (@_);

  printf $FH ("#\n");
  printf $FH ("# Explanation of columns:\n");
  printf $FH ("#\n");
  printf $FH ("# Column 1 [idx]:                 index of sequence in input sequence file\n");
  printf $FH ("# Column 2 [target]:              name of target sequence\n");
  printf $FH ("# Column 3 [classification]:      classification of sequence\n");
  printf $FH ("# Column 4 [strnd]:               strand ('plus' or 'minus') of best-scoring hit\n");
#  printf $FH ("# Column 5 [p/f]:                 PASS or FAIL (see below for more on FAIL)\n");
  printf $FH ("# Column 5 [p/f]:                 PASS or FAIL\n");
#  printf $FH ("# Column 6 [unexpected_features]: unexpected/unusual features of sequence (see below for more)\n");
  printf $FH ("# Column 6 [unexpected_features]: unexpected/unusual features of sequence (see 00README.txt)\n");
  
  output_unexpected_features_explanation($FH, $opt_HHR);

  return;
}


#################################################################
# Subroutine : output_long_tail()
# Incept:      EPN, Thu Feb 23 15:33:25 2017
#
# Purpose:     Output explanation of columns to long output file.
#              
# Arguments: 
#   $FH:       file handle to output to
#   $opt_HHR:  reference to options 2D hash
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_long_tail { 
  my $nargs_expected = 2;
  my $sub_name = "output_long_tail";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $opt_HHR) = (@_);

  my $use_evalues = opt_Get("--evalues", $opt_HHR);
  my $have_accurate_coverage = determine_if_coverage_is_accurate($opt_HHR);

  my $inaccurate_cov_str = ("#                                  (these values are inaccurate, run with --hmm or --slow to get accurate coverage)\n");

  my $column_ct = 1;

  printf $FH ("#\n");
  printf $FH ("# Explanation of columns:\n");
  printf $FH ("#\n");
  printf $FH ("# Column %2d [idx]:                 index of sequence in input sequence file\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [target]:              name of target sequence\n", $column_ct); 
  $column_ct++;
  printf $FH ("# Column %2d [p/f]:                 PASS or FAIL (see below for more on FAIL)\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [length]:              length of target sequence (nt)\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [#fm]:                 number of different families detected in sequence\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [fam]:                 name of family the best-scoring model to this sequence belongs to\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [domain]:              name of domain the best-scoring model to this sequence belongs to\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [model]:               name of best-scoring model\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [strnd]:               strand ('plus' or 'minus') of best-scoring hit\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [score]:               bit score of best-scoring hit to this sequence\n", $column_ct);
  $column_ct++;
  if($use_evalues) { 
    printf $FH ("# Column %2d [evalue]:              E-value of best-scoring hit to this sequence\n", $column_ct);
    $column_ct++;
  }
  printf $FH ("# Column %2d [b/nt]:                bits per nucleotide (bits/hit_length) of best-scoring hit to this sequence\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [#ht]:                 number of hits of best-scoring model to this sequence (no threshold enforced)\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [tcov]:                fraction of target sequence included in all (non-overlapping) hits to the best-scoring model\n", $column_ct);
  if(! $have_accurate_coverage) { print $FH $inaccurate_cov_str; }
  $column_ct++;
  printf $FH ("# Column %2d [bcov]:                fraction of target sequence included in single best-scoring hit\n", $column_ct);
  if(! $have_accurate_coverage) { print $FH $inaccurate_cov_str; }
  $column_ct++;
  printf $FH ("# Column %2d [bstart]:              start position of best-scoring hit\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [bstop]:               stop position of best-scoring hit\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [scdiff]:              difference in score between top scoring hit in best model and top scoring hit in second best model\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [model]:               name of second best-scoring model\n", $column_ct);
  $column_ct++;
  printf $FH ("# Column %2d [score]:               bit score of best-scoring hit to this sequence\n", $column_ct);
  $column_ct++;
  if($use_evalues) { 
    printf $FH ("# Column %2d [evalue]:              E-value of best-scoring hit to this sequence\n", $column_ct);
    $column_ct++;
  }
#  printf $FH ("# Column %2d [unexpected_features]: unusual/unexpected features of sequence (see below for more)\n", $column_ct);
  printf $FH ("# Column %2d [unexpected_features]: unexpected/unusual features of sequence (see 00README.txt)\n", $column_ct);
  $column_ct++;
  
  output_unexpected_features_explanation($FH, $opt_HHR);

  return;
}


#################################################################
# Subroutine : output_unexpected_features_explanation()
# Incept:      EPN, Tue Mar 28 15:29:10 2017
#
# Purpose:     Output explanation of possible unexpected features.
#              
# Arguments: 
#   $FH:       file handle to output to
#   $opt_HHR:  reference to options 2D hash
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub output_unexpected_features_explanation { 
  my $nargs_expected = 2;
  my $sub_name = "output_unexpected_features_explanation";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $opt_HHR) = (@_);

#  print $FH ("#\n");
#  print $FH ("# Explanation of possible values in unexpected_features column:\n");
#  print $FH ("#\n");
#  print $FH ("# This column will include a '-' if none of the features listed below are detected.\n");
#  print $FH ("# Or it will contain one or more of the following types of messages. There are no\n");
#  print $FH ("# whitespaces in this field, instead underscore '_' are used to make parsing easier.\n");
#  print $FH ("#\n");
#  print $FH ("# There are two types of unexpected features: those that cause a sequence to FAIL and\n");
#  print $FH ("# those that do not\n");
#  print $FH ("# Unexpected features There are two types of unexpected features: those that cause a sequence to FAIL and\n");
#  print $FH ("# those that do not\n");

  return;
}


#####################################################################
# Subroutine: output_banner()
# Incept:     EPN, Thu Oct 30 09:43:56 2014 (rnavore)
# 
# Purpose:    Output the banner with info on the script, input arguments
#             and options used.
#
# Arguments: 
#    $FH:                file handle to print to
#    $version:           version of dnaorg
#    $releasedate:       month/year of version (e.g. "Feb 2016")
#    $synopsis:          string reporting the date
#    $date:              date information to print
#
# Returns:    Nothing, if it returns, everything is valid.
# 
# Dies: never
####################################################################
sub output_banner {
  my $nargs_expected = 5;
  my $sub_name = "outputBanner()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($FH, $version, $releasedate, $synopsis, $date) = @_;

  print $FH ("\# $synopsis\n");
  print $FH ("\# ribotyper $version ($releasedate)\n");
#  print $FH ("\# Copyright (C) 2014 HHMI Janelia Research Campus\n");
#  print $FH ("\# Freely distributed under the GNU General Public License (GPLv3)\n");
  print $FH ("\# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n");
  if(defined $date)    { print $FH ("# date:    $date\n"); }
  printf $FH ("#\n");

  return;
}
#################################################################
# Subroutine : output_progress_prior()
# Incept:      EPN, Fri Feb 12 17:22:24 2016 [dnaorg.pm]
#
# Purpose:      Output to $FH1 (and possibly $FH2) a message indicating
#               that we're about to do 'something' as explained in
#               $outstr.  
#
#               Caller should call *this* function, then do
#               the 'something', then call output_progress_complete().
#
#               We return the number of seconds since the epoch, which
#               should be passed into the downstream
#               output_progress_complete() call if caller wants to
#               output running time.
#
# Arguments: 
#   $outstr:     string to print to $FH
#   $progress_w: width of progress messages
#   $FH1:        file handle to print to, can be undef
#   $FH2:        another file handle to print to, can be undef
# 
# Returns:     Number of seconds and microseconds since the epoch.
#
################################################################# 
sub output_progress_prior { 
  my $nargs_expected = 4;
  my $sub_name = "output_progress_prior()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($outstr, $progress_w, $FH1, $FH2) = @_;

  if(defined $FH1) { printf $FH1 ("# %-*s ... ", $progress_w, $outstr); }
  if(defined $FH2) { printf $FH2 ("# %-*s ... ", $progress_w, $outstr); }

  return seconds_since_epoch();
}

#################################################################
# Subroutine : output_progress_complete()
# Incept:      EPN, Fri Feb 12 17:28:19 2016 [dnaorg.pm]
#
# Purpose:     Output to $FH1 (and possibly $FH2) a 
#              message indicating that we've completed 
#              'something'.
#
#              Caller should call *this* function,
#              after both a call to output_progress_prior()
#              and doing the 'something'.
#
#              If $start_secs is defined, we determine the number
#              of seconds the step took, output it, and 
#              return it.
#
# Arguments: 
#   $start_secs:    number of seconds either the step took
#                   (if $secs_is_total) or since the epoch
#                   (if !$secs_is_total)
#   $extra_desc:    extra description text to put after timing
#   $FH1:           file handle to print to, can be undef
#   $FH2:           another file handle to print to, can be undef
# 
# Returns:     Number of seconds the step took (if $secs is defined,
#              else 0)
#
################################################################# 
sub output_progress_complete { 
  my $nargs_expected = 4;
  my $sub_name = "output_progress_complete()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($start_secs, $extra_desc, $FH1, $FH2) = @_;

  my $total_secs = undef;
  if(defined $start_secs) { 
    $total_secs = seconds_since_epoch() - $start_secs;
  }

  if(defined $FH1) { printf $FH1 ("done."); }
  if(defined $FH2) { printf $FH2 ("done."); }

  if(defined $total_secs || defined $extra_desc) { 
    if(defined $FH1) { printf $FH1 (" ["); }
    if(defined $FH2) { printf $FH2 (" ["); }
  }
  if(defined $total_secs) { 
    if(defined $FH1) { printf $FH1 (sprintf("%.1f seconds%s", $total_secs, (defined $extra_desc) ? ", " : "")); }
    if(defined $FH2) { printf $FH2 (sprintf("%.1f seconds%s", $total_secs, (defined $extra_desc) ? ", " : "")); }
  }
  if(defined $extra_desc) { 
    if(defined $FH1) { printf $FH1 $extra_desc };
    if(defined $FH2) { printf $FH2 $extra_desc };
  }
  if(defined $total_secs || defined $extra_desc) { 
    if(defined $FH1) { printf $FH1 ("]"); }
    if(defined $FH2) { printf $FH2 ("]"); }
  }

  if(defined $FH1) { printf $FH1 ("\n"); }
  if(defined $FH2) { printf $FH2 ("\n"); }
  
  return (defined $total_secs) ? $total_secs : 0.;
}

#################################################################
# Subroutine:  run_command()
# Incept:      EPN, Mon Dec 19 10:43:45 2016
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
    print ("Running cmd: $cmd\n"); 
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

#################################################################
# Subroutine : seconds_since_epoch()
# Incept:      EPN, Sat Feb 13 06:17:03 2016
#
# Purpose:     Return the seconds and microseconds since the 
#              Unix epoch (Jan 1, 1970) using 
#              Time::HiRes::gettimeofday().
#
# Arguments:   NONE
# 
# Returns:     Number of seconds and microseconds
#              since the epoch.
#
################################################################# 
sub seconds_since_epoch { 
  my $nargs_expected = 0;
  my $sub_name = "seconds_since_epoch()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($seconds, $microseconds) = gettimeofday();
  return ($seconds + ($microseconds / 1000000.));
}


#################################################################
# Subroutine : debug_print()
# Incept:      EPN, Thu Jan  5 14:11:21 2017
#
# Purpose:     Output information for current sequence in either
#              long or short mode. Short mode if $do_short is true.
#              
# Arguments: 
#   $FH:            file handle to output to
#   $title:         title to print before any values
#   %model_HR:  'one' model
#   %score_HR:  'one' bit score
#   %evalue_HR: 'one' E-value
#   %start_HR:  'one' start position
#   %stop_HR:   'one' stop position
#   %strand_HR: 'one' strand 
#
# Returns:     Nothing.
# 
# Dies:        Never.
#
################################################################# 
sub debug_print { 
  my $nargs_expected = 8;
  my $sub_name = "debug_print";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($FH, $title, $model_HR, $score_HR, $evalue_HR, $start_HR, $stop_HR, $strand_HR) = @_;

  printf $FH ("************************************************************\n");
  printf $FH ("in $sub_name, title: $title\n");

  foreach my $family (sort keys %{$model_HR}) { 
    printf("family: $family\n");
    printf("\tmodel:  $model_HR->{$family}\n");
    printf("\tscore:  $score_HR->{$family}\n");
    printf("\tevalue: $evalue_HR->{$family}\n");
    printf("\tstart:  $start_HR->{$family}\n");
    printf("\tstop:   $stop_HR->{$family}\n");
    printf("\tstrand: $strand_HR->{$family}\n");
    printf("--------------------------------\n");
  }

  return;
}

#################################################################
# Subroutine: get_monocharacter_string()
# Incept:     EPN, Thu Mar 10 21:02:35 2016 [dnaorg.pm]
#
# Purpose:    Return a string of length $len of repeated instances
#             of the character $char.
#
# Arguments:
#   $len:   desired length of the string to return
#   $char:  desired character
#
# Returns:  A string of $char repeated $len times.
# 
# Dies:     if $len is not a positive integer
#
#################################################################
sub get_monocharacter_string {
  my $sub_name = "get_monocharacter_string";
  my $nargs_expected = 2;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($len, $char) = @_;

  if(! verify_integer($len)) { 
    die "ERROR in $sub_name, passed in length ($len) is not a non-negative integer";
  }
  if($len < 0) { 
    die "ERROR in $sub_name, passed in length ($len) is a negative integer";
  }
    
  my $ret_str = "";
  for(my $i = 0; $i < $len; $i++) { 
    $ret_str .= $char;
  }

  return $ret_str;
}

#################################################################
# Subroutine: center_string()
# Incept:     EPN, Thu Mar  2 10:01:39 2017
#
# Purpose:    Given a string and width, return the string with
#             prepended spaces (" ") so that the returned string
#             will be roughly centered in a window of length 
#             $width.
#
# Arguments:
#   $width:  width to center in
#   $str:    string to center
#
# Returns:  $str prepended with spaces so that it centers
# 
# Dies:     Never
#
#################################################################
sub center_string { 
  my $sub_name = "center_string";
  my $nargs_expected = 2;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($width, $str) = @_;

  my $nspaces_to_prepend = int(($width - length($str)) / 2);
  if($nspaces_to_prepend < 0) { $nspaces_to_prepend = 0; }

  return get_monocharacter_string($nspaces_to_prepend, " ") . $str; 
}

#################################################################
# Subroutine: determine_if_coverage_is_accurate()
# Incept:     EPN, Thu Apr 20 10:30:28 2017
#
# Purpose:    Based on the command line options determine if the 
#             coverage values are accurate. With the fast mode,
#             coverage values are not accurate, but with some
#             options like --hmm and --slow, they are.
#
# Arguments:
#   $opt_HHR:       reference to 2D hash of cmdline options
#
# Returns:  '1' if coverage is accurate, else '0'
# 
# Dies:     Never
#
#################################################################
sub determine_if_coverage_is_accurate { 
  my $sub_name = "determine_if_coverage_is_accurate()";
  my $nargs_expected = 1;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($opt_HHR) = (@_);

  my $have_accurate_coverage = 0;
  if(opt_Get("--hmm",      $opt_HHR)) { $have_accurate_coverage = 1; }
  if(opt_Get("--slow",     $opt_HHR)) { $have_accurate_coverage = 1; }
  if(opt_Get("--mid",      $opt_HHR)) { $have_accurate_coverage = 1; }
  if(opt_Get("--max",      $opt_HHR)) { $have_accurate_coverage = 1; }
  if(opt_Get("--nhmmer",   $opt_HHR)) { $have_accurate_coverage = 1; }
  if(opt_Get("--ssualign", $opt_HHR)) { $have_accurate_coverage = 1; }

  return $have_accurate_coverage;
}

#################################################################
# Subroutine: determine_if_we_have_model_coords()
# Incept:     EPN, Tue May  2 09:40:34 2017
#
# Purpose:    Based on the command line options determine if the
#             search output includes model coordinates or not.
#
# Arguments:
#   $opt_HHR: reference to 2D hash of cmdline options
#
# Returns:  '1' if we have model coords, else '0'
# 
# Dies:     Never
#
#################################################################
sub determine_if_we_have_model_coords { 
  my $sub_name = "determine_if_we_have_model_coords()";
  my $nargs_expected = 1;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($opt_HHR) = (@_);

  my $have_model_coords = 0;
  if(opt_Get("--hmm",      $opt_HHR)) { $have_model_coords = 1; }
  if(opt_Get("--slow",     $opt_HHR)) { $have_model_coords = 1; }
  if(opt_Get("--mid",      $opt_HHR)) { $have_model_coords = 1; }
  if(opt_Get("--max",      $opt_HHR)) { $have_model_coords = 1; }
  if(opt_Get("--nhmmer",   $opt_HHR)) { $have_model_coords = 1; }
  if(opt_Get("--ssualign", $opt_HHR)) { $have_model_coords = 1; }

  return $have_model_coords;
}

#################################################################
# Subroutine: get_overlap()
# Incept:     EPN, Mon Apr 24 15:47:13 2017
#
# Purpose:    Determine if there is overlap between two regions
#             defined by strings of the format <d1>-<d2> where
#             <d1> is the beginning of the region and <d2> is the
#             end. If strand is "+" then <d1> <= <d2> and if strand
#             is "-" then <d1> >= <d2>.
#
# Arguments:
#   $regstr1:  string 1 defining region 1
#   $regstr2:  string 2 defining region 2
#
# Returns:  Two values:
#           $noverlap:    Number of nucleotides of overlap between hit1 and hit2, 
#                         0 if none
#           $overlap_reg: region of overlap, "" if none
# 
# Dies:     If regions are not formatted correctly, or
#           regions are different strands.
#
#################################################################
sub get_overlap { 
  my $sub_name = "get_overlap()";
  my $nargs_expected = 2;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($regstr1, $regstr2) = (@_);

  my ($start1, $stop1, $strand1) = decompose_region_str($regstr1);
  my ($start2, $stop2, $strand2) = decompose_region_str($regstr2);

  if($strand1 ne $strand2) { 
    die "ERROR in $sub_name, different strands for regions $regstr1 and $regstr2";
  }

  if($strand1 eq "-") { 
    my $tmp = $start1; 
    $start1 = $stop1;
    $stop1  = $tmp;
    $tmp    = $start2;
    $start2 = $stop2;
    $stop2  = $tmp;
  }

  return get_overlap_helper($start1, $stop1, $start2, $stop2);
}

#################################################################
# Subroutine: get_overlap_helper()
# Incept:     EPN, Mon Mar 14 13:47:57 2016 [dnaorg_scripts:dnaorg.pm:getOverlap()]
#
# Purpose:    Calculate number of nucleotides of overlap between
#             two regions.
#
# Args:
#  $start1: start position of hit 1 (must be <= $end1)
#  $end1:   end   position of hit 1 (must be >= $end1)
#  $start2: start position of hit 2 (must be <= $end2)
#  $end2:   end   position of hit 2 (must be >= $end2)
#
# Returns:  Two values:
#           $noverlap:    Number of nucleotides of overlap between hit1 and hit2, 
#                         0 if none
#           $overlap_reg: region of overlap, "" if none
#
# Dies:     if $end1 < $start1 or $end2 < $start2.
sub get_overlap_helper {
  my $sub_name = "get_overlap_helper";
  my $nargs_exp = 4;
  if(scalar(@_) != 4) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($start1, $end1, $start2, $end2) = @_; 

  # printf("in $sub_name $start1..$end1 $start2..$end2\n");

  if($start1 > $end1) { die "ERROR in $sub_name start1 > end1 ($start1 > $end1)"; }
  if($start2 > $end2) { die "ERROR in $sub_name start2 > end2 ($start2 > $end2)"; }

  # Given: $start1 <= $end1 and $start2 <= $end2.
  
  # Swap if nec so that $start1 <= $start2.
  if($start1 > $start2) { 
    my $tmp;
    $tmp   = $start1; $start1 = $start2; $start2 = $tmp;
    $tmp   =   $end1;   $end1 =   $end2;   $end2 = $tmp;
  }
  
  # 3 possible cases:
  # Case 1. $start1 <=   $end1 <  $start2 <=   $end2  Overlap is 0
  # Case 2. $start1 <= $start2 <=   $end1 <    $end2  
  # Case 3. $start1 <= $start2 <=   $end2 <=   $end1
  if($end1 < $start2) { return (0, ""); }                                           # case 1
  if($end1 <   $end2) { return (($end1 - $start2 + 1), ($start2 . "-" . $end1)); }  # case 2
  if($end2 <=  $end1) { return (($end2 - $start2 + 1), ($start2 . "-" . $end2)); }  # case 3
  die "ERROR in $sub_name, unforeseen case in $start1..$end1 and $start2..$end2";

  return; # NOT REACHED
}

#################################################################
# Subroutine: sort_hit_array()
# Incept:     EPN, Tue Apr 25 06:23:42 2017
#
# Purpose:    Sort an array of regions of hits.
#
# Args:
#  $tosort_AR:   ref of array to sort
#  $order_AR:    ref to array of original indices corresponding to @{$tosort_AR}
#  $allow_dups:  '1' to allow duplicates in $tosort_AR, '0' to not and die if
#                they're found
#
# Returns:  string indicating the order of the elements in $tosort_AR in the sorted
#           array.
#
# Dies:     - if some of the regions in @{$tosort_AR} are on different strands
#             or are in the wrong format
#           - if there are duplicate values in $tosort_AR and $allow_dups is 0
sub sort_hit_array { 
  my $sub_name = "sort_hit_array";
  my $nargs_exp = 3;
  if(scalar(@_) != 3) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($tosort_AR, $order_AR, $allow_dups) = @_;

  my ($i, $j); # counters

  my $nel = scalar(@{$tosort_AR});

  if($nel == 1) { die "ERROR in $sub_name, nel is 1 (should be > 1)"; }

  # make sure all elements are on the same strand
  my(undef, undef, $strand) = decompose_region_str($tosort_AR->[0]);
  for($i = 1; $i < $nel; $i++) { 
    my(undef, undef, $cur_strand) = decompose_region_str($tosort_AR->[$i]);
    if($strand ne $cur_strand) { 
      die "ERROR in $sub_name, not all regions are on same strand, region 1: $tosort_AR->[0] $strand, region " . $i+1 . ": $tosort_AR->[$i] $cur_strand";
    }
  }

  # make a temporary hash and sort it by value
  my %hash = ();
  for($i = 0; $i < $nel; $i++) { 
    $hash{($i+1)} = $tosort_AR->[$i];
  }
  @{$order_AR} = (sort {$hash{$a} <=> $hash{$b}} (keys %hash));

  # now that we have the sorted order, we can easily check for dups
  if(! $allow_dups) { 
    for($i = 1; $i < $nel; $i++) { 
      if($hash{$order_AR->[($i-1)]} eq $hash{$order_AR->[$i]}) { 
        die "ERROR in $sub_name, duplicate values exist in the array: " . $hash{$order_AR->[$i]} . " appears twice"; 
      }
    }
  }

  # reverse array if strand is "-"
  if($strand eq "-") { 
    @{$order_AR} = reverse @{$order_AR};
  }

  # construct return string
  my $ret_str = $order_AR->[0];
  for($i = 1; $i < $nel; $i++) { 
    $ret_str .= "," . $order_AR->[$i];
  }

  return $ret_str;
}

#################################################################
# Subroutine: decompose_region_str()
# Incept:     EPN, Wed Apr 26 06:09:45 2017
#
# Purpose:    Given a 'region' string in the format <d1>.<d2>, 
#             decompose it and return <d1>, <d2> and <strand>.
#
# Args:
#  $regstr:    region string in format <d1>.<d2>
#
# Returns:  Three values:
#           <d1>: beginning of region
#           <d2>: end of region
#           <strand>: "+" if <d1> <= <d2>, else "-"
#
# Dies:     if $regstr is not in correct format 
sub decompose_region_str { 
  my $sub_name = "decompose_region_str";
  my $nargs_exp = 1;
  if(scalar(@_) != 1) { die "ERROR $sub_name entered with wrong number of input args"; }

  my ($regstr) = @_;

  my ($d1, $d2, $strand); 
  if($regstr =~ /(\d+)\.(\d+)/) { ($d1, $d2) = ($1, $2); }
  else                          { die "ERROR in $sub_name, region string $regstr not parseable"; }

  $strand = ($d1 <= $d2) ? "+" : "-";

  return($d1, $d2, $strand);
}