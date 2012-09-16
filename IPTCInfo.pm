# IPTCInfo: extractor for IPTC metadata embedded in images
# Copyright (C) 2000 Josh Carter <josh@spies.com>
# All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

package Image::IPTCInfo;

use vars qw($VERSION);
$VERSION = '1.51';

#
# Global vars
#
use vars ('%datasets',		# master list of dataset id's
		  '%datanames',     # reverse mapping (for saving)
		  '%listdatasets',	# master list of repeating dataset id's
		  '%listdatanames', # reverse
		  );

# Debug off for production use
my $debugMode = 1;
my $error;
	  
#####################################
# These names match the codes defined in ITPC's IIM record 2.
# This hash is for non-repeating data items; repeating ones
# are in %listdatasets below.
%datasets = (
#	0	=> 'record version',		# skip -- binary data
	5	=> 'object name',
	7	=> 'edit status',
	8	=> 'editorial update',
	10	=> 'urgency',
	12	=> 'subject reference',
	15	=> 'category',
#	20	=> 'supplemental category',	# in listdatasets (see below)
	22	=> 'fixture identifier',
#	25	=> 'keywords',				# in listdatasets
	26	=> 'content location code',
	27	=> 'content location name',
	30	=> 'release date',
	35	=> 'release time',
	37	=> 'expiration date',
	38	=> 'expiration time',
	40	=> 'special instructions',
	42	=> 'action advised',
	45	=> 'reference service',
	47	=> 'reference date',
	50	=> 'reference number',
	55	=> 'date created',
	60	=> 'time created',
	62	=> 'digital creation date',
	63	=> 'digital creation time',
	65	=> 'originating program',
	70	=> 'program version',
	75	=> 'object cycle',
	80	=> 'by-line',
	85	=> 'by-line title',
	90	=> 'city',
	92	=> 'sub-location',
	95	=> 'province/state',
	100	=> 'country/primary location code',
	101	=> 'country/primary location name',
	103	=> 'original transmission reference',
	105	=> 'headline',
	110	=> 'credit',
	115	=> 'source',
	116	=> 'copyright notice',
	118	=> 'contact',
	120	=> 'caption/abstract',
	122	=> 'writer/editor',
#	125	=> 'rasterized caption', # unsupported (binary data)
	130	=> 'image type',
	131	=> 'image orientation',
	135	=> 'language identifier',
	200	=> 'custom1', # These are NOT STANDARD, but are used by
	201	=> 'custom2', # Fotostation. Use at your own risk. They're
	202	=> 'custom3', # here in case you need to store some special
	203	=> 'custom4', # stuff, but note that other programs won't 
	204	=> 'custom5', # recognize them and may blow them away if 
	205	=> 'custom6', # you open and re-save the file. (Except with
	206	=> 'custom7', # Fotostation, of course.)
	207	=> 'custom8',
	208	=> 'custom9',
	209	=> 'custom10',
	210	=> 'custom11',
	211	=> 'custom12',
	212	=> 'custom13',
	213	=> 'custom14',
	214	=> 'custom15',
	215	=> 'custom16',
	216	=> 'custom17',
	217	=> 'custom18',
	218	=> 'custom19',
	219	=> 'custom20',
	);

# this will get filled in if we save data back to file
%datanames = ();

%listdatasets = (
	20	=> 'supplemental category',
	25	=> 'keywords',
	);

# this will get filled in if we save data back to file
%listdatanames = ();
	
#######################################################################
# New, Save, Destroy, Error
#######################################################################

#
# new
# 
# $info = new IPTCInfo('image filename goes here')
# 
# Returns iPTCInfo object filled with metadata from the given image 
# file. File on disk will be closed, and changes made to the IPTCInfo
# object will *not* be flushed back to disk.
#
sub new
{
	my ($pkg, $filename, $force) = @_;

	#
	# Open file and snarf data from it.
	#
	unless(open(FILE, $filename))
	{
		$error = "Can't open file: $!"; Log($error);
		return undef;
	}

	binmode(FILE);

	my $datafound = ScanToFirstIMMTag();
	unless ($datafound || defined($force))
	{
		$error = "No IPTC data found."; Log($error);
		close(FILE);
		return undef;
	}

	my $self = bless
	{
		'_data'		=> {},	# empty hashes; wil be
		'_listdata'	=> {},	# filled in CollectIIMInfo
		'_filename' => $filename,
	}, $pkg;
	
	# Do the real snarfing here
	CollectIIMInfo($self) if $datafound;
	
	close(FILE);
		
	return $self;
}

