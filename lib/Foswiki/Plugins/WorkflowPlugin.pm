#
# Copyright (C) 2005 Thomas Hartkens <thomas@hartkens.de>
# Copyright (C) 2005 Thomas Weigert <thomas.weigert@motorola.com>
# Copyright (C) 2008 Crawford Currie http://c-dot.co.uk
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

# TODO
# 1. Create initial values based on form when attaching a form for
#    the first time.
# 2. Allow appearance of button to be given in preference.

# =========================
package Foswiki::Plugins::WorkflowPlugin;

use strict;

use Error ':try';

use Foswiki::Func ();
use Foswiki::Plugins::WorkflowPlugin::Workflow ();
use Foswiki::Plugins::WorkflowPlugin::ControlledTopic ();
use Foswiki::OopsException ();

our $VERSION          = '$Rev$';
our $RELEASE          = '2 Sep 2009';
our $SHORTDESCRIPTION = 'Supports work flows associated with topics';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName       = 'WorkflowPlugin';
our %cache;

sub initPlugin {
    my ( $topic, $web ) = @_;

    %cache = ();

    Foswiki::Func::registerRESTHandler( 'changeState', \&_changeState );

    Foswiki::Func::registerTagHandler( 'WORKFLOWSTATE', \&_WORKFLOWSTATE );
    Foswiki::Func::registerTagHandler( 'WORKFLOWEDITTOPIC',
        \&_WORKFLOWEDITTOPIC );
    Foswiki::Func::registerTagHandler( 'WORKFLOWATTACHTOPIC',
        \&_WORKFLOWATTACHTOPIC );
    Foswiki::Func::registerTagHandler( 'WORKFLOWSTATEMESSAGE',
        \&_WORKFLOWSTATEMESSAGE );
    Foswiki::Func::registerTagHandler( 'WORKFLOWHISTORY', \&_WORKFLOWHISTORY );
    Foswiki::Func::registerTagHandler( 'WORKFLOWTRANSITION',
        \&_WORKFLOWTRANSITION );

    return 1;
}

# Tag handler
sub _initTOPIC {
    my ( $web, $topic ) = @_;

    ( $web, $topic ) =
      Foswiki::Func::normalizeWebTopicName( $web, $topic );

    my $controlledTopic = $cache{"$web.$topic"};
    return $controlledTopic if $controlledTopic;

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );

    Foswiki::Func::pushTopicContext( $web, $topic );
    my $workflowName = Foswiki::Func::getPreferencesValue('WORKFLOW');
    Foswiki::Func::popTopicContext( $web, $topic );

    if ($workflowName) {

        ( my $wfWeb, $workflowName ) =
          Foswiki::Func::normalizeWebTopicName( $web, $workflowName );
        my $workflow = new Foswiki::Plugins::WorkflowPlugin::Workflow( $wfWeb,
            $workflowName );

        if ($workflow) {
            $controlledTopic =
              new Foswiki::Plugins::WorkflowPlugin::ControlledTopic( $workflow,
                $web, $topic, $meta, $text );
        }
    }

    $cache{"$web.$topic"} = $controlledTopic;

    return $controlledTopic;
}

# Tag handler
sub _WORKFLOWEDITTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    # replace edit tag
    if ( $controlledTopic->canEdit() ) {
        return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'edit', t=> time),
            }, CGI::strong("Edit") );
    }
    else {
        return CGI::strike("Edit");
    }
}

# Tag handler
sub _WORKFLOWSTATEMESSAGE {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $theWeb = $attributes->{web} || $web;
    my $theTopic = $attributes->{_DEFAULT} || $topic;

    ( $theWeb, $theTopic ) =
      Foswiki::Func::normalizeWebTopicName( $theWeb, $theTopic );

    my $controlledTopic = _initTOPIC( $theWeb, $theTopic );

    return '' unless $controlledTopic;
    return $controlledTopic->getStateMessage();
}

# Tag handler
sub _WORKFLOWATTACHTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    # replace attach tag
    if ( $controlledTopic->canAttach() ) {
        return CGI::a(
            {
                href => Foswiki::Func::getScriptUrl(
                    $web, $topic, 'attach', t => time()
                )
            },
            CGI::strong("Attach")
        );
    }
    else {
        return CGI::strike("Attach");
    }
}

