# See bottom of file for copyright and license information

# This module contains the functionality of the bin/actionnotify script
package Foswiki::Plugins::WorkflowPlugin::Mither;

use strict;

use Error qw(:try);
use locale;    # required for international names

use Foswiki::Plugins::WorkflowPlugin::ControlledTopic ();

my $options;
my %workflows;

=begin TML

---++ StaticMethod mither(%options)

Notify all persons of actions that match the search expression
passed. See tools/workflowremind for more about options.
   * =topic= - array of topic wildcard specs
   * =workflow= - name of workflow
   * =states= - map of states to time limits

=cut

sub mither {
    my (%options) = @_;

    my @tres;
    foreach my $topicre ( @{ $options{topic} } ) {
        $topicre =~ s/\./\\./g;
        $topicre =~ s/\*/.*/g;
        $topicre =~ s/\?/./g;
        push( @tres, qr/^$topicre$/ );
    }
    my @topics;
    foreach my $web ( Foswiki::Func::getListOfWebs() ) {
        foreach my $topic ( Foswiki::Func::getTopicList($web) ) {
            if ( grep { "$web.$topic" =~ $_ } @tres ) {
                push( @topics, { web => $web, topic => $topic } );
            }
        }
    }

    foreach my $topic (@topics) {
        my $controlledTopic;
        try {
            # Load the topic
            $controlledTopic =
              Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
                $topic->{web}, $topic->{topic} );
        }
        catch WorkflowException with {
            Foswiki::Func::writeWarning(
                "Failed to load $topic->{web}.$topic->{topic}: "
                  . shift->debug(1) );
        };

        next unless $controlledTopic;

        next
          unless $controlledTopic->{workflow}->{name} =~
          /\.$options{workflow}$/;

        my $state     = $controlledTopic->getCurrentStateName();
        my $timelimit = $options{states}->{$state};
        next unless $timelimit > 0;

        # Get the most recent history record for the state so
        # we know when we transitioned into this state
        my $history = $controlledTopic->getLast($state);
        next unless $history;

        my $tt = $history->{date};

        # See if we've been stuck for too long
        my $stuck = time() - $tt;
        next unless $stuck > $timelimit;

        # Find previous state that we must have
        # transitioned from
        my $ph = $controlledTopic->getLastBefore($tt);
        my $pstate =
            $ph
          ? $ph->{state}
          : $controlledTopic->{workflow}->{defaultState};

        # Determine the transition
        my @txes = $controlledTopic->{workflow}->getTransitions($pstate);
        foreach my $tx (@txes) {
            if ( $tx->{nextstate} eq $state ) {
                $tx->{notify} = 'experiment@c-dot.co.uk';
                $controlledTopic->notifyTransition(
                    $tx,
                    template         => 'WorkflowRemindMail',
                    default_template => 'mailworkflowmither',

                    # %STUCK% is days
                    STUCK => $stuck / 88640
                );
                last;
            }
        }
    }

}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2016-2017 Crawford Currie http://c-dot.co.uk

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


