# Tests for Workflow, ControlledTopic and WorkflowException classes
use strict;

package ClassTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki::Plugins::WorkflowPlugin;
use Foswiki::Plugins::WorkflowPlugin::Workflow;
use Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
use Foswiki::Plugins::WorkflowPlugin::WorkflowException;
use Foswiki::Plugins::WorkflowPlugin::Mither;

use Error qw(:try);

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    my $user = Foswiki::Func::getWikiName();
    $this->{test_workflow} = 'ClassTestWorkflow';

    Foswiki::Func::saveTopic( $this->{test_web}, $this->{test_workflow},
        undef, <<FORM);
| *State* | *Allow Edit* | *Allow View* | *Message* |
| S1      |              |              | S1 message |
| S2      | nobody       | nobody       | S2 message |
| S3      | %META{"formfield" name="F2"}% | not($user)        | S3 message |
| S4      | %META{"formfield" name="F1"}% | %META{"formfield" name="F2"}% | S3 message |

| *State*  | *Action* | *Next State*  | *Allowed* | *Form*        | *Notify* |
| S1       | toS2     | S2            | nobody    |               | |
| S1       | toS3     | S3            |           | TestForm      | |
| S2       | to S3    | S3            | $user     | TestForm      | |
| S3       | to S1    | S1            |  %META{"formfield" name="F1"}% | | jack\@craggyisland.ie |
| S4       | to S2    | S2            |  %META{"formfield" name="F2"}% | | |

   * Set WORKFLOWDEBUG = 1
FORM

