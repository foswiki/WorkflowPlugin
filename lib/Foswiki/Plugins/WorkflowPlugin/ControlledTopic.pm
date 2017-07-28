# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Plugins::WorkflowPlugin::ControlledTopic

A thin layer over the meta for a topic that carries meta-information
about the workflow in an easy-to-access way, and provides operations
that support the plugin.

=cut

package Foswiki::Plugins::WorkflowPlugin::ControlledTopic;

use strict;
use Assert;
use Error ':try';

use Foswiki::Func ();
use Foswiki::Plugins::WorkflowPlugin::Workflow;
use Foswiki::Plugins::WorkflowPlugin::WorkflowException;

=begin TML

---++ ClassMethod new($workflow, $web, $topic)

Construct a new ControlledTopic object.
   * =$workflow= - pointer to Workflow object
   * =$web= - web name
   * =$topic= - topic name

=cut

sub new {
    my ( $class, $workflow, $web, $topic ) = @_;
    my $this = bless(
        {
            workflow => $workflow,                       # ref to workflow
            state    => $workflow->getDefaultState(),    # state *name*
            history  => {},
            form     => undef,
            debug    => 0,

            web   => $web,
            topic => $topic,

            meta => undef,
            text => undef,

            # Cache of who's allowed what - dubious value
            _allowed => {}
        },
        $class
    );

    return $this;
}

=begin TML

---++ ClassMethod load($web, $topic [, $rev])

Load an existing controlled topic. Topic must exist.
   * =$web= - web name
   * =$topic= - topic name
   * =$rev= - optional topic revision to load

Will die if it detects anything wrong with the load

=cut

sub load {
    my ( $class, $web, $topic, $rev ) = @_;

    throw WorkflowException( undef, 'badct', "$web.$topic" )
      unless Foswiki::Func::topicExists( $web, $topic );

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic, $rev );

    throw WorkflowException( undef, 'badct', "$web.$topic" ) unless $meta;

    my $workflowName = $meta->getPreference('WORKFLOW');
    if ( !$workflowName && $meta ) {
        $workflowName = $meta->get( 'FIELD', 'Workflow' );
        $workflowName = $workflowName->{value} if $workflowName;
    }

    throw WorkflowException( undef, 'badct', "$web.$topic" )
      unless $workflowName;

    ( my $wfWeb, $workflowName ) =
      Foswiki::Func::normalizeWebTopicName( $web, $workflowName );

    my $workflow =
      Foswiki::Plugins::WorkflowPlugin::Workflow->getWorkflow( $wfWeb,
        $workflowName );

    throw WorkflowException( undef, 'badwf', "$wfWeb.$workflowName" )
      unless $workflow;

    my $this = new( $class, $workflow, $web, $topic );
    $this->{meta} = $meta;
    $this->{text} = $text;
    $this->{debug} =
      Foswiki::isTrue( $workflow->{debug}
          || $meta->getPreference('WORKFLOWDEBUG') );

    my @hysteria = $meta->find('WORKFLOWHISTORY');
    my %hist;
    foreach my $hysteric (@hysteria) {
        if ( defined $hysteric->{name} ) {
            $hist{ $hysteric->{name} } = $hysteric;
        }
        else {
            # Legacy, only a value that is only useful as a
            # comment.  Note: can't simply parse the history
            # format, as it was defined by WORKFLOWHISTORYFORMAT,
            # the default for which was "state -- date", which
            # is pretty useless.
            # See Item8002 for more.
            $hist{-1} = {
                name    => -1,
                state   => $workflow->getDefaultState(),
                date    => 0,
                author  => 'unknown',
                comment => $hysteric->{value}
            };
        }
    }
    $this->{history} = \%hist;

    if ( my $wfr = $meta->get('WORKFLOW') ) {
        $this->{state} = $wfr->{name};

        # Legacy, extract state history
        while ( my ( $k, $v ) = each %$wfr ) {
            if ( $k =~ /^LAST(TIME|USER|COMMENT)_(.*)$/
                && defined $wfr->{"LASTVERSION_$2"} )
            {
                my $rev = $wfr->{"LASTVERSION_$2"};
                $this->{history}->{$rev}->{state} = $2;
                $this->{history}->{$rev}->{name}  = $rev;
                if ( $1 eq 'TIME' ) {
                    $this->{history}->{$rev}->{date} =
                      Foswiki::Time::parseTime($v);
                }
                elsif ( $1 eq 'USER' ) {
                    $this->{history}->{$rev}->{author} = $v;
                }
                elsif ( $1 eq 'COMMENT' ) {
                    $this->{history}->{$rev}->{comment} = $v;
                }
            }
        }
    }
    $this->{form} = $meta->get('FORM');
    $this->{form} = $this->{form}->{name} if $this->{form};

    return $this;
}