# Tag handler
sub _WORKFLOWHISTORY {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $theWeb = $attributes->{web} || $web;
    my $theTopic = $attributes->{_DEFAULT} || $topic;

    ( $theWeb, $theTopic ) =
      Foswiki::Func::normalizeWebTopicName( $theWeb, $theTopic );

    my $controlledTopic = _initTOPIC( $theWeb, $theTopic );
    return '' unless $controlledTopic;

    return $controlledTopic->getHistoryText();
}

# Tag handler
sub _WORKFLOWTRANSITION {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    #
    # Build the button to change the current status
    #
    my @actions         = $controlledTopic->getActions();
    my $numberOfActions = scalar(@actions);
    my $cs              = $controlledTopic->getState();

    unless ($numberOfActions) {
        return CGI::span(
            { class => 'foswikiAlert' },
            "NO AVAILABLE ACTIONS in state $cs"
        ) if $controlledTopic->debugging();
        return '';
    }

    my @fields = (
        CGI::hidden( 'WORKFLOWSTATE', $cs ),
        CGI::hidden( 'topic',         "$web.$topic" ),

        # Use a time field to help defeat the cache
        CGI::hidden( 't', time() )
    );

    my $buttonClass =
      Foswiki::Func::getPreferencesValue('WORKFLOWTRANSITIONCSSCLASS')
      || 'foswikiChangeFormButton foswikiSubmit"';

    if ( $numberOfActions == 1 ) {
        push( @fields, CGI::hidden( 'WORKFLOWACTION', $actions[0] ) );
        push(
            @fields,
            CGI::submit(
                -class => $buttonClass,
                -value => $actions[0]
            )
        );
    }
    else {
        push(
            @fields,
            CGI::popup_menu(
                -name   => 'WORKFLOWACTION',
                -values => \@actions
            )
        );
        push(
            @fields,
            CGI::submit(
                -class => $buttonClass,
                -value => 'Change status'
            )
        );
    }
    my $url = Foswiki::Func::getScriptUrl( $pluginName, 'changeState', 'rest' );
    my $form =
        CGI::start_form( -method => 'POST', -action => $url )
      . join( '', @fields )
      . CGI::end_form();
    $form =~ s/\r?\n//g;    # to avoid breaking TML
    return $form;
}

# Tag handler
sub _WORKFLOWSTATE {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $theWeb = $attributes->{web} || $web;
    my $theTopic = $attributes->{_DEFAULT} || $topic;

    ( $theWeb, $theTopic ) =
      Foswiki::Func::normalizeWebTopicName( $theWeb, $theTopic );

    my $controlledTopic = _initTOPIC( $theWeb, $theTopic );
    return '' unless $controlledTopic;

    return $controlledTopic->getState();
}

# Used to trap an edit and check that it is permitted by the workflow
sub beforeEditHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;

    my $query = Foswiki::Func::getCgiQuery();
    if ( !$query->param('INWORKFLOWSEQUENCE') && !$controlledTopic->canEdit() ) {
        throw Foswiki::OopsException(
            'accessdenied',
            status => 403,
            def    => 'topic_access',
            web    => $_[2],
            topic  => $_[1],
            params => [
                'Edit topic',
'You are not permitted to edit this topic. You have been denied access by Workflow Plugin'
            ]
        );
    }
}

sub beforeAttachmentSaveHandler {
    my ( $attrHashRef, $topic, $web ) = @_;
    my $controlledTopic = _initTOPIC( $web, $topic );
    return '' unless $controlledTopic;
    if ( !$controlledTopic->canEdit() ) {
        throw Foswiki::OopsException(
            'accessdenied',
            status => 403,
            def    => 'topic_access',
            web    => $_[2],
            topic  => $_[1],
            params => [
                'Edit topic',
'You are not permitted to attach to this topic. You have been denied access by Workflow Plugin'
            ]
        );
    }
}