#Foswiki::Func::saveTopic( $this->{test_web}, 'WorkflowTransitionMailTemplate', undef, "Template check");

    Foswiki::Func::saveTopic(
        $this->{test_web}, 'TestControlled', undef,

        <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498867200" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author4" date="1499126400" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498953600" }%
%META:WORKFLOWHISTORY{name="3" state="S1" author="Author3" date="1499040000" }%
%META:FORM{name="TestForm"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F1" value="$user"}%
%META:FIELD{name="F2" value="FatherTed"}%
TOPIC

    $Foswiki::cfg{EnableEmail} = 1;
    $this->{session}->net->setMailHandler( \&FoswikiFnTestCase::sentMail );
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

# Check the Workflow object construction
sub test_Workflow {
    my $this     = shift;
    my $workflow = Foswiki::Plugins::WorkflowPlugin::Workflow->getWorkflow(
        $this->{test_web}, $this->{test_workflow} );

    $this->assert_equals( "S1", $workflow->getDefaultState() );
    my $st = $workflow->getState("S2");
    $this->assert_equals( "S2",         $st->{state} );
    $this->assert_equals( "nobody",     $st->{allowchange} );
    $this->assert_equals( "nobody",     $st->{allowview} );
    $this->assert_equals( "S2 message", $st->{message} );

    my $tx = $workflow->getTransition( "S1", "toS3" );
    $this->assert_equals( "S1",       $tx->{state} );
    $this->assert_equals( "S3",       $tx->{nextstate} );
    $this->assert_equals( "",         $tx->{allowed} );
    $this->assert_equals( "TestForm", $tx->{form} );

    my @txs = $workflow->getTransitions("S1");
    $this->assert_num_equals( 2, scalar @txs );
    @txs = $workflow->getTransitions("S2");
    $this->assert_num_equals( 1, scalar @txs );

    # Check cache
    my $workflow_2 = Foswiki::Plugins::WorkflowPlugin::Workflow->getWorkflow(
        $this->{test_web}, $this->{test_workflow} );
    $this->assert( $workflow_2 == $workflow );

    #print STDERR $workflow->stringify();
}

# Tests for loading a modern controlled topic
sub test_ControlledTopic {
    my $this = shift;

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );

    my $rec = $controlledTopic->getLast("S1");
    $this->assert_equals( 4,          $rec->{name} );
    $this->assert_equals( 'S1',       $rec->{state} );
    $this->assert_equals( 1499126400, $rec->{date} );
    $this->assert_equals( 'Author4',  $rec->{author} );

    my @tx = $controlledTopic->getTransitions();
    $this->assert_deep_equals(
        [
            {
                'allowed'   => '%META{"formfield" name="F1"}%',
                'form'      => '',
                'nextstate' => 'S1',
                'state'     => 'S3',
                'action'    => 'to S1',
                'notify'    => 'jack@craggyisland.ie'
            }
        ],
        \@tx
    );
    $this->assert_deep_equals(
        {
            'allowed'   => '%META{"formfield" name="F1"}%',
            'form'      => '',
            'nextstate' => 'S1',
            'state'     => 'S3',
            'notify'    => 'jack@craggyisland.ie',
            'action'    => 'to S1'
        },
        $controlledTopic->getTransition('to S1')
    );
}

# Tests for a legacy topic, with history cache in META:WORKFLOW and
# old format WORKFLOWHISTORY
sub test_ControlledTopic_legacy {
    my $this = shift;
    Foswiki::Func::saveTopic( $this->{test_web}, 'LegacyTopic', undef,
        <<LEGACY);
	* Set WORKFLOW = $this->{test_workflow}
| *Workflow* ||
| Current state | %WORKFLOWSTATE% |
| Transitions available | %WORKFLOWTRANSITION% |
| State message | %WORKFLOWSTATEMESSAGE% |
| Last time in APPROVED state | %WORKFLOWLASTTIME_APPROVED% |
| Last version in APPROVED state | %WORKFLOWLASTVERSION_APPROVED% |

Workflow history: %WORKFLOWHISTORY%

%META:FORM{name="TestForm"}%
%META:WORKFLOWHISTORY{value="<br>S3 -- 02 Dec 2008 - 12:10<br>S4 -- 03 Mar 2009 - 18:04<br>S1 -- 03 Mar 2009 - 18:10"}%
%META:WORKFLOW{name="S1" LASTTIME_S1="03 Mar 2009 - 18:10" LASTTIME_S4="03 Mar 2009 - 18:04" LASTTIME_S3="02 Dec 2008 - 12:10" LASTVERSION_S1="6" LASTVERSION_S4="4" LASTVERSION_S3="2" LASTUSER_S1="Author4" LASTCOMMENT_S1="s1comment"}%
%META:FORM{name="TestForm"}%
%META:FIELD{name="Workflow" value="WorkflowName"}%
LEGACY

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'LegacyTopic' );
    my $rec = $controlledTopic->getLast("S1");
    $this->assert_equals( 6,           $rec->{name} );
    $this->assert_equals( 'S1',        $rec->{state} );
    $this->assert_equals( 1236103800,  $rec->{date} );
    $this->assert_equals( 'Author4',   $rec->{author} );
    $this->assert_equals( 's1comment', $rec->{comment} );

    # Make sure %META works - Item1071
    $this->assert_equals(
        'LegacyTopic WorkflowName',
        $controlledTopic->expandMacros(
            '%TOPIC% %META{"formfield" name="Workflow"}%')
    );
}

