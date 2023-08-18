#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Config::IniFiles;
use Getopt::Long;
use Pod::Usage;

use File::Spec;
use File::Copy;

use Imager::QRCode;
use Data::Uniqid qw(uniqid);

use Net::Stomp;
use JSON;

# If the settings are passed using environment variables, these are set, otherwise the
# default values are used
my $opt_loglevel = defined($ENV{'CABLAB_LOGLEVEL'}) ? $ENV{'CABLAB_LOGLEVEL'} : 'INFO';
my $opt_source_dir = defined($ENV{'CABLAB_SCANNER_DIR'}) ? $ENV{'CABLAB_SCANNER_DIR'} : 'data';
my $opt_stomp_host = defined($ENV{'CABLAB_MQ_HOST'}) ? $ENV{'CABLAB_MQ_HOST'} : 'kalisto';
my $opt_stomp_port = defined($ENV{'CABLAB_MQ_PORT'}) ? $ENV{'CABLAB_MQ_PORT'} : '61613';
my $opt_stomp_user = defined($ENV{'CABLAB_MQ_USER'}) ? $ENV{'CABLAB_MQ_USER'} : 'admin';
my $opt_stomp_passwd = defined($ENV{'CABLAB_MQ_PASSWD'}) ? $ENV{'CABLAB_MQ_PASSWD'} : 'admin';
my $opt_stomp_queue = defined($ENV{'CABLAB_MQ_QUEUE'}) ? $ENV{'CABLAB_MQ_QUEUE'} : '/queue/cabinetlab';

# It is also possible to use command line parameters to pass some settings to the
# appictaion.
GetOptions(
    'loglevel=s'    => \$opt_loglevel,
    'scanner-dir=s' => \$opt_source_dir
) or die "Invalid options passed to $0\n";

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($opt_loglevel)));
my $logger = Log::Log4perl->get_logger();

# converting the source path from relative to absolute representation
$opt_source_dir = File::Spec->rel2abs($opt_source_dir);

# Establishing the connection to the MQ service
$logger->info("Establishing connection to [${opt_stomp_host}:${opt_stomp_port}] MQ services");
my $stomp = Net::Stomp->new({ hostname => $opt_stomp_host, port => $opt_stomp_port });
$stomp->connect({ login => $opt_stomp_user, passcode => $opt_stomp_passwd });

# Initializing the QR code generator
my $qrcode = Imager::QRCode->new(
    size          => 5,
    margin        => 5,
    version       => 1,
    level         => 'M',
    casesensitive => 1,
    lightcolor    => Imager::Color->new(255, 255, 255),
    darkcolor     => Imager::Color->new(0, 0, 0),
);

