# Tests for WORKFLOW* macros
# Note that REST handlers are tested in RESTHandlerTests
package TagTests;

use strict;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki::Plugins::WorkflowPlugin;
use Foswiki::Plugins::WorkflowPlugin::Workflow;
use Foswiki::Plugins::WorkflowPlugin::ControlledTopic;
use Foswiki::Plugins::WorkflowPlugin::WorkflowException;

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

sub loadExtraConfig {
    my $this = shift;
    $this->SUPER::loadExtraConfig(@_);
    $Foswiki::cfg{Plugins}{WorkflowPlugin}{Module} ||=
      'Foswiki::Plugins::WorkflowPlugin';
    $Foswiki::cfg{Plugins}{WorkflowPlugin}{Enabled} = 1;
}

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    my $user = $this->{test_user_wikiname};
    $this->{test_workflow} = 'TestWorkflow';

    Foswiki::Func::saveTopic( $this->{test_web}, $this->{test_workflow},
        undef, <<FORM);
| *State* | *Allow Edit* | *Allow View* | *Message* |
| S1      |              |              | S1 message |
| S2      | nobody       | nobody       | S2 message |
| S3      | somebody     | $user        | S3 message |
| S4      | %META{"formfield" name="F1"}% | %META{"formfield" name="F2"}% | S3 message |

| *State*  | *Action* | *Next State*  | *Allowed* | *Form*        |
| S1       | toS2     | S2            |           |               |
| S1       | toS3     | S3            | nobody    | TestForm      |
| S2       | to S3    | S3            | $user     | TestForm      |
| S3       | to S1    | S1            |  %META{"formfield" name="F1"}% | |   
FORM

    Foswiki::Func::saveTopic( $this->{test_web}, 'TestControlled', undef,
        <<TOPIC);
   * Set WORKFLOWDEBUG = 1