# Make sure a changeState does what we expect
sub test_ControlledTopic_changeState {
    my $this = shift;

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );

    my $form = $controlledTopic->changeState( 'to S1', 'fruitbat' );
    $this->assert( !$form );

    # Reload to check
    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );
    my $hr = $controlledTopic->getLast("S1");
    $this->assert_equals( 2,    $hr->{name} );
    $this->assert_equals( "S1", $hr->{state} );
    $this->assert( time - $hr->{date} < 10000, $hr->{date} );
    $this->assert_equals( "fruitbat", $hr->{comment} );
    $this->assert( !$controlledTopic->canTransition("toS2") );
    $this->assert( $controlledTopic->canTransition("toS3") );

    $form = $controlledTopic->changeState( 'toS3', 'golem' );

    # Form isn't changing, so...
    $this->assert_null($form);

    # In S3, only F2 can edit i.e. FatherTed
    #print `cat $Foswiki::cfg{DataDir}/$this->{test_web}/TestControlled.txt`;
    $this->assert(
        !Foswiki::Func::checkAccessPermission(
            "CHANGE", Foswiki::Func::getWikiName(),
            undef,    $controlledTopic->{topic},
            $controlledTopic->{web}
        )
    );
    $this->assert(
        !Foswiki::Func::checkAccessPermission(
            "VIEW", Foswiki::Func::getWikiName(),
            undef,  $controlledTopic->{topic},
            $controlledTopic->{web}
        )
    );
    $this->assert(
        Foswiki::Func::checkAccessPermission(
            "VIEW", $this->{test_user},
            undef,  $controlledTopic->{topic},
            $controlledTopic->{web}
        )
    );
    $this->assert(
        Foswiki::Func::checkAccessPermission(
            "CHANGE", $this->{test_user},
            undef,    $controlledTopic->{topic},
            $controlledTopic->{web}
        )
    );

    # Reload to check
    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );
    $hr = $controlledTopic->getLast("S3");

    $this->assert_equals( 3,    $hr->{name} );
    $this->assert_equals( "S3", $hr->{state} );
    $this->assert( time - $hr->{date} < 10000, $hr->{date} );
    $this->assert_equals( "golem", $hr->{comment} );

    $this->assert_num_equals( 1, scalar(@FoswikiFnTestCase::mails) );

    foreach my $mail (@FoswikiFnTestCase::mails) {
        $this->assert_equals(
            "$this->{test_web}.TestControlled - transitioned to S1",
            $mail->header('Subject') );
        $this->assert_equals( 'jack@craggyisland.ie', $mail->header('To') );
    }
    @FoswikiFnTestCase::mails = ();

}

# Make sure a fork does what we expect
sub test_ControlledTopic_fork {
    my $this = shift;

    # Move the workflow name ito a formfield to test that
    Foswiki::Func::saveTopic( $this->{test_web}, 'ForkHandles', undef, <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498867200" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author4" date="1499126400" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498953600" }%
%META:WORKFLOWHISTORY{name="3" state="S1" author="Author3" date="1499040000" }%
%META:FORM{name="TestForm"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:PREFERENCE{name="WORKFLOWDEBUG" value="on"}%
TOPIC

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'ForkHandles' );

    $controlledTopic->fork(
        [
            {
                web   => $this->{test_web},
                topic => 'CloneTopicAUTOINC0'
            },
            {
                web   => $this->{test_web},
                topic => 'CloneTopicAUTOINC0'
            },
            {
                web   => $this->{test_web},
                topic => 'CloneTopic999'
            }

        ]
    );

    #print `cat $Foswiki::cfg{DataDir}/$this->{test_web}/ForkHandles.txt`;

    # Reload to check
    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'ForkHandles' );

    #print Data::Dumper->Dump([$controlledTopic->{history}],['old']);

    $this->assert_equals( $this->{test_workflow},
        $controlledTopic->{meta}->get( "FIELD", "Workflow" )->{value} );

    $this->assert_equals(
        Foswiki::Plugins::WorkflowPlugin::getString(
            'forkedto',
"$this->{test_web}.CloneTopic0, $this->{test_web}.CloneTopic1, $this->{test_web}.CloneTopic999"
        ),
        $controlledTopic->{history}->{2}->{comment}
    );

    foreach my $ft ( 0, 1, 999 ) {
        my $forkedTopic =
          Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
            $this->{test_web}, "CloneTopic$ft" );

        $this->assert_equals( $this->{test_workflow},
            $forkedTopic->{meta}->get( "FIELD", "Workflow" )->{value} );

        #print Data::Dumper->Dump([$forkedTopic->{history}],['new']);

        $this->assert_equals(
            $controlledTopic->getCurrentStateName,
            $forkedTopic->getCurrentStateName
        );
        $this->assert_equals(
            Foswiki::Plugins::WorkflowPlugin::getString(
                'forkedfrom', "$this->{test_web}.ForkHandles"
            ),
            $forkedTopic->{history}->{1}->{comment}
        );
    }
}

# Make sure fails are cleanly handled
sub test_ControlledTopic_badLoad {
    my $this = shift;
    eval {
        Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
            $this->{test_web}, 'DoesNotExist' );
        $this->assert( 0, "Expected it to fail" );
    };
    my $e = $@;
    $this->assert( $e, "Expected it to fail" );

    #print STDERR Data::Dumper->Dump([$e]);
    $this->assert_equals( "badct", $e->{def} );
}

