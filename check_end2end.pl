#!/usr/bin/perl
# vim: se ts=4 et syn=perl:

# check_end2end.pl - Simple configurable end-to-end probe plugin for Nagios
#
#     Copyright (C) 2016-2017 Giacomo Montagner <giacomo@entirelyunlike.net>
#
#     This program is free software: you can redistribute it and/or modify
#     it under the same terms as Perl itself, either Perl version 5.8.4 or,
#     at your option, any later version of Perl 5 you may have available.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
#
#
#   CHANGELOG:
#
#       2016-05-19T08:46:55+0200
#           First release.
#
#       2016-05-24T11:13:44+0200 v1.0.1
#           - Removed "Export" as parent to Monitoring::Plugin::End2end;
#           - Added TODO to make steps optional
#
#       2016-05-25T09:06:44+0200 v1.0.2
#           - Filled in contact/bug/copyright details in perl POD documentation
#
#       2016-05-26T14:19:26+0200 v1.1.0
#           - Added support for "on_failure" configuration directive
#           - Added more documentation about configuration file format
#
#       2016-05-29T03:05:41+0200 v1.2.0
#           - Added -e flag to interpolate environment variables
#           - Added -E flag to allow empty vars
#           - Added --var flag to pass variables on command line
#
#       2016-06-10T23:06:39+0200 v1.3.0
#           - Added -D flag to dump the downloaded pages to a directory
#             (with debugging purposes)
#
#       2016-07-20T11:07:13+0200 v1.4.0
#           - Added grep_re|grep_str options to configuration file, along with
#             on_grep_failure.
#
#       2016-07-22T09:21:12+0200 v1.4.1
#           - Modified default behaviour in case of pattern-matching-failed to
#             a fatal error (immediate exit on match failure, unless severity
#             is lowered using on_grep_failure).
#
#       2016-08-03T03:21:53+02:00 v1.5.0
#           - Added support for proxy
#           - Added support for basic http authentication
#
#       2017-01-17T14:03:08+01:00 v1.5.1
#           - Added .html extension to the name of the files generated via the
#             -D flag.
#
#       2017-01-17T15:26:33+01:00 v1.6.0
#           - Added grep_err_str/grep_err_re/on_err_grep_match parameters to the
#             configuration, to allow for a negative (error) string match.
#
#       2017-02-24T11:27:28+01:00 v1.6.1
#           - Copyright update 2017
#           - Version updates throughout documentation.
#
#

use strict;
use warnings;
use version; our $VERSION = qv(1.6.1);
use v5.010.001;
use utf8;
use File::Basename qw(basename);

use Config::General;
use Monitoring::Plugin;
use Time::HiRes qw(time);

use subs qw(
    debug
);








# ------------------------------------------------------------------------------
#  Globals
# ------------------------------------------------------------------------------
our $plugin_name = basename( $0 );




# ------------------------------------------------------------------------------
#  Command line initialization
# ------------------------------------------------------------------------------

# This plugin's initialization - see https://metacpan.org/pod/Monitoring::Plugin
#   --verbose, --help, --usage, --timeout and --host are defined automatically.
my $np = Monitoring::Plugin::End2end->new(
    usage => "Usage: %s [-v|--verbose] [-t <timeout>] [-d|--debug] [-M|--manual] "
          . "[-D|--dumpPages=/dump/directory] [-e|--useEnvVars] [-E|--allowEmptyVars] "
          . "[-c|--critical=<threshold>] [-w|--warning=<threshold>] "
          . "[-C|--totcritical=<threshold>] [-W|--totwarning=<threshold>] "
          . "[--var VAR=VALUE [--var VAR2=VALUE2 [ ... ] ] ] "
          . "-f|--configFile=<cfgfile>",
    version => $VERSION,
    blurb   => "This plugin uses LWP::UserAgent to fake a website navigation"
                . " as configured in the named configuration file.",
);

# Command line options
$np->add_arg(
    spec => 'debug|d',
    help => qq{-d, --debug\n   Print debugging messages to STDERR. }
          . qq{Package Data::Dumper is required for debug.},
);

$np->add_arg(
    spec => 'dumpPages|D=s',
    help => qq{-D, --dumpPages=/dump/directory\n   Writes the output of each step }
          . qq{into a file under the named destination directory. The name of the file }
          . qq{will be the same as the name of the corresponding step. Path::Tiny is }
          . qq{required to dump page content.},
);

$np->add_arg(
    spec => 'warning|w=s',
    help => qq{-w, --warning=INTEGER:INTEGER\n}
          . qq{   Warning threshold for each single step.\n}
          . qq{   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT }
          . qq{for the threshold format, or run $plugin_name -M (requires perldoc executable).},
);

$np->add_arg(
    spec => 'critical|c=s',
    help => qq{-c, --critical=INTEGER:INTEGER\n}
          . qq{   Critical threshold for each single step.\n}
          . qq{   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT }
          . qq{for the threshold format, or run $plugin_name -M (requires perldoc executable). },
);

