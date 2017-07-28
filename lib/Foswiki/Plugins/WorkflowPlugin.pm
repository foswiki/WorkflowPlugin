# See bottom of file for license and copyright information
package Foswiki::Plugins::WorkflowPlugin;

use strict;

use Error ':try';
use Assert;

use Foswiki::Func          ();
use Foswiki::OopsException ();
use Foswiki::Sandbox       ();

use Foswiki::Plugins::WorkflowPlugin::WorkflowException;

our $VERSION = '1.17';
our $RELEASE = '9 Jul 2017';
our $SHORTDESCRIPTION =
'Associate a "state" with a topic and then control the work flow that the topic progresses through as content is added.';
our $NO_PREFS_IN_TOPIC = 1;
our $pluginName        = 'WorkflowPlugin';

our $tmplCache;

sub initPlugin {
    my ( $topic, $web ) = @_;

    undef $tmplCache;

    Foswiki::Func::registerRESTHandler(
        'changeState', \&_restChangeState,
        authenticate => 1,
        validate     => 1,
        http_allow   => 'POST'
    );
    Foswiki::Func::registerRESTHandler(
        'fork', \&_restFork,
        authenticate => 1,
        validate     => 1,
        http_allow   => 'POST'
    );

    Foswiki::Meta::registerMETA('WORKFLOW');
    Foswiki::Meta::registerMETA( 'WORKFLOWHISTORY', many => 1 );

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
    Foswiki::Func::registerTagHandler( 'WORKFLOWFORK', \&_WORKFLOWFORK );

    Foswiki::Func::registerTagHandler( 'WORKFLOWLAST',    \&_WORKFLOWLAST );
    Foswiki::Func::registerTagHandler( 'WORKFLOWLASTREV', \&_WORKFLOWLASTREV );
    Foswiki::Func::registerTagHandler( 'WORKFLOWLASTTIME',
        \&_WORKFLOWLASTTIME );
    Foswiki::Func::registerTagHandler( 'WORKFLOWLASTVERSION',
        \&_WORKFLOWLASTVERSION );
    Foswiki::Func::registerTagHandler( 'WORKFLOWLASTUSER',
        \&_WORKFLOWLASTUSER );

    if ( $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled} ) {
        require Foswiki::Plugins::SolrPlugin;
        Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(
            \&_solrIndexTopicHandler );
    }

    return 1;
}

sub _getString {
    my $tmpl = shift;
    require Foswiki::Templates;
    $tmplCache ||= Foswiki::Func::loadTemplate('workflowstrings');
    return unless $tmpl;
    my $s = Foswiki::Func::expandTemplate( 'workflow:' . $tmpl );
    ASSERT( defined $s, "workflow:$tmpl missing" ) if DEBUG;
    $s =~ s{%PARAM(\d+)%}{$_[$1 - 1] // "?$1"}ge;
    return $s;
}

sub _oops {
    my $error = shift;
    _getString();
    throw Foswiki::OopsException(
        'attention',
        def    => "workflow:$error->{def}",
        params => $error->{params}
    );
}

# Get parameters describing a topic, and check their validity
#   * =$attributes= - may be macro params web= topic= _DEFAULT
#   * =$web, $topic= default web, topic if no attributes
sub _getTopicParams {
    my ( $attributes, $web, $topic ) = @_;

    ( $web, $topic ) =
      Foswiki::Func::normalizeWebTopicName( $attributes->{web} || $web,
        $attributes->{topic} || $attributes->{_DEFAULT} || $topic );

    throw WorkflowException( 'badtopic', "$web.$topic" )
      unless Foswiki::Func::isValidTopicName( $topic, 1 )
      && Foswiki::Func::isValidWebName($web);

    my ($rev) =
      defined $attributes->{rev} ? ( $attributes->{rev} =~ m/(\d+)/ ) : ();

    return ( $web, $topic, $rev );
}

sub _formatHistoryRecord {
    my ( $hist, $fmt, $index ) = @_;

    $hist ||= {};

    my $tmpl = '';
    my $auth = $hist->{author} // 'unknown';
    my $date =
      $hist->{date}
      ? Foswiki::Func::formatTime( $hist->{date}, undef )
      : 'unknown';

    if ( $hist->{forkto} ) {
        $tmpl = _getString('forkedto');
        my $p = join( ', ', map { "[[$_]]" } split /\s*,\s*/, $hist->{forkto} );
        $tmpl = s/%PARAM1%/$p/g;
        $tmpl =~ s/%PARAM2%/$auth/g;
        $tmpl =~ s/%PARAM3%/$date/g;
    }
    elsif ( $hist->{forkfrom} ) {
        $tmpl = _getString('forkedfrom');
        $tmpl =~ s/%PARAM1%/$hist->{forkfrom}/g;
        $tmpl =~ s/%PARAM2%/$auth/g;
        $tmpl =~ s/%PARAM3%/$date/g;
    }
    elsif ( !$hist->{name} || $hist->{name} < 0 ) {

        # Legacy
        $tmpl = $hist->{value} // '';
    }
    else {

        sub _expand {
            my ( $record, $token ) = @_;
            return '?' unless defined $record && defined $record->{$token};
            return $record->{$token};
        }
        $tmpl = $fmt;

        # Map compatibility equivalence names
        $tmpl =~ s/\$(wikiusername|user)/\$author/g;
        $tmpl =~ s/\$user/\$author/g;
        $tmpl =~ s/\$version/\$name/g;
        $tmpl =~ s/\$rev/\$name/g;
        $tmpl =~ s/\$index/$index/g;
        $tmpl =~ s/\$time/\$http/g;
        $tmpl =~ s/\$date/\$http/g;

        # Expand time features
        $tmpl = Foswiki::Func::formatTime( $hist->{date} // 0, $tmpl );

        # Expand history fields
        $tmpl =~ s/\$(\w+)/_expand($hist, $1)/ge;
        $tmpl = Foswiki::Func::decodeFormatTokens($tmpl);
    }

    #print STDERR Data::Dumper->Dump([$hist, $fmt, $tmpl]);

    return $tmpl;
}

# Tag handler - report state
sub _WORKFLOWSTATEMESSAGE {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $result = '';

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;

        ( $web, $topic, my $rev ) =
          _getTopicParams( $attributes, $web, $topic );
        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );
        $result = $controlledTopic->getCurrentState()->{message};
    }
    catch WorkflowException with {
        $result = shift->debug();
    };
    return $result;
}

