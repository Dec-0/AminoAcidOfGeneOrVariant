# Package Name
package VcfRelated::VcfParse;

# Exported name
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(VarSimplify VarUniform RefConfirm);
use SeqRelated::Seq;

# 去除多余的碱基;
sub VarSimplify
{
	my ($Chr,$From,$To,$Ref,$Alt) = @_;
	
	if($Ref =~ /^$Alt/ && $Alt ne "*")
	{
		# deletion;
		$From += length($Alt);
		$Ref =~ s/^$Alt//;
		$Alt = "-";
	}
	elsif($Alt =~ /^$Ref/ && $Ref ne "*")
	{
		# insertion;
		$From = $To;
		$Alt =~ s/^$Ref//;
		$Ref = "-";
	}
	$Ref = uc($Ref);
	$Alt = uc($Alt);
	
	return $Chr,$From,$To,$Ref,$Alt;
}

# 将所有的变异都尽量往5'或者3'移动;
sub VarUniform
{
	my ($RefGen,$Chr,$From,$To,$Ref,$Alt,$Ori3Flag,$BedtoolsBin) = @_;
	die "[ Error ] Asterisk * found in Ref or Alt ($Chr,$From,$To,$Ref,$Alt) when var uniform.\n" if($Alt eq "*" || $Ref eq "*");
	
	($Chr,$From,$To,$Ref,$Alt) = &VarSimplify($Chr,$From,$To,$Ref,$Alt);
	if($Ref && $Alt eq "-")
	{
		# deletion;
		if($Ori3Flag)
		{
			# 3’端标准化;
			my $LeftBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$From,$From,$BedtoolsBin);
			my $RightBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$To + 1,$To + 1,$BedtoolsBin);
			while($LeftBase eq $RightBase)
			{
				$From ++;
				$To ++;
				$LeftBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$From,$From,$BedtoolsBin);
				$RightBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$To + 1,$To + 1,$BedtoolsBin);
			}
		}
		else
		{
			# 5’端标准化;
			my $LeftBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$From - 1,$From - 1,$BedtoolsBin);
			my $RightBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$To,$To,$BedtoolsBin);
			while($LeftBase eq $RightBase)
			{
				$From --;
				$To --;
				$LeftBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$From - 1,$From - 1,$BedtoolsBin);
				$RightBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$To,$To,$BedtoolsBin);
			}
		}
		$Ref = SeqRelated::Seq::RefGet($RefGen,$Chr,$From,$To,$BedtoolsBin);
	}
	elsif($Ref eq "-" && $Alt)
	{
		# insertion;
		my $AltLen = length($Alt);
		my @AltBase = split //, $Alt;
		if($Ori3Flag)
		{
			my $tPos = $From;
			my $tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$tPos + 1,$tPos + 1,$BedtoolsBin);
			my $tNum = 0;
			my $tId = $tNum % $AltLen;
			while($tBase eq $AltBase[$tId])
			{
				$tPos ++;
				$tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$tPos + 1,$tPos + 1,$BedtoolsBin);
				$tNum ++;
				$tId = $tNum % $AltLen;
			}
			
			if($tPos > $From)
			{
				$tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$From + 1,$tPos,$BedtoolsBin);
				$tBase = $Alt . $tBase;
				$Alt = substr($tBase,$tPos - $From);
				$From = $tPos;
				$To = $From;
			}
		}
		else
		{
			my $tPos = $From;
			my $tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$tPos,$tPos,$BedtoolsBin);
			my $tNum = 0;
			my $tId = $#AltBase - ($tNum % $AltLen);
			while($tBase eq $AltBase[$tId])
			{
				$tPos --;
				$tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$tPos,$tPos,$BedtoolsBin);
				$tNum ++;
				$tId = $#AltBase - ($tNum % $AltLen);
			}
			
			if($tPos < $From)
			{
				$tBase = SeqRelated::Seq::RefGet($RefGen,$Chr,$tPos + 1,$From,$BedtoolsBin);
				$tBase .= $Alt;
				$Alt = substr($tBase,0,$AltLen);
				$From = $tPos;
				$To = $From;
			}
		}
	}
	$Ref = uc($Ref);
	$Alt = uc($Alt);
	
	return $Chr,$From,$To,$Ref,$Alt;
}

# 确认ref序列是否正确;
sub RefConfirm
{
	my ($RefGen,$Chr,$From,$To,$Ref,$BedtoolsBin) = @_;
	my $Flag = 1;
	
	die "[ Error ] The format of coordinate not correct ($Chr,$From,$To,$Ref).\n" if($From eq "-" || $To eq "-");
	die "[ Error in VcfRelated::VcfParse ] To smaller than From ($Chr,$From,$To,$Ref).\n" if($To =~ /\D/ || $From =~ /\D/ || $To < $From);
	if($Ref ne "-")
	{
		$Ref = uc($Ref);
		$Flag = 0 unless(length($Ref) == $To - $From + 1);
		
		if($Flag)
		{
			my $tSeq = SeqRelated::Seq::RefGet($RefGen,$Chr,$From,$To,$BedtoolsBin);
			$Flag = 0 if($tSeq ne $Ref);
		}
	}
	
	return $Flag;
}

1;