$np->add_arg(
    spec => 'totwarning|W=s',
    help => qq{-W, --totwarning=INTEGER:INTEGER\n}
          . qq{   Warning threshold for the whole process.\n}
          . qq{   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT }
          . qq{for the threshold format, or run $plugin_name -M (requires perldoc executable).},
);

$np->add_arg(
    spec => 'totcritical|C=s',
    help => qq{-C, --totcritical=INTEGER:INTEGER\n}
          . qq{   Critical threshold for the whole process.\n}
          . qq{   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT }
          . qq{for the threshold format, or run $plugin_name -M (requires perldoc executable). },
);

$np->add_arg(
    spec => 'configFile|f=s',
    help => qq{-f, --configFile=/path/to/file.\n   Configuration }
          . qq{of the steps to be performed by this plugin. }
          . qq{See "perldoc $plugin_name" for details con configuration format, }
          . qq{or run $plugin_name -M},
);

$np->add_arg(
    spec => 'useEnvVars|e',
    help => qq{-e, --useEnvVars\n}
          . qq{   Interpolate variables in configuration file using enviroment variables }
          . qq{also. Default: NO. },
);

$np->add_arg(
    spec => 'allowEmptyVars|E',
    help => qq{-E, --allowEmptyVars\n}
          . qq{   By default, Config::General will croak if it tries to interpolate an }
          . qq{undefined variable. Use this option to turn off this behaviour.},
);

$np->add_arg(
    spec => 'var=s@',
    help => qq{--var <VAR=VALUE>\n}
          . qq{   Specify this option (even multiple times) to pass variables to this }
          . qq{plugin on the command line. These variables will be interpolated in the }
          . qq{configuration file, as if they were found inside environment. This automatically }
          . qq{turns on --useEnvVars flag.},
);