# Tag handler - controllable edit button
sub _WORKFLOWEDITTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $tag;

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic, my $rev ) =
          _getTopicParams( $attributes, $web, $topic );

        throw WorkflowException( 'badtopic', "$web.$topic" )
          unless ( Foswiki::Func::topicExists( $web, $topic ) );

        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );

        throw WorkflowException( $controlledTopic, 'cantedit',
            Foswiki::Func::getWikiName(),
            "$web.$topic" )
          unless $controlledTopic->canEdit();

        $tag =
          _getString( 'editbutton',
            Foswiki::Func::getScriptUrl( $web, $topic, 'edit', t => time() ) );
    }
    catch WorkflowException with {
        $tag = _getString('strikeedit') . _getString( 'debug', shift->debug() );
    };
    return $tag;
}

# Tag handler - controllable attach button
sub _WORKFLOWATTACHTOPIC {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $tag;
    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic, my $rev ) =
          _getTopicParams( $attributes, $web, $topic );

        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );

        throw WorkflowException( $controlledTopic,
            'cantedit', Foswiki::Func::getWikiName(),
            "$web.$topic" )
          unless $controlledTopic->canEdit();

        $tag = _getString( 'attachbutton',
            Foswiki::Func::getScriptUrl( $web, $topic, 'attach', t => time() )
        );
    }
    catch WorkflowException with {
        $tag =
          _getString('strikeattach') . _getString( 'debug', shift->debug() );
    };
    return $tag;
}

# Tag handler - history report
sub _WORKFLOWHISTORY {
    my ( $session, $params, $topic, $web ) = @_;

    my $result = "";
    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic, my $rev ) = _getTopicParams( $params, $web, $topic );

        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );

        my $header    = $params->{header}    || '';
        my $footer    = $params->{footer}    || '';
        my $separator = $params->{separator} || '';
        my $fmt =
          $params->{format}
          // Foswiki::Func::getPreferencesValue("WORKFLOWHISTORYFORMAT")
          // '<br>$state -- $date';

        $fmt =~ s/\$count/\$index/g;

        my $include = $params->{include};
        my $exclude = $params->{exclude};

        my @results = ();
        my $index   = 1;
        foreach
          my $rev ( sort { $a <=> $b } keys %{ $controlledTopic->{history} } )
        {
            my $hist = $controlledTopic->{history}->{$rev};
            next if $include && $hist->{state} !~ /$include/;
            next if $exclude && $hist->{state} =~ /$exclude/;

            push( @results, _formatHistoryRecord( $hist, $fmt, $index++ ) );
        }

        $result = $header . join( $separator, @results ) . $footer;
    }
    catch WorkflowException with {
        shift->warn();
        $result = '';
    };

    return $result;
}

