#!/usr/bin/perl


# Perl c_rehash script, scan all files in a directory
# and add symbolic links to their hash values.

my $openssl;
my $symlink_exists = eval {symlink("",""); 1};


if(defined $ENV{OPENSSL}) {
    $openssl = $ENV{OPENSSL};
} else {
    $openssl = "openssl";
    $ENV{OPENSSL} = $openssl;
}

my $osslver = `"$openssl" version`;

if ($? != 0) {
    print STDERR "Unable to find the $openssl binary\n";
    exit 1;
}
print "Found OpenSSL version: $osslver\n";


foreach (@ARGV) {
    if(-d $_ and -w $_) {
	hash_dir($_);
    }
}

sub hash_dir {
    my %hashlist;
    print "Doing $_[0]\n";
    chdir $_[0];
    opendir(DIR, ".");
    my @flist = readdir(DIR);

    # Delete any existing symbolic links
    foreach (grep {/^[\da-f]+\.r{0,1}\d+$/} @flist) {
	if(-l $_) {
	    unlink $_;
	}
    }
    closedir DIR;
    FILE: foreach $fname (grep {/\.pem$/} @flist) {
	# Check to see if certificates and/or CRLs present.
	my ($cert, $crl) = check_file($fname);
	if(!$cert && !$crl) {
	    print STDERR "WARNING: $fname does not contain a certificate or CRL: skipping\n";
	    next;
	}
	link_hash_cert($fname) if($cert);
	link_hash_crl($fname) if($crl);
    }
}

sub check_file {
    my ($is_cert, $is_crl) = (0,0);
    my $fname = $_[0];
    open IN, $fname;
    while(<IN>) {
	if(/^-----BEGIN (.*)-----/) {
	    my $hdr = $1;
	    if($hdr =~ /^(X509 |TRUSTED |)CERTIFICATE$/) {
		$is_cert = 1;
		last if($is_crl);
	    } elsif($hdr eq "X509 CRL") {
		$is_crl = 1;
		last if($is_cert);
	    }
	}
    }
    close IN;
    return ($is_cert, $is_crl);
}


# Link a certificate to its subject name hash value, each hash is of
# the form <hash>.<n> where n is an integer. If the hash value already exists
# then we need to up the value of n, unless its a duplicate in which
# case we skip the link. We check for duplicates by comparing the
# certificate fingerprints

sub link_hash_cert {
    my $fname = $_[0];
    my ($hash, $fprint) = `"$openssl" x509 -hash -fingerprint -noout -in "$fname"`;

    chomp $hash;
    chomp $fprint;
    $fprint =~ s/^.*=//;
    $fprint =~ tr/://d;
    my $suffix = 0;
    # Search for an unused hash filename
    while(exists $hashlist{"$hash.$suffix"}) {
	# Hash matches: if fingerprint matches its a duplicate cert
	if($hashlist{"$hash.$suffix"} eq $fprint) {
	    print STDERR "WARNING: Skipping duplicate certificate $fname\n";
	    return;
	}
	$suffix++;
    }
    $hash .= ".$suffix";
    print "$fname => $hash\n";
    if ($symlink_exists) {
	symlink $fname, $hash;
    } else {
	file_cp($fname, $hash);
    }
    $hashlist{$hash} = $fprint;
}

# Same as above except for a CRL. CRL links are of the form <hash>.r<n>

sub link_hash_crl {
    my $fname = $_[0];
    my ($hash, $fprint) = `"$openssl" crl -hash -fingerprint -noout -in "$fname"`;

    chomp $hash;
    chomp $fprint;
    $fprint =~ s/^.*=//;
    $fprint =~ tr/://d;
    my $suffix = 0;
    # Search for an unused hash filename
    while(exists $hashlist{"$hash.r$suffix"}) {
	# Hash matches: if fingerprint matches its a duplicate cert
	if($hashlist{"$hash.r$suffix"} eq $fprint) {
	    print STDERR "WARNING: Skipping duplicate CRL $fname\n";
	    return;
	}
	$suffix++;
    }
    $hash .= ".r$suffix";
    print "$fname => $hash\n";
    if ($symlink_exists) {
	symlink $fname, $hash;
    } else {
	file_cp($fname, $hash);
    }
    $hashlist{$hash} = $fprint;
}

sub file_cp {
    my ($fsrc, $fdst) = @_;

    if (!open(SFIL, "$fsrc")) {
	print STDERR "unable to open $fsrc\n";
	return 0;
    }
    if (!open(DFIL, ">$fdst")) {
	print STDERR "unable to create $fdst\n";
	close SFIL;
	return 0;
    }
    binmode SFIL;
    binmode DFIL;
    for (;;) {
	my $data;
	my $size = read(SFIL, $data, 10000);
	
	if (!defined($size)) {
	    print STDERR "unable to read file: $fsrc\n";
	    close SFIL;
	    close DFIL;
	    return 0;
	}
	if (!$size) {
	    last;
	}
	if (!print DFIL $data) {
	    print STDERR "unable to write file: $fdst\n";
	    close SFIL;
	    close DFIL;
	    return 0;
	}
    }
    close SFIL;
    close DFIL;
    return 1;
}