=begin TML

---++ ObjectMethod getCurrentStateName() -> $statename

Get the name of the current state of the workflow in this topic

=cut

sub getCurrentStateName {
    my $this = shift;
    return $this->{state};
}

=begin TML

---++ ObjectMethod getCurrentState() -> \%state

Get the row of the workflow state table for the current state
of this topic

=cut

sub getCurrentState {
    my $this = shift;
    return $this->{workflow}->getState( $this->{state} );
}

=begin TML

---++ ObjectMethod getForm() -> $formname

Get the name of the currently attached form.

=cut

sub getForm {
    my $this = shift;
    return $this->{form};
}

=begin TML

---++ ObjectMethod getLast($state) -> \%history

Get the history record stored from the last time the topic
transitioned to the given state. Transition records contain at least
state and date

=cut

sub getLast {
    my ( $this, $state ) = @_;

    my $best;
    foreach my $hist ( values %{ $this->{history} } ) {
        next unless ( $hist->{state} // '' ) eq $state && defined $hist->{date};
        $best = $hist if !$best || $best->{date} < $hist->{date};
    }
    return $best;
}

# Get all the workflow transitions available from the current state
sub getTransitions {
    my ($this) = @_;
    return $this->{workflow}->getTransitions( $this->getCurrentStateName() );
}

# Get the workflow transition for the given action from the current state
sub getTransition {
    my ( $this, $action ) = @_;
    return $this->{workflow}
      ->getTransition( $this->getCurrentStateName(), $action );
}

=begin TML

---++ ObjectMethod setState($statename)

Set the current state. Note does not record history,
doesn't change the form.

=cut

sub setState {
    my ( $this, $state ) = @_;
    $this->{state} = $state;
}

=begin TML

---++ ObjectMethod setForm($formname)

Set the current form.

=cut

sub setForm {
    my ( $this, $form ) = @_;
    $this->{form} = $form;
}

=begin TML

---++ ObjectMethod haveNextState($action) -> $boolean

Return true if a new state is available from the current state using this action

=cut

sub haveNextState {
    my ( $this, $action ) = @_;
    my $tx = $this->getTransition($action);
    return $tx && $this->expandMacros( $tx->{nextstate} // '' );
}

# ---++ ObjectMethod _checkAllowed($allowed, $action [, $fwperm])
#    * =$allowed - comma-separated list of permitted actors
#    * =$action= - a unique identifier for the action being checked
#    * =$fwperm= - optional Foswiki permission that is also required
#      e.g. CHANGE.
#
# Finds out if the current user is allowed to perform the given
# action.
#
# They are allowed if their wikiname is in the (comma,space)-separated
# list of allowed actors, or they are a member of a group in the list.
#
# $allowed is macro-expanded in the content of the current topic.
sub _checkAllowed {
    my ( $this, $allowlist, $action, $fwperm ) = @_;
    ASSERT( $this->{debug} );
    my $thisUser = Foswiki::Func::getWikiName();
    my $id       = "$action:$thisUser";
    return $this->{_allowed}{$id} if defined $this->{_allowed}{$id};

    my $allowed;

    my @allow = split( /\s*,\s*/, $this->expandMacros( $allowlist // '' ) );

    #print STDERR "_checkAllowed $id in ". join(',', @allow)."\n"; #detail

    if ( grep { $_ eq 'nobody' } @allow ) {

        #print STDERR "None can $action\n";#detail
        Foswiki::Func::writeDebug( __PACKAGE__ . " nobody is allowed $action" )
          if $this->{debug};
        $allowed = 0;
    }

    elsif ( scalar(@allow) ) {
        my ( @yes, @no );

        #print STDERR "Some can '$action': ".join(',', @allow)."\n";#detail

        # Split into allow (yes) and deny (no)
        foreach my $entry (@allow) {
            ( my $waste, $entry ) =
              Foswiki::Func::normalizeWebTopicName( undef, $entry );

            if ( $entry =~ /^not\((.*)\)$/ ) {
                $entry = $1;
                if ( $entry =~ /^LASTUSER_(.+)$/ ) {
                    $entry = $this->{workflow}->getLast($1);
                    if ($entry) {
                        $entry = $entry->{author};
                        $entry =~ s/^.*\.//;    # strip web
                    }
                }

                #print STDERR "$entry cannot\n";#detail
                push( @no, $entry );
            }

            else {
                #print STDERR "$entry can\n";#detail
                push( @yes, $entry );
            }
        }

        $allowed = 1;

        # not() trumps everything else
        if ( scalar(@no) ) {
            foreach my $entry (@no) {
                if ( $entry eq $thisUser
                    || Foswiki::Func::isGroup($entry)
                    && Foswiki::Func::isGroupMember( $entry, $thisUser, {} ) )
                {
                    #print STDERR "NO trumps YES\n";#detail
                    Foswiki::Func::writeDebug( __PACKAGE__
                          . " $thisUser denied '$action' by explicit not() listing"
                    ) if $this->{debug};
                    $allowed = 0;
                    last;
                }
            }
        }

        if ( $allowed && scalar(@yes) ) {
            $allowed = 0;
            foreach my $entry (@yes) {
                if ( $entry eq $thisUser
                    || Foswiki::Func::isGroup($entry)
                    && Foswiki::Func::isGroupMember( $entry, $thisUser, {} ) )
                {
                    #print STDERR "YES is allowed\n";#detail
                    Foswiki::Func::writeDebug( __PACKAGE__
                          . " $thisUser allowed '$action' by explicit name listing"
                    ) if $this->{debug};
                    $allowed = 1;
                    last;
                }
            }
        }

    }
    else {
        Foswiki::Func::writeDebug( __PACKAGE__ . " Anyone is allowed $action" )
          if $this->{debug};
        $allowed = 1;
    }

   #print STDERR "Start FW ".($allowed // '?')." ".($fwperm // '?')."\n";#detail

    if ( $allowed && $fwperm ) {

        # Workflow allows it, but does Foswiki

        # DO NOT PASS $this->{meta}, because of Item11461
        $allowed =
          Foswiki::Func::checkAccessPermission( $fwperm,
            Foswiki::Func::getWikiName(),
            $this->{text}, $this->{topic}, $this->{web} ) // 0;

        unless ($allowed) {
            Foswiki::Func::writeDebug __PACKAGE__
              . " $action/$fwperm is denied by Foswiki ACLs\n"
              if $this->{debug};
        }
    }

    #print STDERR "Nonadmin ".($allowed || 0)."\n";#detail
    if ( !$allowed && Foswiki::Func::isAnAdmin() ) {
        $allowed = 1;
        Foswiki::Func::writeDebug __PACKAGE__
          . " $action denied, but $thisUser is admin\n"
          if $this->{debug};
    }

    $this->{_allowed}{$id} = $allowed;

    return $allowed;
}

# ---++ ObjectMethod _addHistory($rev, ...)
# Add a new history record. The fields are set in the params.
# e.g. addHistory{1, author => "fred", ...)
sub _addHistory {
    my ( $this, $name, %data ) = @_;
    $data{name} = $name;

    $this->{history}->{$name} = \%data;
}

=begin TML

---++ ObjectMethod canEdit($ungrant) -> $boolean

Determine if workflow allows editing for the current user.
   =$ungrant= - if there has been a temporary grant of change access, clear it

=cut

sub canEdit {
    my ( $this, $ungrant ) = @_;
    my $state = $this->getCurrentState();

    #print STDERR "canEdit ".Data::Dumper->Dump([$state]);#detail

    if ($ungrant) {
        my $grant =
          $this->{meta}->find( 'PREFERENCE', 'WORKFLOWTEMPORARYGRANT' );
        if ($grant) {
            my $c = $this->{meta}->find( 'PREFERENCE', 'ALLOWTOPICCHANGE' );
            if ( $c =~ s/,$grant$// ) {
                $this->{meta}->put(
                    'PREFERENCE',
                    {
                        name  => 'ALLOWTOPICHANGE',
                        value => $c
                    }
                );
            }
            return 1;
        }
    }

    return $this->_checkAllowed( $state->{allowchange}, 'allowchange',
        'CHANGE' );
}

=begin TML

---++ ObjectMethod canView() -> $boolean

Determine if workflow allows viewing for the current user.

=cut

sub canView {
    my $this  = shift;
    my $state = $this->getCurrentState();

    #print STDERR "canView ".Data::Dumper->Dump([$state]);#detail
    return $this->_checkAllowed( $state->{allowview}, 'allowview', 'VIEW' );
}

=begin TML

---++ ObjectMethod canTransition($action) -> $boolean

Determine if workflow allows the given action for the current user.
Note that admin users can always transition, and can override workflow
rules.
   * =$action= - the action to test

=cut

sub canTransition {
    my ( $this, $action ) = @_;
    my $tx = $this->getTransition($action);
    my $ok = 1;

    unless ($tx) {
        $ok = 0;
        Foswiki::Func::writeDebug __PACKAGE__
          . " $action transition does not exist"
          if $this->{debug};
    }

    # Check if the transition is allowed for this user under workflow rules
    my $step =
      $this->getCurrentStateName() . "..$tx->{action}..$tx->{nextstate}";

    #print STDERR "canTransition $step\n";#detail
    unless ( $this->_checkAllowed( $tx->{allowed}, $action ) ) {
        $ok = 0;
        Foswiki::Func::writeDebug( __PACKAGE__ . " $step denied by workflow" )
          if $this->{debug};
    }

    if ( !$ok && Foswiki::Func::isAnAdmin() ) {
        $ok = 1;
        Foswiki::Func::writeDebug(
            __PACKAGE__ . " $step denied, but user is admin" )
          if $this->{debug};
    }

    return $ok;
}

=begin TML

---++ ObjectMethod changeState($action[, $comment [,$breaklock]]) -> $form

Change the state of the topic, noitifying the change to listeners
and saving the topic.
   * =$action= - the action from the current state
   * =$comment= - comment accompanying the state change
   * =$breaklock= - if true, stomp over any lease on the topic
Note that the current user may not have permission to edit the topic
after the transition. However if a form is added, they need to
be able to edit to fill in the form. To that end, they are
automatically (and temporarily) granted CHANGE for the next edit only.

Note this method does *not* check if the transition is permitted for
the current user under workflow rules.

@throw WorkflowException if there's a problem

@return the name of the new form, if the form has changed, undef otherwise

=cut

sub changeState {
    my ( $this, $action, $comment, $breaklock ) = @_;

    ASSERT(
        !defined $this->{meta}->getLoadedRev()
          || $this->{meta}->getLatestRev() == $this->{meta}->getLoadedRev(),
        "latest rev needed"
    ) if DEBUG;

    unless ( $this->canTransition($action) ) {
        throw WorkflowException( $this, 'nosuchtx', $this->{workflow}->{name},
            Foswiki::Func::getWikiName, $action, $this->getCurrentStateName() );
    }

    my $oldForm = $this->getForm() // '';
    my $newForm = $this->getTransition($action)->{form} // '';
    my $newState = $this->haveNextState($action);

    # If there is a form with the new state, and it's not
    # the same form as previously, we need to kick into edit
    # mode to support form field changes. In this case the
    # transition is delayed until after the edit is saved
    # (the transition is executed by the beforeSaveHandler)
    $newForm = ( $newForm && $newForm ne $oldForm ) ? $newForm : undef;

    unless ($breaklock) {
        my ( $url, $loginName, $t ) =
          Foswiki::Func::checkTopicEditLock( $this->{web}, $this->{topic} );
        if ($t) {
            my $currUser = Foswiki::Func::getCanonicalUserID();
            my $locker   = Foswiki::Func::getCanonicalUserID($loginName);
            if ( $locker ne $currUser ) {
                $t = Foswiki::Time::formatDelta( $t,
                    $Foswiki::Plugins::SESSION->i18n );
                throw WorkflowException( $this, 'leaseconflict',
                    Foswiki::Func::getWikiName($locker),
                    "$this->{web}.$this->{topic}", $t );
            }
        }
    }

    my ( $revdate, $revuser, $version ) = $this->{meta}->getRevisionInfo();
    if ( ref($revdate) eq 'HASH' ) {
        my $info = $revdate;
        ( $revdate, $revuser, $version ) =
          ( $info->{date}, $info->{author}, $info->{version} );
    }

    my $tx = $this->getTransition($action);

    $this->setState( $tx->{nextstate} );

    $this->_addHistory(
        $version + 1,    # should be, we force an increment
        state   => $this->getCurrentStateName(),
        author  => Foswiki::Func::getWikiUserName(),
        date    => time(),
        comment => $comment
    );

    $this->{form} = $tx->{form};

    $this->save( 0, $newForm );

    Foswiki::Func::writeDebug( __PACKAGE__
          . " $this->{web}.$this->{topic} transitioned to "
          . $this->getCurrentStateName() . " by "
          . Foswiki::Func::getWikiName() )
      if $this->{debug};

    $this->_notify($tx);

    return $newForm;
}

# Notify all interested parties that the given transition has just
# been executed.
sub _notify {
    my ( $this, $tx ) = @_;

    # Expand vars in the notify list. This supports picking up the
    # value of the notifees from the topic itself.
    my $notify = $this->expandMacros( $tx->{notify} // '' );

    return unless $notify;

    # Dig up the bodies
    my @persons = split( /\s*,\s*/, $notify );
    my @emails;
    my @templates;
    my $web = $this->{web};

    # Parse the notify column
    foreach my $who (@persons) {
        if ( $who =~ /^$Foswiki::regex{emailAddrRegex}$/ ) {
            push( @emails, $who );
        }
        elsif ( $who =~ /^template\((.*)\)$/ ) {

            # Read template topic if provided with one
            my ( $tw, $tt ) = Foswiki::Func::normalizeWebTopicName( $web, $1 );
            if ( Foswiki::Func::topicExists( $tw, $tt ) ) {
                ( undef, my $templatetext ) =
                  Foswiki::Func::readTopic( $tw, $tt );
                push(
                    @templates,
                    {
                        text  => $templatetext,
                        web   => $tw,
                        topic => $tt,
                    }
                );
            }
            else {
                Foswiki::Func::writeWarning(
                    __PACKAGE__ . " cannot find email template '$tw.$tt'" );
            }
        }
        else {
            if ( $who =~ /^LASTUSER_([A-Z]+)$/ ) {

                $who = $this->getLast($1);
                $who = $who->{author} if $who;
            }

            $who =~ s/^.*\.//;    # web name?
            my @list = Foswiki::Func::wikinameToEmails($who);
            if ( scalar(@list) ) {
                push( @emails, @list );
            }
            else {
                Foswiki::Func::writeWarning( __PACKAGE__
                      . " cannot send mail to '$who'"
                      . " - cannot determine an email address" );
            }
        }
    }

    return unless scalar(@emails);

    # Have a list of recipients

    my $tofield = join( ',', @emails );

    # Set values for exapansion in the email templates
    Foswiki::Func::setPreferencesValue( 'EMAILTO',      $tofield );
    Foswiki::Func::setPreferencesValue( 'TARGET_STATE', $tx->{nextstate} );
    Foswiki::Func::setPreferencesValue( 'TRANSITION',   $tx->{name} );

    if ( scalar(@emails) ) {

        # See if this workflow has a custom default email template defined
        # in preferences
        my $override =
          $this->{workflow}->getPreference('WORKFLOWDEFAULTEMAILTEMPLATE');

        my $tmpl;
        if ($override) {
            my ( $otweb, $ottopic ) =
              Foswiki::Func::normalizeWebTopicName( $web, $override );
            if ( Foswiki::Func::topicExists( $otweb, $ottopic ) ) {
                ( undef, $tmpl ) = Foswiki::Func::readTopic( $otweb, $ottopic );
            }
            else {
                Foswiki::Func::writeWarning( __PACKAGE__
                      . " cannot find topic '$otweb.$ottopic'"
                      . " - falling back to default email template" );
            }
        }

        # Otherwise use the default template
        $tmpl ||= Foswiki::Func::loadTemplate('mailworkflowtransition');

        $tmpl = $this->expandMacros($tmpl);
        my $errors = Foswiki::Func::sendEmail( $tmpl, 3 );
        if ($errors) {
            Foswiki::Func::writeWarning(
                __PACKAGE__ . ' Failed to send transition mails: ' . $errors );
        }
    }

    # See if this workflow has one or more custom email templates defined
    # in the *Notify* column
    if ( scalar(@templates) ) {
        foreach my $template (@templates) {
            Foswiki::Func::setPreferencesValue( 'TEMPLATE',
                "$template->{web}.$template->{topic}" );
            my $text = $this->expandMacros( $template->{text} );
            my $errors = Foswiki::Func::sendEmail( $text, 3 );
            if ($errors) {
                Foswiki::Func::writeWarning( __PACKAGE__
                      . ' Failed to send transition mails: '
                      . $errors );
            }
        }
    }
}

=begin TML

---++ ObjectMethod save($lockdown, $temporaryGrant)

Save the topic to the store.
   * =lockdown= can be used to lock the topic for changes after save.
   * =$temporaryGrant= can be used to grant the current user CHANGE
     access for the next edit only.

=cut

sub save {
    my ( $this, $lockdown, $temporaryGrant ) = @_;

    # Move history into meta
    my $meta = $this->{meta};
    ASSERT($meta) if DEBUG;

    foreach my $rev ( values %{ $this->{history} } ) {
        $meta->putKeyed( 'WORKFLOWHISTORY', $rev );
    }

    my $state = $this->getCurrentStateName();
    $this->{meta}->put( 'WORKFLOW', { name => $state } );
    $this->{meta}->put( 'FORM', { name => $this->{form} } ) if $this->{form};

    my %perms;
    foreach my $mode (qw/CHANGE VIEW/) {
        $perms{$mode} = [
            split(
                /\s*,\s*/,
                $this->expandMacros(
                    $this->{workflow}->{states}->{$state}->{ lc("allow$mode") }
                )
            )
        ];
        $this->{meta}->remove( 'PREFERENCE', "ALLOWTOPIC$mode" );
        $this->{meta}->remove( 'PREFERENCE', "DENYTOPIC$mode" );
    }

    # Lockdown is used in forking
    $perms{CHANGE} = ['nobody'] if ($lockdown);

    while ( my ( $mode, $whos ) = each %perms ) {
        foreach my $who (@$whos) {
            if ( $who =~ /not\((.*)\)/ ) {
                $this->{meta}->putKeyed(
                    'PREFERENCE',
                    {
                        name  => "DENYTOPIC$mode",
                        title => "DENYTOPIC$mode",
                        value => $1,
                        type  => 'Set'
                    }
                );
            }
            else {
                $this->{meta}->putKeyed(
                    'PREFERENCE',
                    {
                        name  => "ALLOWTOPIC$mode",
                        title => "ALLOWTOPIC$mode",
                        value => $who,
                        type  => 'Set'
                    }
                );
            }
        }
    }

    # Only add the temporary grant if the current user does *not*
    # have change access after the transition
    if (
        $temporaryGrant
        && !Foswiki::Func::checkAccessPermission(
            'CHANGE',      Foswiki::Func::getWikiName(),
            $this->{text}, $this->{topic},
            $this->{web},  $this->{meta}
        )
      )
    {

        my $c = $this->{meta}->find( 'PREFERENCE', 'ALLOWTOPICHANGE' ) // '';
        $c .= ',' if $c;
        $c .= Foswiki::Func::getWikiName();
        $this->{meta}->putKeyed(
            'PREFERENCE',
            {
                name  => 'WORKFLOWTEMPORARYGRANT',
                value => Foswiki::Func::getWikiName()
            }
        );
        $this->{meta}->putKeyed(
            'PREFERENCE',
            {
                name  => 'ALLOWTOPICCHANGE',
                value => Foswiki::Func::getWikiName()
            }
        );
    }

    Foswiki::Func::saveTopic(
        $this->{web},
        $this->{topic},
        $meta,
        $this->{text},
        {
            forcenewrevision  => 1,
            ignorepermissions => 1
        }
    );
}

=begin TML

---++ ObjectMethod fork(\@forks [,$lockdown])

Create a series of new topics that are clones of this topic, except that
the history of the copied topic is not carried over. Topics being cloned
to must not exist.
   * =\@forks= - array of hashes each containing web, topic for
      the topics being created
   * =$lockdown= - if true, will lock down this topic for changes after
     the cloning is complete

=cut

sub fork {
    my ( $this, $forks, $lockdown ) = @_;
    my $clone;

    foreach $clone (@$forks) {
        throw WorkflowException( $this, 'forkalreadyexists',
            "$clone->{web}.$clone->{topic}" )
          if Foswiki::Func::topicExists( $clone->{web}, $clone->{topic} );
    }

    my $forkedRev = $this->{meta}->getLoadedRev() + 1;
    my $who       = Foswiki::Func::getWikiUserName();

    foreach my $clone (@$forks) {

        # Clone metadata
        my $newMeta =
          Foswiki::Meta->new( $Foswiki::Plugins::SESSION, $clone->{web},
            $clone->{topic} );

        while ( my ( $k, $v ) = each %{ $this->{meta} } ) {

            # Note that we don't carry over the history from the cloned topic
            next if ( $k =~ m/^_/ || $k eq 'WORKFLOWHISTORY' );

            my @data;
            foreach my $item (@$v) {
                my %datum = %$item;
                push( @data, \%datum );
            }
            $newMeta->putAll( $k, @data );
        }

        my $new =
          new( __PACKAGE__, $this->{workflow}, $clone->{web}, $clone->{topic} );
        $new->{state} = $this->{state};
        $new->{meta}  = $newMeta;
        $new->{text}  = $this->{text};

        $new->_addHistory(
            1,
            author   => $who,
            date     => time(),
            state    => $this->getCurrentStateName(),
            forkfrom => "$this->{web}.$this->{topic}",

            # Since there will be a save of the forked topic with
            # 'forcenewrevision' to record the fork information, it's safe
            # to do +1 here.
            rev => $forkedRev
        );

        $new->save();

        Foswiki::Func::writeDebug( __PACKAGE__
              . " $this->{web}.$this->{topic} forked to "
              . "$new->{web}.$new->{topic} by "
              . Foswiki::Func::getWikiName() )
          if $this->{debug};
    }

    # Record the fork in the source topic, and optionally lock it down
    $this->_addHistory(
        $forkedRev,
        author => $who,
        date   => time,
        forkto => join( ',', map { "$_->{web}.$_->{topic}" } @$forks )
    );

    $this->save($lockdown);
}

=begin TML

---++ ObjectMethod expandMacros($text) -> $expandedText

Expand all macros in the text in the context of the topic, and perform
some rendering steps (remove <literal>, <noautolink> and <nop>)

=cut

sub expandMacros {
    my ( $this, $text ) = @_;

    #my $c = Foswiki::Func::getContext();

    # Workaround for Item1071
    #my $memory = $c->{can_render_meta};
    #$c->{can_render_meta} = $this->{meta};
    $text =
      Foswiki::Func::expandCommonVariables( $text, $this->{topic}, $this->{web},
        $this->{meta} );

    #$c->{can_render_meta} = $memory;

    # remove some
    $text =~ s/<\/?(literal|noautolink|nop)>//gi;

    return $text;
}

=begin TML

---++ OnjectMethod stringify() -> $string

Generate a stringified version of the topic, for debugging

=cut

sub stringify {
    my $this        = shift;
    my $tmpmeta     = $this->{meta};
    my $tmpworkflow = $this->{workflow};
    my $tmp_allowed = $this->{_allowed};
    delete $this->{meta};
    $this->{workflow} = $tmpworkflow->{name};
    delete $this->{_allowed};
    require Data::Dumper;
    my $str = Data::Dumper->Dump( [$this] );
    $this->{meta}     = $tmpmeta;
    $this->{workflow} = $tmpworkflow;
    $this->{_allowed} = $tmp_allowed;
    $str =~ s/^\$VAR\d+\s*=\s*//;
    return $str;
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

