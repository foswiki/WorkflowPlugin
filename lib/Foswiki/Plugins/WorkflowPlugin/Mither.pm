# See bottom of file for copyright and license information

# This module contains the functionality of the bin/actionnotify script
package Foswiki::Plugins::WorkflowPlugin::Mither;

use strict;
use integer;

use locale;    # required for international names
use Assert;
use Data::Dumper;

use Time::ParseDate                            ();
use Foswiki::Net                               ();
use Foswiki::Attrs                             ();
use Foswiki::Plugins::WorkflowPlugin           ();
use Foswiki::Plugins::WorkflowPlugin::Workflow ();

my $options;
my %workflows;

# PUBLIC actionnotify script entry point. Reinitialises Foswiki.
#
# Notify all persons of actions that match the search expression
# passed.
#
sub mither {
    my %options = @_;

    my $session = new Foswiki();

    # Assign SESSION so that Func methods work
    $Foswiki::Plugins::SESSION = $session;

    my @allwebs = Foswiki::Func::getListOfWebs();
    my @topics;
    foreach my $topicre ( split( /,+/, $options{topics} ) ) {
        $topicre =~ s/([.\/])/\\$1/g;
        $topicre =~ s/\*/.*/g;
        $topicre =~ s/\?/./g;
        $topicre = qr/^$topicre$/;
        foreach my $web (@allwebs) {
            foreach my $topic ( Foswiki::Func::getTopicList($web) ) {
                if ( "$web.$topic" =~ /$topicre/ ) {
                    push( @topics, { web => $web, topic => $topic } );
                }
            }
        }
    }

    foreach my $topic (@topics) {

        # Load the topic
        my ( $meta, $text ) =
          Foswiki::Func::readTopic( $topic->{web}, $topic->{topic} );
        Foswiki::Func::pushTopicContext( $topic->{web}, $topic->{topic} );
        my $workflowName = Foswiki::Func::getPreferencesValue('WORKFLOW');
        if ( $workflowName && $workflowName eq $options{workflow} ) {
            my $current   = $meta->get('WORKFLOW');
            my $state     = $current->{name};
            my $timelimit = $options{states}->{$state};
            if ( $timelimit > 0 ) {
                my @history = _loadHistory($meta);
                my $tt      = $history[0]->{date};
                my $stuck   = ( time() - $tt ) / ( 24 * 60 * 60 );
                if ( $stuck > $timelimit ) {

                    # Find previous state
                    my $pstate = $history[1]->{state};
                    renotifyStateChange(
                        topic        => $topic,
                        meta         => $meta,
                        text         => $text,
                        pstate       => $pstate,
                        state        => $state,
                        stuck        => $stuck,
                        workflowName => $workflowName
                    );
                }
            }
        }
        Foswiki::Func::popTopicContext();
    }
}

# Sort the META:WORKFLOWHISTORY by decreasing date
sub _loadHistory {
    my $meta = shift;
    return sort { $b->{date} <=> $a->{date} } $meta->find('WORKFLOWHISTORY');
}

sub renotifyStateChange {
    my %p = @_;

    # Load the workflow
    my $workflow = $workflows{"$p{topic}->{web}.$p{workflowName}"};
    if ( !$workflow ) {
        $workflow =
          new Foswiki::Plugins::WorkflowPlugin::Workflow( $p{topic}->{web},
            $p{workflowName} );
        $workflows{"$p{topic}->{web}.$p{workflowName}"} = $workflow;
    }
    if ( !$workflow ) {
        print STDERR
          "Unable to load workflow $p{topic}->{web}.$p{workflowName}\n";
        return;
    }

    # Find the transition that corresponds to our state change
    my $transition;
    foreach ( @{ $workflow->{transitions} } ) {

        # HUGE ASSUMPTION - expansion is in the context of the
        # post-transition topic.
        my $from = Foswiki::Func::expandCommonVariables(
            $_->{state},
            $p{topic}->{topic},
            $p{topic}->{web},
            $p{meta}
        );
        my $to = Foswiki::Func::expandCommonVariables(
            $_->{nextstate},
            $p{topic}->{topic},
            $p{topic}->{web},
            $p{meta}
        );
        if ( $from eq $p{pstate} && $to eq $p{state} ) {
            print STDERR "Transition was '$_->{action}'\n";
            $p{transition} = $_;
            renotifyTransition(%p);
            return;
        }
    }
    print STDERR
      "Unable to determine transition for move from $p{pstate} to $p{state}\n";
}

sub renotifyTransition {
    my %p = @_;

    print
"$p{topic}->{web}.$p{topic}->{topic} has been in state $p{workflowName}.$p{state} for $p{stuck} days. Previous state was $p{workflowName}.$p{pstate}.\n";

    # Dig up the bodies
    my $notify = Foswiki::Func::expandCommonVariables(
        $p{transition}->{notify},
        $p{topic}->{topic},
        $p{topic}->{web},
        $p{meta}
    );

    print "Renotifying $notify\n";

    my @persons = split( /\s*,\s*/, $notify );
    my @emails;
    my @templates;
    my $templatetext        = undef;
    my $currenttemplatetext = undef;

    foreach my $who (@persons) {
        if ( $who =~ /^$Foswiki::regex{emailAddrRegex}$/ ) {
            push( @emails, $who );
        }
        elsif ( $who =~ /^template\((.*)\)$/ ) {

            # Read template topic if provided one
            my @webtopic =
              Foswiki::Func::normalizeWebTopicName( $p{topic}->{web}, $1 );
            if ( Foswiki::Func::topicExists( $webtopic[0], $webtopic[1] ) ) {
                ( undef, $currenttemplatetext ) =
                  Foswiki::Func::readTopic( $webtopic[0], $webtopic[1] );
                push( @templates, $currenttemplatetext );
            }
            else {
                print STDERR __PACKAGE__
                  . " cannot find topic '"
                  . $webtopic[0] . "."
                  . $webtopic[1] . "'"
                  . " - this template will not be expanded!\n";
            }
        }
    }

    if ( scalar(@emails) ) {

        # Have a list of recipients
        my $defaulttemplate = undef;
        my $text            = undef;
        my $currentweb      = undef;
        my $currenttopic    = undef;

        my $text = Foswiki::Func::loadTemplate('mailworkflowmither');

        my $tofield = join( ', ', @emails );

        Foswiki::Func::setPreferencesValue( 'EMAILTO',      $tofield );
        Foswiki::Func::setPreferencesValue( 'TARGET_STATE', $p{state} );
        Foswiki::Func::setPreferencesValue( 'STUCK',        $p{stuck} );

        # if this workflow has a custom email template defined via
        # the notify-column use only this template
        if ( scalar(@templates) ) {
            foreach my $template (@templates) {
                $template = Foswiki::Func::expandCommonVariables($template);
                my $errors = Foswiki::Func::sendEmail( $template, 5 );
                if ($errors) {
                    print STDERR
                      "Failed to send transition reminders: $errors\n";
                }
            }
        }
        else {
            $text = Foswiki::Func::expandCommonVariables($text);
            my $errors = Foswiki::Func::sendEmail( $text, 5 );
            if ($errors) {
                print STDERR "Failed to send transition reminders: $errors";
            }
        }
    }
    else {
        print STDERR
"*** No email addresses could be determined for $notify. No mails sent.\n";
    }
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2016 Crawford Currie http://c-dot.co.uk

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details, published at
http://www.gnu.org/copyleft/gpl.html

NOTE: THIS SCRIPT MUST BE RUN FROM THE bin DIRECTORY
This is so it can find setlib.cfg.

As per the GPL, removal of this notice is prohibited.