# Handle actions. REST handler, on changeState action.
sub _changeState {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    return unless $query;

    my $web   = $session->{webName};
    my $topic = $session->{topicName};
    die unless $web && $topic;

    my $url;
    my $controlledTopic = _initTOPIC( $web, $topic );

    unless ($controlledTopic) {
        $url = Foswiki::Func::getScriptUrl(
            $web, $topic, 'oops',
            template => "oopssaveerr",
            param1   => "Could not initialise workflow for "
              . ( $web   || '' ) . '.'
                . ( $topic || '' )
               );
        Foswiki::Func::redirectCgiQuery( undef, $url );
        return undef;
    }

    my $action = $query->param('WORKFLOWACTION');
    my $state  = $query->param('WORKFLOWSTATE');
    die "BAD STATE $action $state!=", $controlledTopic->getState()
      unless $action
        && $state
          && $state eq $controlledTopic->getState()
            && $controlledTopic->haveNextState($action);

    my $newForm = $controlledTopic->newForm($action);

    # Check that no-one else has a lease on the topic
    my $breaklock = $query->param('breaklock');
    unless (Foswiki::Func::isTrue($breaklock)) {
        my ( $url, $loginName, $t ) = Foswiki::Func::checkTopicEditLock(
            $web, $topic );
        if ( $t ) {
            my $currUser = Foswiki::Func::getCanonicalUserID();
            my $locker = Foswiki::Func::getCanonicalUserID($loginName);
            if ($locker ne $currUser) {
                $t = Foswiki::Time::formatDelta(
                    $t, $Foswiki::Plugins::SESSION->i18n );
                $url = Foswiki::Func::getScriptUrl(
                    $web, $topic, 'oops',
                    template => 'oopswfplease',
                    param1   => Foswiki::Func::getWikiName($locker),
                    param2   => $t,
                    param3   => $state,
                    param4   => $action,
                   );
                Foswiki::Func::redirectCgiQuery( undef, $url );
                return undef;
            }
        }
    }
    try {
        try {
            $query->param( 'INWORKFLOWSEQUENCE' => 1 );
            if ($newForm) {

                # If there is a form with the new state, and it's not
                # the same form as previously, we need to kick into edit
                # mode to support form field changes.
                $url =
                  Foswiki::Func::getScriptUrl(
                      $web, $topic, 'edit',
                      INWORKFLOWSEQUENCE => time(),
                      breaklock => $breaklock);
            }
            else {
                $url = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );
            }

            # SMELL: don't do this until the edit is over
            $controlledTopic->changeState($action);
            Foswiki::Func::redirectCgiQuery( undef, $url );
        }
          catch Error::Simple with {
              my $error = shift;
              throw Foswiki::OopsException(
                  'oopssaveerr',
                  web    => $web,
                  topic  => $topic,
                  params => [ $error || '?' ]
                 );
          };
    } catch Foswiki::OopsException with {
        my $e = shift;
        if ( $e->can('generate') ) {
            $e->generate($session);
        }
        else {

            # Deprecated, TWiki compatibility only
            $e->redirect($session);
        }

    };
    return undef;
}

# Mop up other WORKFLOW tags without individual handlers
sub commonTagsHandler {
    my ( $text, $topic, $web ) = @_;

    my $controlledTopic = _initTOPIC( $web, $topic );

    if ( $controlledTopic ) {

        # show all tags defined by the preferences
        my $url = Foswiki::Func::getScriptUrl( $web, $topic, "view" );
        $controlledTopic->expandWorkflowPreferences( $url, $_[0] );

        return unless ( $controlledTopic->debugging() );
    }

    # Clean up unexpanded variables
    $_[0] =~ s/%WORKFLOW[A-Z_]*%//g;
}

# Check the the workflow permits a save operation.
#sub beforeSaveHandler {
#    my ( $text, $topic, $web ) = @_;
#
#    my $controlledTopic = _initTOPIC( $web, $topic );
#    return '' unless $controlledTopic;
#
# This handler is called by Foswiki::Store::saveTopic just before
# the save action.
#    my $query = Foswiki::Func::getCgiQuery();
#    if ( !$query->param('INWORKFLOWSEQUENCE')
#         && !$controlledTopic->canEdit() ) {
#        throw Foswiki::OopsException(
#            'accessdenied',
#            def   => 'topic_access',
#            web   => $_[2],
#            topic => $_[1],
#            params =>
#              [ 'Save topic', 'You are not permitted to make this transition' ]
#        );
#        return 0;
#   }
#}

1;