#
# create
#
# Like new, but forces an object to always be returned. This allows
# you to start adding stuff to files that don't have IPTC info and then
# save it.
#
sub create
{
	my ($pkg, $filename) = @_;

	return new($pkg, $filename, 'force');
}

#
# Save
#
# Saves JPEG with IPTC data back to the same file it came from.
#
sub Save
{
	my ($self) = @_;

	return $self->SaveAs($self->{'_filename'});
}

#
# Save
#
# Saves JPEG with IPTC data to a given file name.
#
sub SaveAs
{
	my ($self, $newfile) = @_;

	#
	# Open file and snarf data from it.
	#
	unless(open(FILE, $self->{'_filename'}))
	{
		$error = "Can't open file: $!"; Log($error);
		return undef;
	}

	binmode(FILE);

	unless (FileIsJFIF())
	{
		$error = "Source file is not a JFIF; I can only save JFIFs. Sorry.";
		Log($error);
		return undef;
	}

	my $ret = JFIFCollectFileParts();

	close(FILE);

	if ($ret == 0)
	{
		Log("collectfileparts failed");
		return undef;
	}

	my ($start, $end, $adobe) = @$ret;

	#
	# Open dest file and stuff data there
	#
	unless(open(FILE, '>' . $newfile))
	{
		$error = "Can't open output file: $!"; Log($error);
		return undef;
	}

	binmode(FILE);

	print FILE $start;
	print FILE $self->PhotoshopIIMBlock($adobe, $self->PackedIIMData());
	print FILE $end;

	close(FILE);
		
	return 1;
}

#
# DESTROY
# 
# Called when object is destroyed. No action necessary in this case.
#
sub DESTROY
{
	# no action necessary
}

#
# Error
#
# Returns description of the last error.
#
sub Error
{
	return $error;
}

#######################################################################
# Attributes for clients
#######################################################################

#
# Attribute/SetAttribute
# 
# Returns/Changes value of a given data item.
#
sub Attribute
{
	my ($self, $attribute) = @_;

	return $self->{_data}->{$attribute};
}

sub SetAttribute
{
	my ($self, $attribute, $newval) = @_;

	$self->{_data}->{$attribute} = $newval;
}

#
# Keywords/Clear/Add
# 
# Returns reference to a list of keywords/clears the keywords
# list/adds a keyword.
#
sub Keywords
{
	my $self = shift;
	return $self->{_listdata}->{'keywords'};
}

sub ClearKeywords
{
	my $self = shift;
	$self->{_listdata}->{'keywords'} = [];
}

sub AddKeyword
{
	my ($self, $add) = @_;
	
	$self->AddListData('keywords', $add);
}

#
# SupplementalCategories/Clear/Add
# 
# Returns reference to a list of supplemental categories.
#
sub SupplementalCategories
{
	my $self = shift;
	return $self->{_listdata}->{'supplemental category'};
}

sub ClearSupplementalCategories
{
	my $self = shift;
	$self->{_listdata}->{'supplemental category'} = [];
}

sub AddSupplementalCategories
{
	my ($self, $add) = @_;
	
	$self->AddListData('supplemental category', $add);
}

sub AddListData
{
	my ($self, $list, $add) = @_;

	# did user pass in a list ref?
	if (ref($add) eq 'ARRAY')
	{
		# yes, add list contents
		push(@{$self->{_listdata}->{$list}}, @$add);
	}
	else
	{
		# no, just a literal item
		push(@{$self->{_listdata}->{$list}}, $add);
	}
}

#######################################################################
# XML, SQL export
#######################################################################