# Tag handler
sub _WORKFLOWTRANSITION {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $form = '';

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic ) = _getTopicParams( $attributes, $web, $topic );
        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        #
        # Build the button to change the current status
        #
        my @actions =
          grep { $controlledTopic->canTransition($_) }
          map  { $_->{action} } $controlledTopic->getTransitions();

        if ( scalar(@actions) ) {
            $form =
              _getString( 'txformhead', $controlledTopic->getCurrentStateName(),
                $web, $topic );

            if ( scalar(@actions) == 1 ) {
                $form .= _getString( 'txformone', $actions[0] );
            }
            else {
                my $acts =
                  join( '', map { _getString( 'txformeach', $_ ) } @actions );
                $form .= _getString( 'txformmany', $acts );
            }

            $form .= _getString('txformfoot');
        }
        else {
            $form .= _getString('txformnone');
        }
    }
    catch WorkflowException with {
        shift->warn();
        $form = '';
    };
    return $form;
}

# Tag handler - button for inquiring state
sub _WORKFLOWSTATE {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $result;

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;

        ( $web, $topic, my $rev ) =
          _getTopicParams( $attributes, $web, $topic );

        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );
        my $state = $attributes->{state};
        $state ||= $controlledTopic->getCurrentStateName();

        my $lastVersion = $controlledTopic->getLast( $state, 'VERSION' ) || '';
        my $hideNull = Foswiki::Func::isTrue( $attributes->{hidenull}, 0 );
        return '' if $hideNull && !$lastVersion;

        my $workflow = $controlledTopic->{workflow};

        my $message = $controlledTopic->{workflow}->getState($state)->{message};
        my $last    = $controlledTopic->getLast($state);
        my $lastUser    = $last->{author};
        my $lastTime    = $last->{date};
        my $lastComment = $last->{comment};

        my @actions = map { $_->{action} } $controlledTopic->getTransitions();
        my $actions = join( ", ", @actions );
        my $numActions = scalar(@actions);

        $result = $attributes->{format} || '$state';

        $result =~ s/\$web/$web/g;
        $result =~ s/\$topic/$topic/g;
        $result =~ s/\$state/$state/g;
        $result =~ s/\$message/$message/g;
        $result =~ s/\$rev/$lastVersion/g;
        $result =~ s/\$user/$lastUser/g;
        $result =~ s/\$time/$lastTime/g;
        $result =~ s/\$comment/$lastComment/g;
        $result =~ s/\$numactions/$numActions/g;
        $result =~ s/\$actions/$actions/g;
        $result =~ s/\$(allowed|allowedit)/\$allowchange/g;    # legacy

        $result =~
s/\$(allow[a-z]+)/$controlledTopic->expandMacros($workflow->getState($state)->{$1} || '')/ge;
    }
    catch WorkflowException with {
        shift->warn();
        $result = '';
    };

    return Foswiki::Func::decodeFormatTokens($result);
}

# Tag handler - button for forking
sub _WORKFLOWFORK {
    my ( $session, $attributes, $topic, $web ) = @_;
    my $result;

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic, my $rev ) =
          _getTopicParams( $attributes, $web, $topic );

        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );

        my $newnames;
        if ( !defined $attributes->{newnames} ) {

            # Old interpretation, for compatibility
            $newnames = $attributes->{_DEFAULT};
            $topic = $attributes->{topic} || $topic;
        }
        else {
            ( $web, $topic ) = _getTopicParams( $attributes, $web, $topic );
            $newnames = $attributes->{newnames};
        }

        if ($newnames) {
            my $lockdown = Foswiki::Func::isTrue( $attributes->{lockdown} );

            my $errors = '';
            if ( !Foswiki::Func::topicExists( $web, $topic ) ) {
                $errors .= _getString( 'badct', "$web.$topic" );
            }

            foreach my $newname ( split( ',', $newnames ) ) {
                my ( $w, $t ) =
                  Foswiki::Func::normalizeWebTopicName( $web, $newname );
                if ( Foswiki::Func::topicExists( $w, $t ) ) {
                    $errors .= _getString( 'forkalreadyexists', "$w.$t" );
                }
            }

            if ($errors) {
                $result = $errors;
            }
            else {
                my $label = $attributes->{label} || 'Fork';
                $result = _getString( 'txforkbutton',
                    "$web.$topic", $newnames, $lockdown, $label );
            }
        }
        else {
            $result = _getString( 'wrongparams', 'WORKFLOWFORK' );
        }
    }
    catch WorkflowException with {
        $result = shift->debug();
    };
    return $result;
}