$np->add_arg(
    spec => 'useEnvProxy|P',
    help => qq{-P, --useEnvProxy\n}
          . qq{   Get proxy configuration from environment variables (you can use --var to pass }
          . qq{environment variables like http_proxy/https_proxy, and so on, if they're not in your }
          . qq{environment already)},
);

$np->add_arg(
    spec => 'manual|M',
    help => qq{-M, --manual\n   Show plugin manual (requires perldoc executable).},
);




# It would be easy to do this and then die() peacefully from everywhere it's
# required, but it would break any eval{} in the code from here to everywhere,
# so it cannot be done. I document it here so no one else is tempted to do
# this.
# $SIG{ __DIE__ } = sub {
#   $np->plugin_die(@_);
# };



# ------------------------------------------------------------------------------
#  Command line parsing
# ------------------------------------------------------------------------------

# Parse @ARGV and process standard arguments (e.g. usage, help, version)
$np->getopts;
my $opts = $np->opts();

if ($opts->manual()) {
    exec(qq{\$(which perldoc) $0});
}

if ($opts->debug) {
    require Data::Dumper;
    *debug = sub { say STDERR "DEBUG :: ", @_; };
    *ddump = sub { Data::Dumper->Dump( @_ ); };
} else {
    *debug = sub { return; };
    *ddump = *debug;
}

if ($opts->dumpPages) {
    require Path::Tiny;
    require File::Spec;
    *writepage = sub {
        debug qq{Dumping step "$_[0]" to }. $opts->dumpPages();
        Path::Tiny::path(
            File::Spec->catfile(
                $opts->dumpPages(), $_[0] . ".html"
            )
        )->spew( $_[1] );
    };
} else {
    *writepage = sub { return; };
}

unless ($opts->configFile()) {
    $np->plugin_die("Missing mandatory option: --configFile|-f");
}

my $useEnv = $opts->useEnvVars() || 0;
if (defined( my $vars = $opts->var() )) {
    $useEnv = 1;
    $np->plugin_die("Cannot parse variables passed via --var flag")
        unless ref( $vars ) && ref( $vars ) eq 'ARRAY';

    for my $vardef (@$vars) {
        my ($name, $val) = split('=', $vardef, 2);
        $np->plugin_die("Cannot parse variable definition: $vardef")
            unless defined($name) && defined($val);

        $ENV{$name} = $val;
    }
}


# ------------------------------------------------------------------------------
#  External configuration loading
# ------------------------------------------------------------------------------

# Read configuration file
my $conf = Config::General->new(
    -ConfigFile      => $opts->configFile(),
    -InterPolateVars => 1,
    -InterPolateEnv  => $useEnv,
    -StrictVars      => ! $opts->allowEmptyVars(),
    -ExtendedAccess  => 1,
);

if ($conf->exists("Monitoring::Plugin::shortname")) {
    $np->shortname( $conf->value("Monitoring::Plugin::shortname") );
}



# ------------------------------------------------------------------------------
#  Global configurations
# ------------------------------------------------------------------------------

# Prepare user agent for the requests
my $ua = Monitoring::Plugin::End2end::UserAgent->new( $conf )
    or $np->plugin_die("Error initializing UserAgent: ". $Monitoring::Plugin::End2end::UserAgent::reason);
   $ua->env_proxy() if $opts->useEnvProxy();

# Get the steps from configuration
my $steps = Steps->new( $conf->hash("Step") );

# Check for thresholds before performing steps
my @step_names = $steps->list();
my $num_steps = @step_names;

my $warns = Thresholds->new( $opts->warning(),  @step_names );
debug "WARNING THRESHOLDS: ", ddump([$warns], ['warns']);
my $crits = Thresholds->new( $opts->critical(), @step_names );
debug "CRITICAL THRESHOLDS: ", ddump([$crits], ['crits']);


# ------------------------------------------------------------------------------
#  MAIN :: Do the check
# ------------------------------------------------------------------------------
if ($opts->timeout()) {
    $SIG{ALRM} = sub {
        $np->plugin_die("Operation timed out after ". $opts->timeout(). "s" );
    };

    alarm $opts->timeout();
}

my $totDuration = 0;
# Perform each configured step
STEP:
for my $step_name ( @step_names ) {

    debug "Performing step: ", $step_name;

    my $step = $steps->step( $step_name )
        or $np->plugin_die("Malformed configuration file -- cannot proceed on step $step_name; error token was: ". $Step::reason);

    debug "URL: ", $step->url();
    debug "Data: ", ddump([ $step->data() ])
        if $step->data();
    debug "Method: ", $step->method();
    debug "Auth:   ", join(":", $step->auth_basic_credentials())
        if $step->has_basic_auth;

    my $response;
    my $method = $step->method();

    my $before = time();
    if (defined( $step->data() )) {
        $response = $ua->$method(
            $step->url(),
            $step->data(),
        );
    } else {
        $response = $ua->$method( $step->url() );
    }
    my $after = time();

    debug "Cookies: ", $ua->cookie_jar->as_string();

    my $duration = sprintf("%.3f", $after - $before);
    $totDuration += $duration;
    my $warn = $warns->get( $step_name );
    my $crit = $crits->get( $step_name );


    # -----------------------------------------
    # Process result in case of failure of step
    # -----------------------------------------

    if (! $response->is_success) {

        my $level = $step->on_failure();

        if ($level == OK) {
            $np->add_ok( "Step $step_name failed (". $response->status_line(). ") but was ignored as configured" );
            next STEP;  # Lowered to non-fatal, go to next step
        }

        # Set the level
        $np->raise_status( $level );

        # Add the error to the final output
        $np->add_status( $level, "Step $step_name failed (". $response->status_line(). ")" );

        # See if error is fatal or not
        if ($level < CRITICAL) {
            next STEP;
        } else {
            last STEP;
        }
    }


    # ----------------------------------------------
    # Process result in case of success of this step
    # ----------------------------------------------

    writepage($step_name, $response->decoded_content() );

    # Add perfdata regardless of the other conditions
    $np->add_perfdata( label => "Step_${step_name}_duration", value => $duration, uom => "s", warning => $warn, critical => $crit );

    # First of all, check if the result matches the NEGATIVE pattern (if provided).
    # Matching the negative pattern is a fatal error, unless the error level was lowered
    # using "on_err_grep_match".
    if ($step->has_neg_pattern()) {

        debug "Step $step_name has NEGATIVE pattern: ". $step->neg_pattern();

        if ( ($response->decoded_content() =~ $step->neg_pattern()) ) {

            debug "Negative pattern did match!";

            my $level = $step->on_err_grep_match();

            if ($level == OK) {
                $np->add_ok( "Pattern <". $step->neg_pattern(). "> matched at step $step_name but ignored as configured" );
            } else {
                $np->raise_status( $level );
                $np->add_status( $level, "Pattern <". $step->neg_pattern(). "> matched at step $step_name" );
            }

            # See if error is fatal or not
            last STEP
                if $level > WARNING;
        }
    }


    # Second, check if the result matches the POSITIVE pattern (if provided).
    # Not matching the patters is a fatal error, unless the error level was lowered
    # using "on_grep_failure".
    if ($step->has_pattern()) {

        debug "Step $step_name has POSITIVE pattern: ". $step->pattern();

        if (! ($response->decoded_content() =~ $step->pattern()) ) {

            debug "Pattern did not match!";

            my $level = $step->on_grep_failure();

            if ($level == OK) {
                $np->add_ok( "Pattern <". $step->pattern(). "> not matched at step $step_name but ignored as configured" );
            } else {
                $np->raise_status( $level );
                $np->add_status( $level, "Pattern <". $step->pattern(). "> not matched at step $step_name" );
            }

            # See if error is fatal or not
            last STEP
                if $level > WARNING;
        }
    }

    # Check step timing
    my $status = $np->check_threshold( check => $duration, warning => $warn, critical => $crit );

    if ($status == OK) {
        $np->add_ok( "Step $step_name took ${duration}s" );
    } elsif ($status == WARNING) {
        $np->add_warning( "Step $step_name took ${duration}s > ${warn}s" );
    } elsif ($status == CRITICAL) {
        $np->add_critical( "Step $step_name took ${duration}s > ${crit}s" );
    }

}



# Prepare for exit
my $msg = 'Check complete. ';

# Check total duration time against thresholds
my $tc = $opts->totcritical() || '';
my $tw = $opts->totwarning()  || '';
$np->add_perfdata( label => "Total_duration", value => $totDuration, uom => "s", warning => $tw, critical => $tc );

my $status = $np->check_threshold( check => $totDuration, warning => $tw, critical => $tc );

if ( $status == CRITICAL ) {
    $msg .= "CRITICAL: Total duration was ${totDuration}s > ${tc}s; ";
    $np->raise_status( CRITICAL );
} elsif ( $status == WARNING ) {
    $msg .= "WARNING Total duration was ${totDuration}s > ${tw}s; ";
    $np->raise_status( WARNING );
}

# Build final message
my @crits = $np->criticals();
$msg .= "CRITICAL steps: ". join("; ", @crits). "; "
    if @crits;

my @warns = $np->warnings();
$msg .= "WARNING steps: ". join("; ", @warns). "; "
    if @warns;

my @oks = $np->oks();
$msg .= "Steps OK: ". join("; ", @oks). "; "
    if @oks;

# Finally, exit
$np->plugin_exit( $np->status(), $msg );













###############################################################################
## Monitoring::Plugin extension
###############################################################################
package Monitoring::Plugin::End2end;

use strict;
use warnings;
use Monitoring::Plugin;
use parent qw(
    Monitoring::Plugin
);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{_end2end_status} = 0;
    $self->{_end2end_oks} = [];
    $self->{_end2end_warnings} = [];
    $self->{_end2end_criticals} = [];

    return $self;
}