#
# ExportXML
# 
# $xml = $info->ExportXML('entity-name', \%extra-data,
#                         'optional output file name');
# 
# Exports XML containing all image metadata. Attribute names are
# translated into XML tags, making adjustments to spaces and slashes
# for compatibility. (Spaces become underbars, slashes become dashes.)
# Caller provides an entity name; all data will be contained within
# this entity. Caller optionally provides a reference to a hash of 
# extra data. This will be output into the XML, too. Keys must be 
# valid XML tag names. Optionally provide a filename, and the XML 
# will be dumped into there.
#
sub ExportXML
{
	my ($self, $basetag, $extraRef, $filename) = @_;
	my $out;
	
	$basetag = 'photo' unless length($basetag);
	
	$out .= "<$basetag>\n";

	# dump extra info first, if any
	foreach my $key (keys %$extraRef)
	{
		$out .= "\t<$key>" . $extraRef->{$key} . "</$key>\n";
	}
	
	# dump our stuff
	foreach my $key (keys %{$self->{_data}})
	{
		my $cleankey = $key;
		$cleankey =~ s/ /_/g;
		$cleankey =~ s/\//-/g;
		
		$out .= "\t<$cleankey>" . $self->{_data}->{$key} . "</$cleankey>\n";
	}
	
	if (defined ($self->Keywords()))
	{
		# print keywords
		$out .= "\t<keywords>\n";
		
		foreach my $keyword (@{$self->Keywords()})
		{
			$out .= "\t\t<keyword>$keyword</keyword>\n";
		}
		
		$out .= "\t</keywords>\n";
	}

	if (defined ($self->SupplementalCategories()))
	{
		# print supplemental categories
		$out .= "\t<supplemental_categories>\n";
		
		foreach my $category (@{$self->SupplementalCategories()})
		{
			$out .= "\t\t<supplemental_cagegory>$category</supplemental_category>\n";
		}
		
		$out .= "\t</supplemental_categories>\n";
	}

	# close base tag
	$out .= "</$basetag>\n";

	# export to file if caller asked for it.
	if (length($filename))
	{
		open(XMLOUT, ">$filename");
		print XMLOUT $out;
		close(XMLOUT);
	}
	
	return $out;
}

#
# ExportSQL
# 
# my %mappings = (
#   'IPTC dataset name here'    => 'your table column name here',
#   'caption/abstract'          => 'caption',
#   'city'                      => 'city',
#   'province/state'            => 'state); # etc etc etc.
# 
# $statement = $info->ExportSQL('mytable', \%mappings, \%extra-data);
#
# Returns a SQL statement to insert into your given table name 
# a set of values from the image. Caller passes in a reference to
# a hash which maps IPTC dataset names into column names for the
# database table. Optionally pass in a ref to a hash of extra data
# which will also be included in the insert statement. Keys in that
# hash must be valid column names.
#
sub ExportSQL
{
	my ($self, $tablename, $mappingsRef, $extraRef) = @_;
	my ($statement, $columns, $values);
	
	return undef if (($tablename eq undef) || ($mappingsRef eq undef));

	# start with extra data, if any
	foreach my $column (keys %$extraRef)
	{
		my $value = $extraRef->{$column};
		$value =~ s/'/''/g; # escape single quotes
		
		$columns .= $column . ", ";
		$values  .= "\'$value\', ";
	}
	
	# process our data
	foreach my $attribute (keys %$mappingsRef)
	{
		my $value = $self->Attribute($attribute);
		$value =~ s/'/''/g; # escape single quotes
		
		$columns .= $mappingsRef->{$attribute} . ", ";
		$values  .= "\'$value\', ";
	}
	
	# must trim the trailing ", " from both
	$columns =~ s/, $//;
	$values  =~ s/, $//;

	$statement = "INSERT INTO $tablename ($columns) VALUES ($values)";
	
	return $statement;
}

#######################################################################
# File parsing functions (private)
#######################################################################

#
# ScanToFirstIMMTag
#
# Scans to first IIM Record 2 tag in the file. The will either use
# smart scanning for JPEGs or blind scanning for other file types.
#
sub ScanToFirstIMMTag
{
	if (FileIsJFIF())
	{
		Log("File is JFIF, proceeding with JFIFScan");
		return JFIFScan();
	}
	else
	{
		Log("File not a JFIF, trying BlindScan");
		return BlindScan();
	}
}

#
# FileIsJFIF
#
# Checks to see if this file is a JPEG/JFIF or not. Will reset the
# file position back to 0 after it's done in either case.
#
sub FileIsJFIF
{
	# reset to beginning just in case
	seek(FILE, 0, 0);

	if ($debugMode)
	{
		Log("Opening 16 bytes of file:\n");
		my $dump;
		read (FILE, $dump, 16);
		HexDump($dump);
		seek(FILE, 0, 0);
	}

	# check start of file marker
	my ($ff, $soi);
	read (FILE, $ff, 1) || goto notjfif;
	read (FILE, $soi, 1);
	
	goto notjfif unless (ord($ff) == 0xff & ord($soi) == 0xd8);

	# now check for APP0 marker. I'll assume that anything with a SOI
	# followed by APP0 is "close enough" for our purposes. (We're not
	# dinking with image data, so anything following the JPEG tagging
	# system should work.)
	my ($app0, $len, $jfif);
	read (FILE, $ff, 1);
	read (FILE, $app0, 1);

	goto notjfif unless (ord($ff) == 0xff);

	# reset to beginning of file
	seek(FILE, 0, 0);
	return 1;

  notjfif:
	seek(FILE, 0, 0);
	return 0;
}