# Tag handler - report on last time in a certain state
sub _WORKFLOWLAST {
    my ( $session, $attr, $topic, $web ) = @_;

    my $result;

    # undef _DEFAULT, otherwise legacy code in _getTopicParams will
    # try to interpret it as a topic name
    my $state = $attr->{_DEFAULT};
    undef $attr->{_DEFAULT};

    return _getString( 'wrongparams', 'WORKFLOWLAST' )
      unless $state;

    try {
        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        ( $web, $topic, my $rev ) = _getTopicParams( $attr, $web, $topic );
        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic, $rev );
        my $record = $controlledTopic->getLast($state);
        if ($record) {
            my $format = $attr->{format} || '$rev: $state $author $date';
            $result = _formatHistoryRecord( $record, $format );
        }
        else {
            $result = _getString( 'neverinstate', "$web.$topic", $state );
        }
    }
    catch WorkflowException with {
        $result = shift->debug();
    };
    return $result;
}

# Deprecated
sub _WORKFLOWLASTREV {
    my ( $session, $attr, $topic, $web ) = @_;
    return _getString( 'wrongparams', 'WORKFLOWLASTREV' )
      unless $attr->{_DEFAULT};
    $attr->{format} = '$rev';
    return _WORKFLOWLAST( $session, $attr, $topic, $web );
}

# Deprecated
sub _WORKFLOWLASTTIME {
    my ( $session, $attr, $topic, $web ) = @_;
    return _getString( 'wrongparams', 'WORKFLOWLASTTIME' )
      unless $attr->{_DEFAULT};
    $attr->{format} = '$day $month $year - $hours:$minutes';
    return _WORKFLOWLAST( $session, $attr, $topic, $web );
}

# Deprecated
sub _WORKFLOWLASTUSER {
    my ( $session, $attr, $topic, $web ) = @_;
    return _getString( 'wrongparams', 'WORKFLOWLASTUSER' )
      unless $attr->{_DEFAULT};
    $attr->{format} = '$author';
    return _WORKFLOWLAST( $session, $attr, $topic, $web );
}

sub _WORKFLOWLASTVERSION {
    my ( $session, $attr, $topic, $web ) = @_;
    my $result;

    my $state = $attr->{_DEFAULT};
    return _getString( 'wrongparams', 'WORKFLOWLASTVERSION' )
      unless $state;
    undef $attr->{_DEFAULT};

    try {
        ( $web, $topic, my $rev ) = _getTopicParams( $attr, $web, $topic );
        $result = _getString( 'lastversion', $web, $topic, $state );
    }
    catch WorkflowException with {
        $result = shift->debug();
    };
    return $result;
}

# REST handler to change topic state
# Requires:
# topic
# WORKFLOWACTION
# WORKFLOWSTATE
# Optional:
# WORKFLOWCOMMENT
sub _restChangeState {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    ASSERT($query) if DEBUG;

    try {
        my $topic = $query->param('topic');
        throw WorkflowException( undef, 'wrongparams', 'topic' )
          unless $topic;

        ( my $web, $topic ) = _getTopicParams( {}, undef, $topic );

        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        my $action = $query->param('WORKFLOWACTION');
        throw WorkflowException( $controlledTopic, 'wrongparams',
            'WORKFLOWACTION' )
          unless $action;

        my $state = $query->param('WORKFLOWSTATE') // '';
        throw WorkflowException( $controlledTopic, 'wrongparams',
            "WORKFLOWSTATE $state!=" . $controlledTopic->getCurrentStateName() )
          unless $state eq $controlledTopic->getCurrentStateName();

        # Check that no-one else has a lease on the topic
        my $breaklock = $query->param('breaklock');
        $breaklock = Foswiki::Func::isTrue($breaklock);

        my $comment = $query->param('WORKFLOWCOMMENT');

        my $newForm =
          $controlledTopic->changeState( $action, $comment, $breaklock );

        # If there is a form with the new state, and it's not
        # the same form as previously, we need to kick into edit
        # mode to support form field changes. The current user will
        # have been temorarily granted change access if necessary.
        my $url;
        if ($newForm) {
            $url = Foswiki::Func::getScriptUrl(
                $web, $topic, 'edit',
                breaklock    => $breaklock,
                t            => time(),
                formtemplate => $newForm,
                template     => 'workflowedit',

                # Flag the transitional state to the edit
                WORKFLOWINTRANSITION => $action
            );
        }
        else {
            $url = Foswiki::Func::getScriptUrl( $web, $topic, 'view' );
            $url = $session->redirectto($url);
        }

        Foswiki::Func::redirectCgiQuery( undef, $url );
    }

    catch WorkflowException with {

        # Convert the exception into an oops
        _oops(@_);
    }

    catch Foswiki::OopsException with {
        my $e = shift;
        $e->generate($session);
    };
    return undef;
}