sub add_warning {
    my $self = shift;

    push @{ $self->{_end2end_warnings} }, @_;

    $self->{_end2end_status} = WARNING
        unless $self->{_end2end_status} && $self->{_end2end_status} > WARNING;
}

sub add_critical {
    my $self = shift;

    push @{ $self->{_end2end_criticals} }, @_;

    $self->{_end2end_status} = CRITICAL
        unless $self->{_end2end_status} && $self->{_end2end_status} > CRITICAL;
}

sub add_ok {
    my $self = shift;

    push @{ $self->{_end2end_oks} }, @_;
}

sub add_status {
    my ($self, $status, $reason) = @_;

    if ($status == OK) {
        $self->add_ok( $reason );
    } elsif ($status == WARNING) {
        $self->add_warning( $reason );
    } elsif ($status == CRITICAL) {
        $self->add_critical( $reason );
    }
}

sub status {
    return $_[0]->{_end2end_status};
}

sub raise_status {
    my ($self, $newStatus) = @_;
    $self->{_end2end_status} = $newStatus
        if $self->{_end2end_status} < $newStatus;
}

sub oks {
    return wantarray                    ?
        @{ $_[0]->{_end2end_oks} } :
           $_[0]->{_end2end_oks}   ;
}

sub warnings {
    return wantarray                    ?
        @{ $_[0]->{_end2end_warnings} } :
           $_[0]->{_end2end_warnings}   ;
}

sub criticals {
    return wantarray                    ?
        @{ $_[0]->{_end2end_criticals} } :
           $_[0]->{_end2end_criticals}   ;
}





###############################################################################
## DATA HANDLER
###############################################################################

package Data;

use strict;
use warnings;
use URI::URL;

sub new {
    my $class = shift;
    my $url = URI::URL->new("?".$_[0]);

    return bless( { $url->query_form() }, $class );
}



###############################################################################
## STEP HANDLER
###############################################################################

package Step;

use strict;
use warnings;
use Monitoring::Plugin;