#
# JFIFScan
#
# Assuming the file is a JFIF (see above), this will scan through the
# markers looking for the APP13 marker, where IPTC/IIM data should be
# found. While this isn't a formally defined standard, all programs
# have (supposedly) adopted Adobe's technique of putting the data in
# APP13.
#
sub JFIFScan
{
	# Skip past start of file marker
	my ($ff, $soi);
	read (FILE, $ff, 1) || return 0;
	read (FILE, $soi, 1);
	
	unless (ord($ff) == 0xff & ord($soi) == 0xd8)
	{
		$error = "JFIFScan: invalid start of file"; Log($error);
		return 0;
	}

	# Scan for the APP13 marker which will contain our IPTC info (I hope).

	my $marker = JFIFNextMarker();

	while (ord($marker) != 0xed)
	{
		if (ord($marker) == 0)
		{ $error = "Marker scan failed"; Log($error); return 0; }

		if (ord($marker) == 0xd9)
		{ $error = "Marker scan hit end of image marker";
		  Log($error); return 0; }

		if (ord($marker) == 0xda)
		{ $error = "Marker scan hit start of image data";
		  Log($error); return 0; }

		if (JFIFSkipVariable() == 0)
		{ $error = "JFIFSkipVariable failed";
		  Log($error); return 0; }

		$marker = JFIFNextMarker();
	}

	# If were's here, we must have found the right marker. Now
	# BlindScan through the data.
	return BlindScan();
}

#
# JFIFNextMarker
#
# Scans to the start of the next valid-looking marker. Return value is
# the marker id.
#
sub JFIFNextMarker
{
	my $byte;

	# Find 0xff byte. We should already be on it.
	read (FILE, $byte, 1) || return 0;
	while (ord($byte) != 0xff)
	{
		Log("JFIFNextMarker: warning: bogus stuff in JFIF file");
		read(FILE, $byte, 1) || return 0;
	}

	# Now skip any extra 0xffs, which are valid padding.
	do
	{
		read(FILE, $byte, 1) || return 0;
	} while (ord($byte) == 0xff);

	# $byte should now contain the marker id.
	Log("JFIFNextMarker: at marker " . unpack("H*", $byte));
	return $byte;
}

#
# JFIFSkipVariable
#
# Skips variable-length section of JFIF block. Should always be called
# between calls to JFIFNextMarker to ensure JFIFNextMarker is at the
# start of data it can properly parse.
#
sub JFIFSkipVariable
{
	my $rSave = shift;

	# Get the marker parameter length count
	my $length;
	read(FILE, $length, 2) || return 0;
		
	($length) = unpack("n", $length);

	Log("JFIF variable length: $length");

	# Length includes itself, so must be at least 2
	if ($length < 2)
	{
		Log("JFIFSkipVariable: Erroneous JPEG marker length");
		return 0;
	}
	$length -= 2;
	
	# Skip remaining bytes
	my $temp;
	if (defined($rSave) || $debugMode)
	{
		unless (read(FILE, $temp, $length))
		{
			Log("JFIFSkipVariable: read failed while skipping var data");
			return 0;
		}

		# prints out a heck of a lot of stuff
		# HexDump($temp);
	}
	else
	{
		# Just seek
		unless(seek(FILE, $length, 1))
		{
			Log("JFIFSkipVariable: read failed while skipping var data");
			return 0;
		}
	}

	$$rSave = $temp if defined($rSave);

	return 1;
}

#
# BlindScan
#
# Scans blindly to first IIM Record 2 tag in the file. This method may
# or may not work on any arbitrary file type, but it doesn't hurt to
# check. We expect to see this tag within the first 8k of data. (This
# limit may need to be changed or eliminated depending on how other
# programs choose to store IIM.)
#
sub BlindScan
{
	my $offset = 0;
	my $MAX    = 8192; # keep within first 8192 bytes 
					   # NOTE: this may need to change
	
	# start digging
	while ($offset <= $MAX)
	{
		my $temp;
		
		unless (read(FILE, $temp, 1))
		{
			Log("BlindScan: hit EOF while scanning");
			return 0;
		}

		# look for tag identifier 0x1c
		if (ord($temp) == 0x1c)
		{
			# if we found that, look for record 2, dataset 0
			# (record version number)
			my ($record, $dataset);
			read (FILE, $record, 1);
			read (FILE, $dataset, 1);
			
			if (ord($record) == 2 && ord($dataset) == 0)
			{
				# found it. seek to start of this tag and return.
				Log("BlindScan: found IIM start at offset $offset");
				seek(FILE, -3, 1); # seek rel to current position
				return $offset;
			}
			else
			{
				# didn't find it. back up 2 to make up for
				# those reads above.
				seek(FILE, -2, 1); # seek rel to current position
			}
		}
		
		# no tag, keep scanning
		$offset++;
	}
	
	return 0;
}