%META:WORKFLOW{name="S3"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498867200" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author4" date="1499126400" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498953600" }%
%META:WORKFLOWHISTORY{name="3" state="S1" author="Author3" date="1499040000" }%
%META:FORM{name="TestForm"}%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
TOPIC
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

sub getExpanded {
    my $def = shift;
    Foswiki::Func::loadTemplate('workflowstrings');
    my $s = Foswiki::Func::expandTemplate( 'workflow:' . $def );
    $s =~ s{%PARAM(\d+)%}{$_[$1 - 1] // "?$1"}ge;
    return Foswiki::Func::expandCommonVariables($s);
}

# Make sure all the expected string ids have strings on the end of them
sub test_strings {
    my $this = shift;
    my $s;

    # Make sure there's a def for each string ID
    foreach my $def (
        qw/
        attachbutton badct badwf cantedit editbutton forkalreadyexists forkedfrom
        forkedto lastversion leaseconflict neverinstate nosuchtx strikeattach
        strikeedit txforkbutton txformeach txformfoot txformhead txformmany
        txformnone txformone wrongparams
        /
      )
    {
        $s =
          Foswiki::Plugins::WorkflowPlugin::_getString( $def, 'p1', 'p2', 'p3',
            'p4', 'p5', 'p6' );
        $this->assert( defined $s && $s ne '', $def );
    }
    $s = getExpanded( 'txforkbutton', 'p1', 'p2', 'p3', 'Fork', 'p5', 'p6' );
    $this->assert_matches( qr/value="Fork"/, $s );
}

sub test_WORKFLOWSTATE {
    my $this = shift;
    $this->assert_equals(
        'S3',
        Foswiki::Func::expandCommonVariables(
            '%WORKFLOWSTATE%', 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWSTATEMESSAGE {
    my $this = shift;
    my $text = '%WORKFLOWSTATEMESSAGE%';
    $this->assert_equals(
        'S3 message',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWEDITTOPIC1 {
    my $this = shift;

    # Not allowed to edit in state S3
    my $text = '%WORKFLOWEDITTOPIC{topic="TestControlled"}%';

    #print STDERR "State S3\n";
    $this->assert_html_equals(
"<strike>Edit</strike><!--Workflow does not permit WikiGuest to modify $this->{test_web}.TestControlled-->",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWEDITTOPIC2 {
    my $this = shift;

    # Force to state S1, allow edit should be unrestricted
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestS1', undef, <<TOPIC);
   * Set WORKFLOWDEBUG = 1
   * Set WORKFLOW = $this->{test_workflow}
%META:WORKFLOW{name="S1"}%
%META:FORM{name="TestForm"}%
TOPIC
    my $text = '%WORKFLOWEDITTOPIC{topic="TestS1"}%';
    my $editurl =
      Foswiki::Func::getScriptUrl( $this->{test_web}, 'TestS1', 'edit' );

    #print STDERR "State S1\n";
    my $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestS1',
        $this->{test_web} );
    $act =~ s/\?t=\d+//;
    $this->assert_html_equals( "<a href='$editurl'><strong>Edit<\/strong><\/a>",
        $act );
}

sub test_WORKFLOWATTACHTOPIC1 {
    my $this = shift;

    # Not allowed to attach in state S3
    my $text = '%WORKFLOWATTACHTOPIC{topic="TestControlled"}%';

    #print STDERR "State S3\n";
    $this->assert_html_equals(
"<strike>Attach<\/strike><!--Workflow does not permit WikiGuest to modify $this->{test_web}.TestControlled-->",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWATTACHTOPIC2 {
    my $this = shift;

    # Force to state S1, allow edit should be unrestricted
    Foswiki::Func::saveTopic( $this->{test_web}, 'TestS1', undef, <<TOPIC);
   * Set WORKFLOWDEBUG = 1
   * Set WORKFLOW = $this->{test_workflow}
%META:WORKFLOW{name="S1"}%
%META:FORM{name="TestForm"}%
TOPIC
    my $text = '%WORKFLOWATTACHTOPIC{topic="TestS1"}%';
    my $editurl =
      Foswiki::Func::getScriptUrl( $this->{test_web}, 'TestS1', 'attach' );

    #print STDERR "State S1\n";
    my $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestS1',
        $this->{test_web} );
    $act =~ s/\?t=\d+//;
    $this->assert_html_equals(
        "<a href='$editurl'><strong>Attach<\/strong><\/a>", $act );
}

sub test_WORKFLOWTRANSITION {
    my $this     = shift;
    my $text     = '%WORKFLOWTRANSITION%';
    my $expected = Foswiki::Func::expandCommonVariables(<<HERE);
<form method="POST" action="%SCRIPTURL{"rest"}%/WorkflowPlugin/changeState">
<input type="hidden" name="WORKFLOWSTATE" value="S3" />
<input type="hidden" name="topic" value="%WEB%.TestControlled" />
<input type="hidden" name="t" value="?" />
<input type="hidden" name="WORKFLOWACTION" value="to S1" />
<input type="submit" class="%WORKFLOWTRANSITIONCSSCLASS%" name="to S1" value="to S1" />
</form>
HERE
    my $actual =
      Foswiki::Func::expandCommonVariables( $text, 'TestControlled',
        $this->{test_web} );
    $actual =~ s/value=["']?\d+["']?/value="?"/;
    $this->assert_html_equals( $expected, $actual );
}

sub test_WORKFLOWFORK {
    my $this = shift;
    my $text = '%WORKFLOWFORK%';
    my $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestControlled',
        $this->{test_web} );
    $this->assert_equals( getExpanded( 'wrongparams', 'WORKFLOWFORK' ), $act );
    $text = '%WORKFLOWFORK{newnames="TestControlled"}%';
    $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestControlled',
        $this->{test_web} );
    $this->assert_equals(
        getExpanded( 'forkalreadyexists', "$this->{test_web}.TestControlled" ),
        $act
    );
}

sub test_WORKFLOWLAST {
    my $this = shift;
    my $text = '%WORKFLOWLAST{"S1"}%';
    $this->assert_equals(
        '4: S1 Author4 ' . Foswiki::Time::formatTime( 1499126400, '$http' ),
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLAST{"S1" format="$user $epoch"}%';
    $this->assert_equals(
        'Author4 1499126400',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWLASTVERSION {
    my $this = shift;
    my $text = '%WORKFLOWLASTVERSION%';
    my $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestControlled',
        $this->{test_web} );
    $this->assert_equals( getExpanded( 'wrongparams', 'WORKFLOWLASTVERSION' ),
        $act );
    $text = '%WORKFLOWLASTVERSION{"S1"}%';
    $act =
      Foswiki::Func::expandCommonVariables( $text, 'TestControlled',
        $this->{test_web} );
    $this->assert_html_equals(
        Foswiki::Func::expandCommonVariables(
                '<a href="%SCRIPTURL{view}%/'
              . $this->{test_web}
              . '/TestControlled?rev=4">revision 4</a>'
        ),
        $act
    );
}

sub checkWORKFLOWLAST_badCommonParams {
    my ( $this, $macro ) = @_;
    $macro = "WORKFLOWLAST$macro";
    my $text = "\%${macro}\{\}%";
    $this->assert_equals(
        "Wrong parameters to $macro",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = "\%$macro%";
    $this->assert_equals(
        "Wrong parameters to $macro",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = "\%$macro\{web=\"FRUIT\"\}%";
    $this->assert_equals(
        "Wrong parameters to $macro",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = "\%$macro\{topic=\"BAT\"\}%";
    $this->assert_equals(
        "Wrong parameters to $macro",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWLASTTIME {
    my $this = shift;
    my $text = '%WORKFLOWLASTTIME{}%';

    $this->checkWORKFLOWLAST_badCommonParams('TIME');

    $text = '%WORKFLOWLASTTIME{"S1" topic="TestControlled"}%';
    $this->assert_equals(
        '04 Jul 2017 - 00:00',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTTIME{"S1"}%';
    $this->assert_equals(
        '04 Jul 2017 - 00:00',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTTIME{"S2"}%';
    $this->assert_equals(
        "$this->{test_web}.TestControlled has never been in state 'S2'",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWLASTUSER {
    my $this = shift;

    $this->checkWORKFLOWLAST_badCommonParams('USER');

    my $text = '%WORKFLOWLASTUSER{"S1" topic="TestControlled"}%';
    $this->assert_equals(
        'Author4',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTUSER{"S1"}%';
    $this->assert_equals(
        'Author4',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTUSER{"S2"}%';
    $this->assert_equals(
        "$this->{test_web}.TestControlled has never been in state 'S2'",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

sub test_WORKFLOWLASTREV {
    my $this = shift;

    $this->checkWORKFLOWLAST_badCommonParams('REV');

    my $text = '%WORKFLOWLASTREV{"S1" topic="TestControlled"}%';
    $this->assert_equals(
        '4',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTREV{"S1"}%';
    $this->assert_equals(
        '4',
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
    $text = '%WORKFLOWLASTREV{"S2"}%';
    $this->assert_equals(
        "$this->{test_web}.TestControlled has never been in state 'S2'",
        Foswiki::Func::expandCommonVariables(
            $text, 'TestControlled', $this->{test_web}
        )
    );
}

1;
