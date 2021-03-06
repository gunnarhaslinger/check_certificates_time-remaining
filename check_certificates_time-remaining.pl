#!/usr/bin/perl -w
use strict;
use Crypt::OpenSSL::X509;       # requires: apt install libcrypt-openssl-x509-perl
use DateTime::Format::Strptime; # requires: apt install libdatetime-format-strptime-perl
use Getopt::Long qw(GetOptions);
use Data::Dumper;

my $verbose; my $help; my $debug;
my $limit = 20;
my $LetsEncrytpCertDir="/etc/letsencrypt/live";
my $ApacheConfigs="/etc/apache2/sites-enabled/*";
my %certlist;
my $renew = 0;

GetOptions('limit=i' => \$limit, 'v' => \$verbose, 'd|vv' => \$debug, 'help|?|h' => \$help, 'renew' => \$renew);

if ($help) {
print "Commandline arguments:\n";
print "Without Arguments: Only shows Certificates valid for less than 25 days.\n";
print "-limit=20 ... show only certificates valid for less than n (20) days\n";
print "-v ... Verbose Output\n";
print "-vv ... Debug Output\n";
print "-renew ... erneuere automatisch\n";
exit(1);
}

$verbose++ if $debug;

# Lets Encrypt Certificates from Filesystem
opendir my $DirHandle, $LetsEncrytpCertDir or die "$0: opendir: $!";
while (defined(my $name = readdir $DirHandle)) {
      next unless -d "$LetsEncrytpCertDir/$name"; next if $name =~ /^\./; # Enumarate Directories
      $name = "$LetsEncrytpCertDir/$name/fullchain.pem";
      if (-e $name) {
         print "Adding to List: $name\n" if $debug;
         $certlist{$name}++;
      } else { print "Warning: File not found: $name\n"; }
}
closedir($DirHandle);

# Get all Certificates used by Apache
foreach my $certfile (`egrep -i "SSLCertificateFile" $ApacheConfigs`) {
  chomp($certfile);
  print "Found Apache Entry: $certfile\n" if $debug;
  next if $certfile !~ /:\s*SSLCertificateFile\s+(.+)/i;
  my $cert = $1;
  print "Adding to List: " . $cert . "\n" if $debug;
  $certlist{$cert}++;
}

sub checkcert($)
{ my $certfile=shift;
  my $cert = Crypt::OpenSSL::X509->new_from_file($certfile);
  #print $cert->notAfter() . "\n"; # Apr 11 17:24:00 2017 GMT
  my $date_valid = DateTime::Format::Strptime->new(pattern => '%b %d %H:%M:%S %Y %Z', on_error  => 'croak')->parse_datetime($cert->notAfter());
  my $days_left = $date_valid->delta_days(DateTime->now())->delta_days();
  my $name = $cert->subject(); $name = $1 if $name =~ /CN=(\S+)/i;
  if ($days_left <= $limit || $verbose) {
     print "$name" . " "x(30-length($name)) . " "x(4-length($days_left)) . $days_left . " Days difference now to " . $date_valid->strftime("%d.%m.%Y %H:%M:%S %Z") . "\n";
     print " "x35 . "File: $certfile\n";
     my $SAN = $cert->extensions_by_name()->{'subjectAltName'}->value();
     #print "### $SAN\n";
     if ($SAN =~ /^\#/) { # if SAN is encoded as HEX-String
         $SAN =~ s/^\#//; # cut of the starting "#" and decode HEX to ASCII-String
         $SAN =~ s/(..)/chr(hex($1))/eg;
     }
     $SAN =~ s/[^\w\d\.-]/./g;
     $SAN =~ s/^\dU?\.+//;
     $SAN =~ s/^..\.\.//; # am Beginn zwei Zeichen + 2 Punkte - dann entfernen
     $SAN =~ s/^.\.\.//; # am Beginn ein Zeichen + 2 Punkte - dann entfernen
     $SAN =~ s/\.\./\n                                            /g;
     print " "x35 . "AltName: " . $SAN . "\n";
     if ($renew) {
        print "=== START automatische Erneuerung $name ===\n";
        my $renewscript="./anforderung_$name.sh";
        if (! -f $renewscript) { print "   Error: Script fehlt: $renewscript\n";
           } else
           { system($renewscript);
           }
        print "=== ENDE  automatische Erneuerung $name ===\n";
     }
  }
}

foreach my $certfile (keys %certlist) { checkcert($certfile); }
exit(0);
