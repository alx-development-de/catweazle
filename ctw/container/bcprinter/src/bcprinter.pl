#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Getopt::Long;
use Pod::Usage;

use File::Spec;
use IO::Socket::INET;

use Net::Stomp;
use JSON;

use Data::Dumper;

# If the settings are passed using environment variables, these are set, otherwise the
# default values are used
my $opt_loglevel = defined($ENV{'CABLAB_LOGLEVEL'}) ? $ENV{'CABLAB_LOGLEVEL'} : 'INFO';
my $opt_stomp_host = defined($ENV{'CABLAB_MQ_HOST'}) ? $ENV{'CABLAB_MQ_HOST'} : 'kalisto';
my $opt_stomp_port = defined($ENV{'CABLAB_MQ_PORT'}) ? $ENV{'CABLAB_MQ_PORT'} : '61613';
my $opt_stomp_user = defined($ENV{'CABLAB_MQ_USER'}) ? $ENV{'CABLAB_MQ_USER'} : 'admin';
my $opt_stomp_passwd = defined($ENV{'CABLAB_MQ_PASSWD'}) ? $ENV{'CABLAB_MQ_PASSWD'} : 'admin';
my $opt_stomp_queue = defined($ENV{'CABLAB_MQ_QUEUE'}) ? $ENV{'CABLAB_MQ_QUEUE'} : '/queue/cabinetlab';
my $opt_lbl_template = File::Spec->rel2abs(defined($ENV{'CABLAB_LBL_TEMPLATE'}) ? $ENV{'CABLAB_LBL_TEMPLATE'} : '/usr/src/template.lbl');
my $opt_printer_ip = defined($ENV{'CABLAB_PRINTER_IP'}) ? $ENV{'CABLAB_PRINTER_IP'} : '127.0.0.1';
my $opt_printer_port = defined($ENV{'CABLAB_PRINTER_PORT'}) ? $ENV{'CABLAB_PRINTER_PORT'} : 9100;

# It is also possible to use command line parameters to pass some settings to the
# appictaion.
GetOptions(
    'loglevel=s' => \$opt_loglevel
) or die "Invalid options passed to $0\n";

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($opt_loglevel)));
my $logger = Log::Log4perl->get_logger();

# Establishing the connection to the MQ service
$logger->info("Establishing connection to [${opt_stomp_host}:${opt_stomp_port}] MQ services");
my $stomp_destination = $opt_stomp_queue;
my $stomp = Net::Stomp->new({ hostname => $opt_stomp_host, port => $opt_stomp_port });
$stomp->connect({ login => $opt_stomp_user, passcode => $opt_stomp_passwd });
$logger->info("Connection established, subscribing [$opt_stomp_queue]");
$stomp->subscribe(
    { destination               => $opt_stomp_queue,
        'ack'                   => 'client',
        'activemq.prefetchSize' => 1
    }
);
# Generating the JSON decoder
my $json = JSON->new->allow_nonref;
$logger->info("Connections established, waiting for incoming events");
while (1) {
    $logger->debug("Waiting for incoming event");
    my $frame = $stomp->receive_frame;
    if (!defined $frame) {
        # maybe log connection problems
        next; # will reconnect automatically
    }
    # Processing the message content
    my $message = $json->decode($frame->body);
    my $uuid = $message->{'project'}->{'id'};
    $logger->debug("UUID [$uuid] received, printing barcode");
    &print_barcode($uuid);
    $stomp->ack({ frame => $frame });
}

$stomp->disconnect();
exit(0);

# -------------------------------------------------------------------

sub print_barcode($;) {

    # Receiving the uuid from parameters
    my $uuid = shift();

    # Loading the template file
    $logger->debug("Loading label template from [$opt_lbl_template]");
    open(LBL, '<', $opt_lbl_template) or $logger->logdie("Can't open LBL template [$opt_lbl_template]: $!");
    my @lbl_template = <LBL>;
    close LBL;
    # Replacing the placeholder for the QR content inside the label definition
    $logger->debug("Inserting UUID [$uuid] information");
    for (my $i = 0; $i < scalar(@lbl_template); $i++) {
        $lbl_template[$i] =~ s/\{\[QRCONTENT\]\}/$uuid/g;
    }

    # Sending the label to the printer
    my $sock = IO::Socket::INET->new(
        Domain   => AF_INET,
        PeerAddr => $opt_printer_ip,
        PeerPort => $opt_printer_port,
        Proto    => 'tcp',
    ) or die "failed to create socket: $!\n";

    foreach my $line (@lbl_template) {
        #print($line);
        $sock->send($line, 0);
    }
    $sock->close();
}