#
# CollectIIMInfo
#
# Assuming file is seeked to start of IIM data (using above), this
# reads all the data into our object's hashes
#
sub CollectIIMInfo
{
	my $self = shift;
	
	# NOTE: file should already be at the start of the first
	# IPTC code: record 2, dataset 0.
	
	while (1)
	{
		my $header;
		return unless read(FILE, $header, 5);
		
		($tag, $record, $dataset, $length) = unpack("CCCn", $header);

		# bail if we're past end of IIM record 2 data
		return unless ($tag == 0x1c) && ($record == 2);
		
		# print "tag     : " . $tag . "\n";
		# print "record  : " . $record . "\n";
		# print "dataset : " . $dataset . "\n";
		# print "length  : " . $length  . "\n";
	
		my $value;
		read(FILE, $value, $length);
		
		# try to extract first into _listdata (keywords, categories)
		# and, if unsuccessful, into _data. Tags which are not in the
		# current IIM spec (version 4) are currently discarded.
		if (exists $listdatasets{$dataset})
		{
			my $dataname = $listdatasets{$dataset};
			my $listref  = $listdata{$dataname};
			
			push(@{$self->{_listdata}->{$dataname}}, $value);
		}
		elsif (exists $datasets{$dataset})
		{
			my $dataname = $datasets{$dataset};
	
			$self->{_data}->{$dataname} = $value;
		}
		# else discard
	}
}

#######################################################################
# File Saving
#######################################################################

#
# JFIFCollectFileParts
#
# Collects all pieces of the file except for the IPTC info that we'll
# replace when saving. Returns the stuff before the info, stuff after,
# and the contents of the Adobe Resource Block that the IPTC data goes
# in. Returns undef if a file parsing error occured.
#
sub JFIFCollectFileParts
{
	my ($start, $end, $adobeParts);

	# Start at beginning of file
	seek(FILE, 0, 0);

	# Skip past start of file marker
	my ($ff, $soi);
	read (FILE, $ff, 1) || return 0;
	read (FILE, $soi, 1);
	
	unless (ord($ff) == 0xff & ord($soi) == 0xd8)
	{
		$error = "JFIFScan: invalid start of file"; Log($error);
		return 0;
	}

	#
	# Begin building start of file
	#
	$start .= pack("CC", 0xff, 0xd8);

	#
	# Scan first APP0 section. This part *must* go in first in JFIF
	# files, so we handle it specially. I'm not going to insist that
	# it's APP0, however, since EXIF files appear to put APP1 first.
	# (Not sure why that is.) In any case, the first marker after the
	# SOI will be the first marker in our output.
	#
	my $marker = JFIFNextMarker();

	my $app0data;
	if (JFIFSkipVariable(\$app0data) == 0)
	{ $error = "JFIFSkipVariable failed";
	  Log($error); return 0; }
	
	# Append it to the file start
	$start .= pack("CC", 0xff, ord($marker));
	# remember that the length must include itself (2 bytes)
	$start .= pack("n", length($app0data) + 2);
	$start .= $app0data;

	#
	# Now scan through rest of file
	#
	$marker = JFIFNextMarker();

	while (1)
	{
		if (ord($marker) == 0)
		{ $error = "Marker scan failed"; Log($error); return 0; }

		# Check for end of image
		if (ord($marker) == 0xd9)
		{
			Log("JFIFCollectFileParts: saw end of image marker");
			$end .= pack("CC", 0xff, ord($marker));
			goto doneScanning;
		}

		# Check for start of compressed data
		if (ord($marker) == 0xda)
		{
			Log("JFIFCollectFileParts: saw start of compressed data");
			$end .= pack("CC", 0xff, ord($marker));
			goto doneScanning;
		}

		my $partdata;
		if (JFIFSkipVariable(\$partdata) == 0)
		{ $error = "JFIFSkipVariable failed";
		  Log($error); return 0; }

		# Take all parts aside from APP13, which we'll replace
		# ourselves.
		if (ord($marker) == 0xed)
		{
			# But we do need the adobe stuff from part 13
			$adobeParts = CollectAdobeParts($partdata);
			goto doneScanning;
		}
		else
		{
			# Append all other parts to start section
			$start .= pack("CC", 0xff, ord($marker));
			$start .= pack("n", length($partdata) + 2);
			$start .= $partdata;
		}

		$marker = JFIFNextMarker();
	}

  doneScanning:

	#
	# Append rest of file to $end
	#
	my $buffer;

	while (read(FILE, $buffer, 16384))
	{
		$end .= $buffer;
	}

	return [$start, $end, $adobeParts];
}

