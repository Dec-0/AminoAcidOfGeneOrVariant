#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
Getopt::Long::Configure qw(no_ignore_case);
use File::Basename;
use FindBin qw($Bin);
use lib "$Bin/.Modules";
use Parameter::BinList;
use SeqRelated::Seq;

my ($HelpFlag,$BinList,$BeginTime);
my $ThisScriptName = basename $0;
my ($Gene,$Transcript,$FlankLen,$RefInfo,$Ref,$BedtoolsBin);
my @Var;
my $HelpInfo = <<USAGE;

 $ThisScriptName
 Auther: zhangdong_xie\@foxmail.com

  本脚本的应用范围：
      1. 查询基因对应的转录本信息，包括转录本号、外显子号以及对应的染色体坐标（with -gene，比如:perl Script -gene EGFR）；
      2. 查询转录本对应的碱基及氨基酸序列（with -tr，比如:perl Script -tr NM_001346941）；
      3. 检查引入变异（alt）前后碱基及氨基酸序列的改变（with -tr -var, -flank optional，比如:perl Script -tr NM_001346941 -var 'chr7,55181378,C,T'）。

 -gene   ( Optional ) Gene name;
 -tr     ( Optional ) Transcript ID begin with 'NM_';
 -var    ( Optional ) Variants\' info with format like 'chr7,55181378,C,T' (one or multi times);
 -flank  ( Optional ) Flanking length of the alt amino acid (default: all);

 -bin    List for searching of related bin or scripts; 
 -h      Help infomation;

USAGE

GetOptions(
	'gene:s' => \$Gene,
	'tr:s' => \$Transcript,
	'var:s' => \@Var,
	'flank:i' => \$FlankLen,
	'bin:s' => \$BinList,
	'h!' => \$HelpFlag
) or die $HelpInfo;

if($HelpFlag || (!$Gene && !$Transcript && !@Var))
{
	die $HelpInfo;
}
else
{
	$BeginTime = ScriptBegin();
	
	
	$BinList = BinListGet() if(!$BinList);
	$RefInfo = BinSearch("refGene",$BinList);
	$Ref = BinSearch("Reference",$BinList);
	$BedtoolsBin = BinSearch("Bedtools",$BinList);
}