sub new {
    my $class = shift;

    unless( ref( $_[0] ) && ref( $_[0] ) eq 'HASH' ) {
        our $reason = "invalid initialization parameters for Step";
        return;
    }

    # Start from the base configuration (if present)
    my $step = {};

    # In case of errors, do not initialize this object
    # (will cause the plugin to die with an error)
    unless ( $step->{url} = delete $_[0]->{url} ) {
        our $reason = "missing 'url' directive";
        return;
    }

    # Parse binary data if present
    if (defined( my $data = delete $_[0]->{binary_data})) {
        unless ( $step->{data} = Data->new( $data ) ) {
            our $reason = "parsing 'binary_data' failed";
            return;
        }
    }

    # Parse on_failure directive if present, otherwise force it
    # to CRITICAL
    if (exists( $_[0]->{on_failure} )) {
        unless (defined( $step->{on_failure} = _parse( 'on_failure', delete $_[0]->{on_failure} ))) {
            our $reason = "parsing 'on_failure' failed";
            return;
        }
    } else {
        $step->{on_failure} = CRITICAL;
    }

    # Parse grep_err_str/grep_err_re patterns if present
    if (my $grep_err_re = delete $_[0]->{grep_err_re}) {
        $step->{neg_pattern} = qr/$grep_err_re/;
        $step->{on_err_grep_match} = CRITICAL;
        $step->{has_neg_pattern} = 1;
        delete $_[0]->{grep_err_str};   # grep_err_re supersedes grep_err_str
    } elsif (my $grep_err_str = delete $_[0]->{grep_err_str}) {
        $step->{neg_pattern} = quotemeta($grep_err_str);
        $step->{on_err_grep_match} = CRITICAL;
        $step->{has_neg_pattern} = 1;
    }

    # Parse on_err_grep_match if present
    if (exists( $_[0]->{on_err_grep_match} )) {
        main::debug "Parsing: ", $_[0]->{on_err_grep_match};
        unless (defined( $step->{on_err_grep_match} = _parse( 'on_err_grep_match', delete $_[0]->{on_err_grep_match} ))) {
            our $reason = "parsing 'on_err_grep_match' failed";
            return;
        }
        main::debug "Parsed as: ", $step->{on_err_grep_match};
    }

    # Parse grep_str/grep_re patterns if present
    if (my $grep_re = delete $_[0]->{grep_re}) {
        $step->{pattern} = qr/$grep_re/;
        $step->{on_grep_failure} = CRITICAL;
        $step->{has_pattern} = 1;
        delete $_[0]->{grep_str};   # grep_re supersedes grep_str
    } elsif (my $grep_str = delete $_[0]->{grep_str}) {
        $step->{pattern} = quotemeta($grep_str);
        $step->{on_grep_failure} = CRITICAL;
        $step->{has_pattern} = 1;
    }

    # Parse on_grep_failure if present
    if (exists( $_[0]->{on_grep_failure} )) {
        main::debug "Parsing: ", $_[0]->{on_grep_failure};
        unless( defined( $step->{on_grep_failure} = _parse( 'on_grep_failure', delete $_[0]->{on_grep_failure} ) ) ) {
            our $reason = "parsing 'on_grep_failure' failed";
            return;
        }
        main::debug "Parsed as: ", $step->{on_grep_failure};
    }

    # Parse basic authentication if present
    if (exists( $_[0]->{auth_basic_user} )) {
        $step->{auth_basic_credentials} = [
            delete $_[0]->{auth_basic_user},
            delete $_[0]->{auth_basic_password} || ''
        ];
    }

    # Parse method if present, otherwise force it to "get"
    $step->{method} = $_[0]->{method} ? lc( delete $_[0]->{method} ) : 'get';

    return bless( $step, $class );
}

sub _parse {
    # main::debug "_parse ", $_[0], " / ", $_[1];
    my $parsed;
    eval {
        # Call OK(), WARNING(), CRITICAL() or UNKNOWN()
        my $m = uc( $_[1] );
        {
            no strict "refs";
            $parsed = $m->();
        }
        # main::debug "Value: $parsed";
    };

    if ($@) {
        $Step::reason = "parsing '". $_[0]. "' failed (Caused by: $@)";
        return;
    }

    return $parsed;
}

sub url {
    return $_[0]->{url};
}

sub data {
    return unless $_[0]->has_data();
    # Copy data, do not return internal reference
    my %data = %{ $_[0]->{data} };
    return \%data;
}

sub has_data {
    return exists( $_[0]->{data} ) && defined( $_[0]->{ data } );
}

sub pattern {
    return $_[0]->{pattern};
}

sub neg_pattern {
    return $_[0]->{neg_pattern};
}

sub has_pattern {
    return $_[0]->{has_pattern};
}

sub has_neg_pattern {
    return $_[0]->{has_neg_pattern};
}

sub method {
    return $_[0]->{method};
}

sub on_failure {
    return $_[0]->{on_failure};
}

sub on_grep_failure {
    return $_[0]->{on_grep_failure};
}

sub on_err_grep_match {
    return $_[0]->{on_err_grep_match};
}

sub auth_basic_credentials {
    return unless $_[0]->has_basic_auth();
    return @{ $_[0]->{auth_basic_credentials} };
}

sub has_basic_auth {
    return (
        exists( $_[0]->{auth_basic_credentials} ) and
        ref( $_[0]->{auth_basic_credentials} ) eq 'ARRAY'
    );
}


###############################################################################
## STEPS HANDLER
###############################################################################

package Steps;

use strict;
use warnings;

sub new {
    my $class = shift;
    return bless({ @_ }, $class);
}