#
# CollectAdobeParts
#
# Part APP13 contains yet another markup format, one defined by Adobe.
# See "File Formats Specification" in the Photoshop SDK (avail from
# www.adobe.com). We must take everything but the IPTC data so that
# way we can write the file back without losing everything else
# Photoshop stuffed into the APP13 block.
#
sub CollectAdobeParts
{
	my ($data) = @_;
	my $length = length($data);
	my $offset = 0;
	my $out;

	# Skip preamble
	$offset = length('Photoshop 3.0 ');

	# Process everything
	while ($offset < $length)
	{
		# Get OSType and ID
		my ($ostype, $id1, $id2) = unpack("NCC", substr($data, $offset, 6));
		$offset += 6;

		# Get pascal string
		my ($stringlen) = unpack("C", substr($data, $offset, 1));
		$offset += 1;
		my $string = substr($data, $offset, $stringlen);
		$offset += $stringlen;
		# round up if odd
		$offset++ if ($stringlen % 2 != 0);
		# there should be a null if string len is 0
		$offset++ if ($stringlen == 0);

		# Get variable-size data
		my ($size) = unpack("N", substr($data, $offset, 4));
		$offset += 4;

		# xxx what if var size is 0? make sure substr returns null.
		my $var = substr($data, $offset, $size);
		$offset += $size;
		$offset++ if ($size % 2 != 0); # round up if odd

		# skip IIM data (0x0404)
		unless ($id1 == 4 && $id2 == 4)
		{
			# Output
			$out .= pack("NCC", $ostype, $id1, $id2);
			$out .= pack("C", $stringlen);
			$out .= $string;
			$out .= pack("C", 0) if ($stringlen == 0 || 
									 $stringlen % 2 != 0);
			$out .= pack("N", $size);
			$out .= $var;
			$out .= pack("C", 0) if ($size % 2 != 0);
		}
	}

	return $out;
}

#
# PackedIIMData
#
# Assembles and returns our _data and _listdata into IIM format for
# embedding into an image.
#
sub PackedIIMData
{
	my $self = shift;
	my $out;

	# First, we need to build a mapping of datanames to dataset
	# numbers if we haven't already.
	unless (scalar(keys %datanames))
	{
		foreach my $dataset (keys %datasets)
		{
			my $dataname = $datasets{$dataset};
			$datanames{$dataname} = $dataset;
		}
	}

	# Ditto for the lists
	unless (scalar(keys %listdatanames))
	{
		foreach my $dataset (keys %listdatasets)
		{
			my $dataname = $listdatasets{$dataset};
			$listdatanames{$dataname} = $dataset;
		}
	}

	# Print record version
	# tag - record - dataset - len (short) - 2 (short)
	$out .= pack("CCCnn", 0x1c, 2, 0, 2, 2);

	# Iterate over data sets
	foreach my $key (keys %{$self->{_data}})
	{
		my $dataset = $datanames{$key};
		my $value   = $self->{_data}->{$key};

		if ($dataset == 0)
		{ Log("PackedIIMData: illegal dataname $key"); next; }

		my ($tag, $record) = (0x1c, 0x02);

		$out .= pack("CCCn", $tag, $record, $dataset, length($value));
		$out .= $value;
	}

	# Do the same for list data sets
	foreach my $key (keys %{$self->{_listdata}})
	{
		my $dataset = $listdatanames{$key};

		if ($dataset == 0)
		{ Log("PackedIIMData: illegal dataname $key"); next; }

		foreach my $value (@{$self->{_listdata}->{$key}})
		{
			my ($tag, $record) = (0x1c, 0x02);

			$out .= pack("CCCn", $tag, $record, $dataset, length($value));
			$out .= $value;
		}
	}

	return $out;
}

#
# PhotoshopIIMBlock
#
# Assembles the blob of Photoshop "resource data" that includes our
# fresh IIM data (from PackedIIMData) and the other Adobe parts we
# found in the file, if there were any.
#
sub PhotoshopIIMBlock
{
	my ($self, $otherparts, $data) = @_;
	my $resourceBlock;
	my $out;

	$resourceBlock .= "Photoshop 3.0";
	$resourceBlock .= pack("C", 0);
	# Photoshop identifier
	$resourceBlock .= "8BIM";
	# 0x0404 is IIM data, 00 is required empty string
	$resourceBlock .= pack("CCCC", 0x04, 0x04, 0, 0);
	# length of data as 32-bit, network-byte order
	$resourceBlock .= pack("N", length($data));
	# Now tack data on there
	$resourceBlock .= $data;
	# Pad with a blank if not even size
	$resourceBlock .= pack("C", 0) if (length($data) % 2 != 0);
	# Finally tack on other data
	$resourceBlock .= $otherparts if defined($otherparts);

	$out .= pack("CC", 0xff, 0xed); # JFIF start of block, APP13
	$out .= pack("n", length($resourceBlock) + 2); # length
	$out .= $resourceBlock;

	return $out;
}