if(1)
{
	if($Gene)
	{
		my %GeneInfo = %{ExonCoordInfo($RefInfo,$Gene)};
		
		print "\n#The transcripts' info for $Gene is as follows:\n";
		print join("\t","#TranscriptID","Chromosome","Orientation","StartOfCD","EndOfCD"),"\n";
		for my $Key (keys %GeneInfo)
		{
			next if($Key eq "All");
			next unless($Key =~ /^NM_/);
			
			print join("\t",$Key,$GeneInfo{$Key}{"chrom"},$GeneInfo{$Key}{"strand"},$GeneInfo{$Key}{"cdsStart"},$GeneInfo{$Key}{"cdsEnd"}),"\n";
		}
		
		print "\n#The exons' info for each transcript is as follows:\n";
		print join("\t","#TranscriptID","Chromosome","Orientation","BedStart","BedEnd","Exon"),"\n";
		foreach my $Key (keys %GeneInfo)
		{
			next if($Key eq "All");
			
			my $NMId = $Key;
			my @Start = split /,/, $GeneInfo{$NMId}{"exonStarts"};
			my @End = split /,/, $GeneInfo{$NMId}{"exonEnds"};
			if($GeneInfo{$NMId}{"strand"} eq "-")
			{
				my (@tStart,@tEnd) = ();
				
				for(my $k = $#Start;$k >= 0;$k --)
				{
					push @tStart, $Start[$k];
					push @tEnd, $End[$k];
				}
				@Start = @tStart;
				@End = @tEnd;
			}
			for my $k (1 .. $GeneInfo{$NMId}{"exonCount"})
			{
				print join("\t",$NMId,$GeneInfo{$NMId}{"chrom"},$GeneInfo{$NMId}{"strand"},$Start[$k - 1],$End[$k - 1],"Exon"),$k,"\n";
			}
			print "\n";
			# 只检查一个转录本;
			#last;
		}
	}
	elsif($Transcript && !@Var)
	{
		my @Cols = CdsOfTranscript($RefInfo,$Transcript,$Ref,$BedtoolsBin);
		my ($BaseSeq,$Chr,$Ori) = @Cols[0 .. 2];
		my $AASeq = Nucleo2Amino($BaseSeq,0,$Ori);
		
		print "#The nucleotide sequence of $Transcript is :\n$BaseSeq\n";
		print "\n#The amino acid sequence of $Transcript is :\n$AASeq\n";
	}
	elsif($Transcript && @Var)
	{
		for my $i (0 .. $#Var)
		{
			my @Cols = split /,/, $Var[$i];
			die "[ Error ] Not format like 'chr7,55249071,C,T'\n" unless($#Cols == 3);
			for my $j (0 .. $#Cols)
			{
				die "[ Error ] Empty column in $Var[$i]\n" unless($Cols[$i]);
			}
			die "[ Error ] Not begin with chr in $Cols[0]\n" unless($Cols[0] =~ /^chr/);
			die "[ Error ] Not pure number in $Cols[1]\n" if($Cols[1] =~ /\D/);
		}
		
		my @Cols = CdsOfTranscript($RefInfo,$Transcript,$Ref,$BedtoolsBin);
		my ($BaseSeq,$Chr,$Ori) = @Cols[0 .. 2];
		my @CDStart = @{$Cols[3]};
		my @CDEnd = @{$Cols[4]};
		@Cols = NucleoBaseRevise($BaseSeq,$Ref,$Chr,$Ori,\@CDStart,\@CDEnd,\@Var);
		my $NewBaseSeq = $Cols[0];
		my @AltStart = @{$Cols[1]};
		my @AltEnd = @{$Cols[2]};
		my $AASeq = Nucleo2Amino($NewBaseSeq,0,$Ori);
		for my $i (0 .. $#Var)
		{
			my ($LeftBase,$RightBase,$AltBase) = ();
			my $Ori3Flag = 0;
			if(length($Ori) == 0)
			{
				$Ori3Flag = 1;
			}
			elsif($Ori eq "-")
			{
				$Ori3Flag = 1;
			}
			elsif($Ori =~ /^\d+$/)
			{
				$Ori3Flag = 1 if($Ori <= 0);
			}
			if($Ori3Flag)
			{
				$LeftBase = substr($NewBaseSeq,0,length($NewBaseSeq) - $AltEnd[$i] + 1);
				$RightBase = substr($NewBaseSeq,length($NewBaseSeq) - $AltStart[$i]);
				$AltBase = substr($NewBaseSeq,length($NewBaseSeq) - $AltEnd[$i] + 1,$AltEnd[$i] - $AltStart[$i] - 1);
			}
			else
			{
				$LeftBase = substr($NewBaseSeq,0,$AltStart[$i]);
				$RightBase = substr($NewBaseSeq,$AltEnd[$i] - 1);
				$AltBase = substr($NewBaseSeq,$AltStart[$i],$AltEnd[$i] - $AltStart[$i] - 1);
			}
			print "#The alt nucleotide sequence for $Transcript is :\n";
			print join("-",$LeftBase,$AltBase,$RightBase),"\n\n";
			
			
			my $LeftAAId = int($AltStart[$i] / 3);
			my $RightAAId = int($AltEnd[$i] / 3);
			$RightAAId ++ unless($AltEnd[$i] % 3 == 0);
			$RightAAId ++ if($AltEnd[$i] % 3 != 1);
			die "[ Error ] The amino acid sequence was truncted before the variation.\n" if(length($AASeq) < $RightAAId);
			my $LeftAA = substr($AASeq,0,$LeftAAId);
			my $RightAA = substr($AASeq,$RightAAId - 1);
			my $AltAA = substr($AASeq,$LeftAAId,$RightAAId - $LeftAAId - 1);
			$LeftAA = substr($LeftAA,length($LeftAA) - $FlankLen) if($FlankLen && length($LeftAA) > $FlankLen);
			$RightAA = substr($RightAA,0,$FlankLen) if($FlankLen && length($RightAA) > $FlankLen);
			print "\n#The alt amino acid sequence for $Transcript is :\n";
			print join("-",$LeftAA,$AltAA,$RightAA),"\n\n";
		}
	}
}
printf "[ %s ] The end.\n",TimeString(time,$BeginTime);


######### Sub functions ##########