# REST handler - fork
sub _restFork {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    try {
        my $topic = $query->param('topic');
        throw WorkflowException( undef, 'wrongparams', 'topic' )
          unless $topic;

        ( my $web, $topic ) = _getTopicParams( {}, undef, $topic );

        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        my $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        my @forks;

        my @newnames = split( /\s*,\s*/, $query->param('newnames') );
        foreach my $newName (@newnames) {
            $newName = Foswiki::Sandbox::untaintUnchecked($newName);
            my ( $newWeb, $newTopic ) =
              Foswiki::Func::normalizeWebTopicName( $web, $newName );
            throw WorkflowException( 'badtopic', "$newWeb.$newTopic" )
              unless Foswiki::Func::isValidTopicName( $newTopic, 1 )
              && Foswiki::Func::isValidWebName($newWeb);
            push( @forks, { web => $newWeb, topic => $newTopic } );
        }

        my $lockdown = $query->param('lockdown');

        $controlledTopic->fork( \@forks, $lockdown );
    }
    catch WorkflowException with {

        # Convert the exception into an oops
        _oops(@_);
    }

    catch Foswiki::OopsException with {
        my $e = shift;
        $e->generate($session);
    };
    return undef;
}

# Used to trap an edit and check that it is permitted by the workflow
sub beforeEditHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    # Presence of the WORKFLOWINTRANSITION parameter indicates that
    # this edit is the follow-on to a state transition. In this case
    # the topic may contain a temporary grant of CHANGE permission.
    my $query = Foswiki::Func::getCgiQuery();
    return unless $query->param('WORKFLOWINTRANSITION');

    my $controlledTopic;

    try {
        ( $web, $topic ) = _getTopicParams( {}, $web, $topic );

        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        # canEdit will clear any temporary grant
        unless ( $controlledTopic->canEdit(1) ) {
            throw Foswiki::OopsException(
                'accessdenied',
                status => 403,
                def    => 'topic_access',
                web    => $_[2],
                topic  => $_[1],
                params => [
                    'Edit',
                    _getString(
                        'cantedit',
                        Foswiki::Func::getWikiName()
                          . $controlledTopic->{workflow}->{name}
                    )
                ]
            );
        }
    }
    catch WorkflowException with {

        # Set up failed, so there should be no object in the exception
        shift->debug(1);
    };
}

# Check that the user is allowed to attach to the topic, if it is controlled.
sub beforeAttachmentSaveHandler {
    my ( $attrHashRef, $topic, $web ) = @_;

    my $controlledTopic;
    try {
        ( $web, $topic ) = _getTopicParams( {}, $web, $topic );

        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        unless ( $controlledTopic->canEdit() ) {
            throw Foswiki::OopsException(
                'accessdenied',
                status => 403,
                def    => 'topic_access',
                web    => $_[2],
                topic  => $_[1],
                params => [
                    'Attach',
                    _getString(
                        'cantedit',
                        Foswiki::Func::getWikiName()
                          . $controlledTopic->{workflow}->{name}
                    )
                ]
            );
        }
    }
    catch WorkflowException with {

        # Set up failed, so there should be no object in the exception
        shift->debug(1);
    };
}

sub _solrIndexTopicHandler {
    my ( $indexer, $doc, $web, $topic, $meta, $text ) = @_;

    my $controlledTopic;
    try {
        ( $web, $topic ) = _getTopicParams( {}, $web, $topic );

        require Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
        $controlledTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load( $web,
            $topic );

        $doc->add_fields( "field_WorkflowState_s" =>
              $controlledTopic->getCurrentStateName() );
    }
    catch WorkflowException with {
        shift->debug(1);
    };
}

1;
__END__

Copyright (C) 2005 Thomas Hartkens <thomas@hartkens.de>
Copyright (C) 2005 Thomas Weigert <thomas.weigert@motorola.com>
Copyright (C) 2008-2017 Crawford Currie http://c-dot.co.uk

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details, published at
http://www.gnu.org/copyleft/gpl.html