#######################################################################
# Helpers, docs
#######################################################################

#
# Log: just prints a message to STDERR if $debugMode is on.
#
sub Log
{
	if ($debugMode)
	{
		my $message = shift;
		my $oldFh = select(STDERR);
	
		print "**IPTC** $message\n";
		
		select($oldFh);
	}
} 

#
# HexDump
#
# Very helpful when debugging.
#
sub HexDump
{
	my $dump = shift;
	my $len  = length($dump);
	my $offset = 0;
	my ($dcol1, $dcol2);

	while ($offset < $len)
	{
		my $temp = substr($dump, $offset++, 1);

		my $hex = unpack("H*", $temp);
		$dcol1 .= " " . $hex;
		if (ord($temp) >= 0x21 && ord($temp) <= 0x7e)
		{ $dcol2 .= " $temp"; }
		else
		{ $dcol2 .= " ."; }

		if ($offset % 16 == 0)
		{
			print $dcol1 . " | " . $dcol2 . "\n";
			undef $dcol1; undef $dcol2;
		}
	}

	if (defined($dcol1) || defined($dcol2))
	{
		print $dcol1 . " | " . $dcol2 . "\n";
		undef $dcol1; undef $dcol2;
	}
}

#
# JFIFDebugScan
#
# Also very helpful when debugging.
#
sub JFIFDebugScan
{
	my $filename = shift;
	open(FILE, $filename) or die "Can't open $filename: $!";

	# Skip past start of file marker
	my ($ff, $soi);
	read (FILE, $ff, 1) || return 0;
	read (FILE, $soi, 1);
	
	unless (ord($ff) == 0xff & ord($soi) == 0xd8)
	{
		Log("JFIFScan: invalid start of file");
		goto done;
	}

	# scan to 0xDA (start of scan), dumping the markers we see between
	# here and there.
	my $marker = JFIFNextMarker();

	while (ord($marker) != 0xda)
	{
		if (ord($marker) == 0)
		{ Log("Marker scan failed"); goto done; }

		if (ord($marker) == 0xd9)
		{Log("Marker scan hit end of image marker"); goto done; }

		if (JFIFSkipVariable() == 0)
		{ Log("JFIFSkipVariable failed"); return 0; }

		$marker = JFIFNextMarker();
	}

done:
	close(FILE);
}

# sucessful package load
1;

__END__

=head1 NAME

Image::IPTCInfo - Perl extension for extracting IPTC image meta-data

=head1 SYNOPSIS

  use Image::IPTCInfo;

  # Create new info object
  my $info = new Image::IPTCInfo('file-name-here.jpg');

  # Check if file had IPTC data
  unless (defined($info)) { die Image::IPTCInfo::Error(); }
    
  # Get list of keywords or supplemental categories...
  my $keywordsRef = $info->Keywords();
  my $suppCatsRef = $info->SupplementalCategories();
    
  # Get specific attributes...
  my $caption = $info->Attribute('caption/abstract');
    
  # Create object for file that may or may not have IPTC data.
  $info = create Image::IPTCInfo('file-name-here.jpg');
    
  # Add/change an attribute
  $info->SetAttribute('caption/abstract', 'Witty caption here');

  # Save new info to file 
  ##### See disclaimer in 'SAVING FILES' section #####
  $info->Save();
  $info->SaveAs('new-file-name.jpg');

=head1 DESCRIPTION

Ever wish you add information to your photos like a caption, the place
you took it, the date, and perhaps even keywords and categories? You
already can. The International Press Telecommunications Council (IPTC)
defines a format for exchanging meta-information in news content, and
that includes photographs. You can embed all kinds of information in
your images. The trick is putting it to use.

That's where this IPTCInfo Perl module comes into play. You can embed
information using many programs, including Adobe Photoshop, and
IPTCInfo will let your web server -- and other automated server
programs -- pull it back out. You can use the information directly in
Perl programs, export it to XML, or even export SQL statements ready
to be fed into a database.

=head1 USING IPTCINFO

Install the module as documented in the README file. You can try out
the demo program called "demo.pl" which extracts info from the images
in the "demo-images" directory.