sub step {
    return Step->new( $_[0]->{ $_[1] } );
}

sub list {
    return wantarray                 ?
        sort( keys( %{ $_[0] } ) )    :
        [ sort( keys( %{ $_[0] } ) ) ];
}






###############################################################################
## THRESHOLDS HANDLER
###############################################################################

package Thresholds;

sub new {
    my $class = shift;
    my $val   = shift || '';
    my @names = @_;

    my %thr;
    if ($val =~ /,/) {
        my @thr = split(/\s*,\s*/, $val);
        %thr = map { $names[ $_ ] => (defined( $thr[ $_ ] ) ? $thr[ $_ ] : '') } 0..$#names;
    } else {
        %thr = map { $names[ $_ ] => $val } 0..$#names;
    }

    return bless( \%thr, $class );
}




sub get {
    return $_[0]->{ $_[1] };
}










################################################################################
# User Agent
################################################################################

package Monitoring::Plugin::End2end::UserAgent;

use HTTP::Headers;
use LWP::UserAgent;
use parent ("LWP::UserAgent");

sub new {
    my $class = shift;
    my $conf  = shift;

    my $hh = HTTP::Headers->new();
    my $self = $class->SUPER::new(
        agent           => $conf->exists("LWP::UserAgent::agent") ? $conf->value("LWP::UserAgent::agent") : $main::plugin_name,
        cookie_jar      => { },
        default_headers => $hh,
        # TODO: be more configurable
    );

    $self->{_http_headers} = $hh;

    $self->_export_proxy($conf)
        or return;
    main::debug "Proxy conf done.";
    $self->_get_basic_auth($conf)
        or return;
    main::debug "Basic auth conf done.";

    return $self;
}

sub _export_proxy {
    my ($self, $conf) = @_;
    return 1
        unless $conf->exists("LWP::UserAgent::proxy");

    # Ensure there are no conflicting proxies in the environment
    for my $var (keys %ENV) {
        $var =~ /_proxy$/i && delete $ENV{ $var };
    }

    # Export proxy configuration into environment
    my $proxy = $conf->value("LWP::UserAgent::proxy");
    my $user  = $conf->exists("LWP::UserAgent::proxy::user")      ? $conf->value("LWP::UserAgent::proxy::user")     : '';
    my $pass  = $conf->exists("LWP::UserAgent::proxy::password")  ? $conf->value("LWP::UserAgent::proxy::password") : '';
    my @schemes = $conf->exists("LWP::UserAgent::proxy::schemes") ?
        split(/\s*,\s*/, $conf->value("LWP::UserAgent::proxy::schemes")) :
        qw(http);
    for my $s (@schemes) {
        $s = uc($s);
        $ENV{$s."_PROXY"} = $proxy;
        $ENV{$s."_PROXY_USERNAME"} = $user if $user;
        $ENV{$s."_PROXY_PASSWORD"} = $pass if $pass;
        main::debug "Using proxy: ". $proxy. " for scheme: ". $s;
    }

    $self->env_proxy();
    return 1;
}

sub _get_basic_auth {
    my ($self, $conf) = @_;
    return 1
        unless $conf->exists("HTTP::Headers::authorization_basic::user");

    unless ($conf->exists("HTTP::Headers::authorization_basic::password")) {
        our $reason = "No password specified for basic http authentication";
        return 0;
    }

    $self->{_http_headers}->authorization_basic(
        $conf->value("HTTP::Headers::authorization_basic::user"),
        $conf->value("HTTP::Headers::authorization_basic::password")
    );

    return 1;
}





###############################################################################
## MANUAL
###############################################################################

=pod

=head1 NAME

check_end2end.pl - Simple configurable end-to-end probe plugin for Nagios


=head1 VERSION

This is the documentation for check_end2end.pl v1.6.1


=head1 SYNOPSYS

See check_end2end.pl -h


=head1 THE CHECK

Every step configured in the configuration file (see L<CONFIGURATION FILE
FORMAT>) is performed regardless of the fact that you specify a threshold for
that step, a global threshold, or a single thresold that will be applied to
every step, because B<every step is checked for success or failure>.
A step check is considered successful if LWP::USerAgent's C<is_success()> method
returns true; otherwise, the check is considered as failed.

A failure in one of the steps will cause the immediate exit of the plugin, with
a critical status, unless configured otherwise (again, see L<CONFIGURATION FILE
FORMAT>), while, if one or more steps are above their time thresholds,
the check will continue and perform the remaining steps (unless the global
timeout is reached). See L<THRESHOLD FORMATS> for details about timing
thresholds.

Overall status of the check will be reported at the end.


=head1 THRESHOLD FORMATS

=head2 -C <CRIT>, -W <WARN>

Total-duration thresholds are just single values in the format specified by
L<https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT>.
For example:

    -W 0.200:1.0

will give a warning if the total duration of the process is below 0.2s or
above 1.0s.