$logger->info("Service started...");
$logger->info("Observing input directory [$opt_source_dir]");
while (-d $opt_source_dir) {
    opendir(my $dh, $opt_source_dir) || $logger->logdie("Can't open directory [$opt_source_dir]: $!");
    $logger->debug("Scanning input directory [$opt_source_dir]");
    my @project_dirs = grep {/^[^.]/ && -d "$opt_source_dir/$_"} readdir($dh);
    closedir $dh;

    # Waiting for a few seconds to avoid race conditions
    sleep(2); # TODO: Better blocking algorithm should be implemented

    # Converting the source files to the base xml format
    foreach my $dir (@project_dirs) {
        # Building the complete absolute path name of the project directory
        # and ignore it, if not existing. This happens, if the folder has been
        # renamed meanwhile.
        my $project_dir = File::Spec->catfile($opt_source_dir, $dir);
        next unless (-d $project_dir);

        # Let's have a look, if the folder has already been processed and
        # an UUID has been generated
        my $uuid_file = File::Spec->catfile($project_dir, 'uuid.dat');
        if (-f $uuid_file) {
            # The directory has already been detected and an uuid and barcode is
            # present. Now the content has to bee parsed and organized if it applies
            # to a defined rule.
            my $cfg_filename = File::Spec->catfile($opt_source_dir, "cabinetlab.ini");
            $logger->debug("Loading the inspection definition [$cfg_filename]");
            my $cfg = Config::IniFiles->new( -file => $cfg_filename );
            unless( defined($cfg) ) {
                $logger->error("The cabinetlab configuration couldn't be loaded from [$cfg_filename]");
                next;
            }

            $logger->debug("Inspection content of [$project_dir]");
            # Reading the files in the project folder except the uuid- and dot-files
            opendir(my $dir, $project_dir) || $logger->logdie("Can't open directory [$project_dir]: $!");
            my @files = grep { !/^\./ && !/^uuid\.(dat|bmp)/ } readdir($dir);
            close($dir);
            # Iterating over the sections and looking for required activities
            foreach my $section ( $cfg->Sections() ) {
                my $filter = $cfg->val( $section, 'filter');
                $logger->debug("Inspecting action item [$section] with filter [$filter]");

                # Reading the desired target directory from section and inspecting if it
                # is available, otherwise skipping this section with an error message.
                my $target_dir = File::Spec->rel2abs($cfg->val( $section, 'target' ));
                unless(-d $target_dir) {
                    $logger->error("The target directory [$target_dir] is not available, skipping action item [$section]");
                    next;
                }

                # Loading the uuid from dat-file content
                open( UUID, '<', $uuid_file ) or $logger->logdie("Can't open UUID: $!");
                my $uuid = <UUID>; chomp($uuid);
                close UUID;
                unless(defined( $uuid )) {
                    $logger->error("The UUID couldn't be accessed");
                    next;
                }

                # Now, let's have a look, if some files have been found. If there is more than one
                # file accepted by the filter, only the last one is used, cause the previous will
                # be overwritten during the search loop.
                foreach my $file (@files) {
                    if( $file =~ /$filter/) {
                        $logger->debug("File [$file] detected");
                        my $source_file = File::Spec->catfile($project_dir, $file);
                        my $target_file = File::Spec->catfile($target_dir, $uuid);
                        if(defined($cfg->val($section,'extension')) && $cfg->val($section,'extension') =~ m/(1|ja|yes|true)/i) {
                            if( $source_file =~ m/(\.[^.]+)$/i ) {
                                $logger->debug("Preserving extension [$1]");
                                $target_file .= $1;
                            }
                        }

                        if( !-e $target_file || (stat $target_file)[9]<(stat $source_file)[9] ) {
                            $logger->info("Change detected, moving [$source_file] to [$target_file]");
                            copy($source_file, $target_file)
                                or $logger->error("File copy process failed: $!");
                        }
                    }
                }
            }

            # As the uuid has been already generated, we skip the following processes
            next;
        }

        # A new project directory is available, now generate the uuid and writing
        # it inside the folder
        $logger->info("New project directory [$project_dir] detected");

        # Generating the UUID
        my $uuid = uniqid;
        $uuid =~ s/[yzYZ]/X/gi; # Substitute Y and Z to avoid problems with QWERTZ and QWERTY

        my $json = JSON->new->allow_nonref;
        my %message = (
            'project' => {
                'id'   => $uuid,
                'path' => $project_dir
            },
            'action'  => 'created'
        );

        # Eval this block to avoid system crashes by errors caused by
        # race conditions
        eval {
            # Now let's write the UUID text into the project folder
            $logger->info("Project UUID [$uuid] generated");
            open(FH, '>', $uuid_file) or $logger->logdie($!);
            print FH $uuid;
            close(FH);

            # Generating a QR code additionally for further use as image
            my $img = $qrcode->plot($uuid);
            $img->write(file => File::Spec->catfile($project_dir, 'uuid.bmp'))
                or $logger->logdie("Failed to write: " . $img->errstr);

            # Sending the MQ message to the local broker
            $logger->info("Sending information to the MQ service at [$opt_stomp_queue]");
            $stomp->send({
                destination => $opt_stomp_queue,
                body => $json->encode(\%message)
            });
        };
        $logger->error($@) if ($@);
    }
}

$logger->error("Seems there is a problem with the source directory [$opt_source_dir]. Perhaps, it can't be accessed.");
$stomp->disconnect;
exit(0);