To integrate with your own code, simply do something like what's in
the synopsys above.

The complete list of possible attributes is given below. These are as
specified in the IPTC IIM standard, version 4. Keywords and categories
are handled differently: since these are lists, the module allows you
to access them as Perl lists. Call Keywords() and Categories() to get
a reference to each list.

=head2 NEW VS. CREATE

You can either create an object using new() or create():

  $info = new Image::IPTCInfo('file-name-here.jpg');
  $info = create Image::IPTCInfo('file-name-here.jpg');

new() will create a new object only if the file had IPTC data in it.
It will return undef otherwise, and you can check Error() to see what
the reason was. Using create(), on the other hand, always returns a
new IPTCInfo object if there was data or not. If there wasn't any IPTC
info there, calling Attribute() on anything will just return undef;
i.e. the info object will be more-or-less empty.

If you're only reading IPTC data, call new(). If you want to add or
change info, call create(). Even if there's no useful stuff in the
info object, you can then start adding attributes and save the file.
That brings us to the next topic....

=head2 MODIFYING IPTC DATA

You can modify IPTC data in JPEG/JFIF files and save the file back to
disk. Here are the commands for doing so:

  # Set a given attribute
  $info->SetAttribute('iptc attribute here', 'new value here');

  # Clear the keywords or supp. categories list
  $info->ClearKeywords();
  $info->ClearSupplementalCategories();

  # Add keywords or supp. categories
  $info->AddKeyword('frob');

  # You can also add a list reference
  $info->AddKeyword(['frob', 'nob', 'widget']);

=head2 SAVING FILES

With JPEG files you can add/change attributes, add keywords, etc., and
then call:

  $info->Save();
  $info->SaveAs('new-file-name.jpg');

This will save the file with the updated IPTC info. Please only run
this on *copies* of your images -- not your precious originals! --
until I know for a fact that the saving code is bulletproof. I know it
works on my machine, but I want to ensure that field reports are good
before I really trust it.

=head2 XML AND SQL EXPORT FEATURES

IPTCInfo also allows you to easily generate XML and SQL from the image
metadata. For XML, call:

  $xml = $info->ExportXML('entity-name', \%extra-data,
                          'optional output file name');

This returns XML containing all image metadata. Attribute names are
translated into XML tags, making adjustments to spaces and slashes for
compatibility. (Spaces become underbars, slashes become dashes.) You
provide an entity name; all data will be contained within this entity.
You can optionally provides a reference to a hash of extra data. This
will get put into the XML, too. (Example: you may want to put info on
the image's location into the XML.) Keys must be valid XML tag names.
You can also provide a filename, and the XML will be dumped into
there. See the "demo.pl" script for examples.

For SQL, it goes like this: 

  my %mappings = (
       'IPTC dataset name here' => 'your table column name here',
       'caption/abstract'       => 'caption',
       'city'                   => 'city',
       'province/state'         => 'state); # etc etc etc.
    
  $statement = $info->ExportSQL('mytable', \%mappings, \%extra-data);

This returns a SQL statement to insert into your given table name a
set of values from the image. You pass in a reference to a hash which
maps IPTC dataset names into column names for the database table. As
with XML export, you can also provide extra information to be stuck
into the SQL.

=head1 IPTC ATTRIBUTE REFERENCE

  object name               originating program              
  edit status               program version                  
  editorial update          object cycle                     
  urgency                   by-line                          
  subject reference         by-line title                    
  category                  city                             
  fixture identifier        sub-location                     
  content location code     province/state                   
  content location name     country/primary location code    
  release date              country/primary location name    
  release time              original transmission reference  
  expiration date           headline                         
  expiration time           credit                           
  special instructions      source                           
  action advised            copyright notice                 
  reference service         contact                          
  reference date            caption/abstract                 
  reference number          writer/editor                    
  date created              image type                       
  time created              image orientation                
  digital creation date     language identifier
  digital creation time

  custom1 - custom20: NOT STANDARD but used by Fotostation.
  IPTCInfo also supports these fields.

=head1 KNOWN BUGS

IPTC meta-info on MacOS may be stored in the resource fork instead
of the data fork. This program will currently not scan the resource
fork.

I have heard that some programs will embed IPTC info at the end of the
file instead of the beginning. The module will currently only look
near the front of the file. If you have a file with IPTC data that
IPTCInfo can't find, please contact me! I would like to ensure
IPTCInfo works with everyone's files.

=head1 AUTHOR

Josh Carter, josh@multipart-mixed.com

=head1 SEE ALSO

perl(1).

=cut