=head2 -c <crit>, -w <warn>

These are per-step duration thresholds. B<If only one value is specified,
that value will be applied to ALL steps in the process>, one by one.
The values still follow the format at
L<https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT>.

For example:

    -c 3

will give you a critical if B<any one> of the steps in you process will last
more than 3s (or less than 0 but that would mean your clock reset in the middle
of the process).

But single-steps thresholds can be specified as a B<comma-separated list of
values>; each individual value follows the already-named guidelines, and
omitted values will be taken as no-threshold for the corresponding step.
The thresholds are appled in order.

So, for example, if you have a 5-step check and only want to apply check to
some steps, you will have to specify:

    -w ,0.2,,,0.5 -c ,0.6,1.1

This will apply a warning threshold of 0.2s and a critical threshold of 0.6s
to the second step, a warning threshold of 0.5s to the fifth step, and a
critical threshold of 1.1s to the third step.

=head3 B<Omitting trailing commas>

You can omit trailing commas if you specify at least two values and don't need
others. For example, to specify thresholds only for the first two steps of a
7-steps process:

    -w 1,3 -c 3,6

will perform all the configured checks, but only the first and the second will
be checked against their thresholds. If you want to apply thresholds only to
the first step, you have to provide at least one trailing comma:

    -w 0.7,

speficies a warning threshold of 0.7s only for the first step.


=head1 CONFIGURATION FILE FORMAT

Here's a sample configuration file for this plugin. If you want to quote
strings, B<use double quotes>.

    #
    # login.cfg -- Configuration file for login check on www.example.com
    #


    ########## check_end2end -specific configuration directives
    #
    # Optional - override default "END2END" plugin name in outputs
    Monitoring::Plugin::shortname = "Check www.example.com Login"

    ########## LWP::UserAgent -specific configuration directives
    #
    # Optional - Override useragent string - defaults to check_end2end
    LWP::UserAgent::agent = "Nagios login check via check_end2end"

    # Optional - Specify proxy settings in the configuration file
    LWP::UserAgent::proxy           = http://proxy.example.com:3128/
        # Optional-optional: defaults to proxy only http
    LWP::UserAgent::proxy::schemes  = http, https       # Comma-separated list
        # Optional-optional: specify credentials if your proxy requires user
        # authentication
    LWP::UserAgent::proxy::user     = proxyuser         # If required
    LWP::UserAgent::proxy::password = proxypassword     # If required

    ########## Optional HTTP parameters
    #
    # Basic HTTP Authentication credentials
    HTTP::Headers::authorization_basic::user     = me
    HTTP::Headers::authorization_basic::password = I_said_it_s_me



    ########## Custom configuration directives
    #
    # Optional - You can specify variables to be interpolated in the
    # following configuration - see "VARIABLES INTERPOLATION" in manual
    BASE_URL = "https://www.example.com"



    ########## check_end2end REQUIRED CONFIGURATION
    #
    # This plugin requires you to specify a list of subsequent steps to be performed.
    # Steps will be performed IN ALPHABETICAL ORDER, so make sure you give them
    # names according to a proper sequence.
    #
    <Step "00 - Public login page">
        url = "$BASE_URL/login.html"
        method = GET
        on_failure = WARNING
        grep_str        = $BASE_URL/login.html
    </Step>

    # Lines can be split as in shell scripts, escaping the final newline with a \
    <Step "01 - Login verification">
        url = "$BASE_URL/login.html"
        binary_data = username=exampleuser&\
            password=examplepassword
        method = POST
        grep_re         = Secret\s+token\d+
        on_grep_failure = WARNING
    </Step>

    <Step "03 - Private login page">
        url = "$BASE_URL/pri/home.html"
        method = GET
        grep_err_str = Wrong username or password
    </Step>



The configuration file is made up of one or many named <Step> blocks, each step
is performed and checked for success. Steps are B<ordered alphabetically>, so
make sure to give them names that reflect the real order to be respected.


=head2 B<Required Step parameters>

=over 4

=item * B<url>

C<url> is the only required parameter for a Step. The url you want to test.

=back


=head2 B<Optional Step parameters>

=over 4

=item * B<method>

C<method> specifies which http method to use to perform the step. B<GET> is the
default. This is passed to LWP::UserAgent after lowercasing it.


=item * B<binary_data>

C<binary_data> is the B<url-encoded> data to be passed to LWP::UserAgent. Prior
to be passed to LWP::UserAgent, binary_data is parsed by the URI::URL module.


=item * B<on_failure>

C<on_failure> specifies if a failure of the Step must be treated as an OK
status, a WARNING, a CRITICAL or ar UNKNOWN.
The default is to treat a failure as a CIRITCAL event and to return an error
immediately.
Specify OK if you just want to time some steps but don't want failures to
be considered as errors; a level of WARNING will raise the level of the check
to WARNING (at least, unless some more serious error happens afterwards); a
level of CRITICAL (default) or UNKNOWN will cause the check to stop as soon
as the error happens and to exit reporting that severity level.