sub test_accessControls1 {
    my $this = shift;
    my $user = Foswiki::Func::getWikiName();

    # In state S2, nobody can view or edit. $user can transition.
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestInvisible', undef,
        <<TOPIC);
%META:WORKFLOW{name="S2"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F2" value="$user"}%
TOPIC
    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestInvisible' );
    $this->assert( !$controlledTopic->canView() );
    $this->assert( !$controlledTopic->canEdit() );
    $this->assert( $controlledTopic->canTransition("to S3") );
}

sub test_accessControls2 {
    my $this = shift;
    my $user = Foswiki::Func::getWikiName();

    # In state S3, F2 can edit, $user can view. F1 can transition.
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestInvisible', undef,
        <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F1" value="$user"}%
%META:FIELD{name="F2" value="RinceWind"}%
TOPIC
    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestInvisible' );

    # not($user) excludes us
    $this->assert( !$controlledTopic->canView() );

    # Only RinceWind can edit
    $this->assert( !$controlledTopic->canEdit() );
    $this->assert( $controlledTopic->canTransition("to S1") );
}

sub test_accessControls3 {
    my $this = shift;
    my $user = Foswiki::Func::getWikiName();

    # In state S3, F2 can edit, $user can view. F1 can transition.
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestInvisible', undef,
        <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F1" value="MeMePickMe"}%
%META:FIELD{name="F2" value="$user"}%
TOPIC
    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestInvisible' );
    $this->assert( !$controlledTopic->canView() );
    $this->assert( $controlledTopic->canEdit() );
    $this->assert( !$controlledTopic->canTransition("to S1") );
}

# Make sure a changeState does what we expect
sub test_ControlledTopic_changeToRestrictedState {
    my $this = shift;
    my $user = Foswiki::Func::getWikiName();

    # In state S2, nobody can view or edit. $user can transition.
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestPlugs', undef, <<TOPIC);
%META:WORKFLOW{name="S2"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F1" value="TwoFlower"}%
%META:FIELD{name="F2" value="CohenTheBarbarian"}%
TOPIC

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestPlugs' );

    $controlledTopic->changeState('to S3');

    # Reload to check
    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestPlugs' );
    my $hr = $controlledTopic->{history}->{2};
    $this->assert_equals( 2,    $hr->{name} );
    $this->assert_equals( "S3", $hr->{state} );
    $this->assert_equals( "",   $hr->{comment} );

    my ( $meta, $text ) =
      Foswiki::Func::readTopic( $this->{test_web}, 'TestPlugs' );
    $this->assert_equals( "CohenTheBarbarian",
        $meta->getPreference("ALLOWTOPICCHANGE") );

    #print `cat $Foswiki::cfg{DataDir}/$this->{test_web}/TestPlugs.txt`;
    $this->assert_equals( "WikiGuest", $meta->getPreference("DENYTOPICVIEW") );

    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestPlugs' );
    $this->assert( !$controlledTopic->canEdit() );
}

sub test_mither {
    my $this = shift;

    Foswiki::Func::saveTopic(
        $this->{test_web}, 'TestMither', undef,

        <<TOPIC);
%META:WORKFLOW{name="S1"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498810000" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498820000" }%
%META:WORKFLOWHISTORY{name="3" state="S3" author="Author3" date="1498830000" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author3" date="1498840000" }%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
TOPIC

    Foswiki::Plugins::WorkflowPlugin::Mither::mither(
        topic    => ["$this->{test_web}.TestM*r"],
        workflow => $this->{test_workflow},
        states   => { S1 => 1 }
    );
    $this->assert_num_equals( 1, scalar(@FoswikiFnTestCase::mails) );

    foreach my $mail (@FoswikiFnTestCase::mails) {
        $this->assert_equals( "$this->{test_web}.TestMither stuck in S1",
            $mail->header('Subject') );
        $this->assert_equals( 'jack@craggyisland.ie', $mail->header('To') );
    }
    @FoswikiFnTestCase::mails = ();
}

1;