=item * B<grep_err_re|grep_err_str>

B<NOTE>: C<grep_err_re> supersedes C<grep_err_str>, in case both are specified.

C<grep_err_str> specifies an error string to be searched inside the response
body. The default status in case the string is found is CRITICAL. This can be
changed specifying C<on_err_grep_match> parameter. With C<grep_err_str> the
string is enclosed between escaping regexp sequence: \Q...\E so it's treated as
a literal string.

C<grep_err_re> is the same as C<grep_err_str>, but the given pattern is assumed
to be a regexp, and is quoted using the regexp quoting operator C<qr{}>.

If an erorr string was found in a step, and the level of this event is higher
than WARNING, the event is treated as a fatal failure and the check stops.


=item * B<on_err_grep_match>

C<on_err_grep_match> specifies the status level in case the
C<grep_err_re|grep_err_str> was found inside response (decoded) body.
It's only meaningful if either C<grep_err_re> or C<grep_err_str> was specified.
The default is to treat the event as a CRITICAL. Criticalty levels of UNKNOWN
and CRITICAL cause the check to stop in case of pattern matched;
criticalty levels of WARNING and OK cause the problem to be reported but the
check will go on performing following steps (if any).


=item * B<grep_re|grep_str>

B<NOTE>: C<grep_re> supersedes C<grep_str>, in case both are specified.

C<grep_str> specifies a string to be searched inside the response body. The
default status in case the string is not found is CRITICAL. This can be changed
by specifying C<on_grep_failure> parameter. With C<grep_str> the string is
enclosed between escaping regexp sequence: \Q...\E so it's treated as a literal
string.

C<grep_re> is the same as C<grep_str>, but the given pattern is assumed to be
a regexp, and is quoted using the regexp quoting operator C<qr{}>.

If a string was not found in a step, and the level of this event is higher than
WARNING, the event is treated as a fatal failure and the check stops.


=item * B<on_grep_failure>

C<on_grep_failure> specifies the status level in case the C<grep_str|grep_re>
was not found inside response (decoded) body. It's only meaningful if
either C<grep_str> or C<grep_re> was specified. The default is to treat the
event as a CRITICAL. Criticalty levels of UNKNOWN and CRITICAL cause the check
to stop in case of pattern not matched; criticalty levels of WARNING and OK
cause the problem to be reported but the check will go on performing following
steps (if any).


=back


=head1 VARIABLES INTERPOLATION

By default, any variable can be used inside the configuration file, after being
initialized. The variable's value will be interpolated in the fields following
variable initialization. Variables can be delimited using shell's notation:

    ${VARIABLE}

or just

    $VARIABLE

if there are no ambiguities.
See the manual of Config::General::Interpolated for full details.


=head2 Environment variables

Environment variables can be used for interpolation if -e|--useEnvVars flag is
specified on the command line. B<Be careful!> - usage of environment variables
can expose your check to environment variables forgery and so must be regarded
as a possible security risk.

=head2 Variables passed by the command line

You can use the flag --var multiple times to specify variables on the command
line. This is useful for Nagios macross expansion, for example:

    check_end2end.pl -f config.cfg --var PROTO=https --var HOST=$HOSTADDRESS$ \
        --var CHECK="$SERVICENAME$"

and, in the configuration file:

    Monitoring::Plugin::shortname = $CHECK

    <Step "some step">
        url = ${PROTO}://$HOST/some/url.html
        ...
    </Step>

B<Be careful!> - --var enables environment variables interpolation
automatically. Any previously defined environment variable will be overridden,
though, if a variable with the same name is specified on the command line.


=head2 Empty variables

By default, Config::General will croak() if undefined variables are used inside
the configuration file. Use -E|--allowEmptyVars to override this behaviour.




=head1 PREREQUISITES

Reuired modules:

=over 4

=item * Config::General

=item * LWP::UserAgent

=item * Monitoring::Plugin

=item * URI::URL

=back

for debugging:

=over 4

=item * Data::Dumper

=item * File::Spec

=item * Path::Tiny

=back




=head1 AUTHOR

Giacomo Montagner, <kromg at entirelyunlike.net>,
<kromg.kromg at gmail.com> >

=head1 BUGS AND CONTRIBUTIONS

Please report any bug at L<https://github.com/kromg/nagios-plugins/issues>. If
you have any patch/contribution, feel free to fork git repository and submit a
pull request with your modifications.


=head2 Contributors:

* Aurel Schwarzentruber







=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016-2017 Giacomo Montagner <giacomo@entirelyunlike.net>

This program is free software: you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See http://dev.perl.org/licenses/ for more information.


=head1 AVAILABILITY

Latest sources are available from L<https://github.com/kromg/nagios-plugins>

=cut
