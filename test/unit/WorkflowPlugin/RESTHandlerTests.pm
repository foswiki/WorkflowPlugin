# Tests for WorkflowPlugin REST handlers
# Note that macros (tags) are tested in TagTests
use strict;

package RESTHandlerTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki::Plugins::WorkflowPlugin;
use Unit::Request::Rest;
use Foswiki::EngineException;
use Error ':try';

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

our $UI_FN;

# Set up the test fixture
sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    $UI_FN = $this->getUIFn('rest');

    my $user = Foswiki::Func::getWikiName();
    $this->{test_workflow} = 'ClassTestWorkflow';

    Foswiki::Func::saveTopic( $this->{test_web}, $this->{test_workflow},
        undef, <<FORM);
| *State* | *Allow Edit* | *Allow View* | *Message* |
| S1      |              |              | S1 message |
| S2      | nobody       | nobody       | S2 message |
| S3      | %META{"formfield" name="F2"}% | $user        | S3 message |
| S4      | %META{"formfield" name="F1"}% | %META{"formfield" name="F2"}% | S3 message |

| *State*  | *Action* | *Next State*  | *Allowed* | *Form*        |
| S1       | toS2     | S2            | nobody    |               |
| S1       | toS3     | S3            |           | TestForm      |
| S2       | to S3    | S3            | $user     | TestForm      |
| S3       | to S1    | S1            |  %META{"formfield" name="F1"}% | |   
| S4       | to S2    | S2            |  %META{"formfield" name="F2"}% | |   

   * Set WORKFLOWDEBUG = 1
FORM

    Foswiki::Func::saveTopic( $this->{test_web}, 'TestControlled', undef,
        <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498867200" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author4" date="1499126400" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498953600" }%
%META:WORKFLOWHISTORY{name="3" state="S1" author="Author3" date="1499040000" }%
%META:FIELD{name="Workflow" value="$this->{test_workflow}"}%
%META:FIELD{name="F1" value="$user"}%
TOPIC
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

sub test_changeState {
    my $this = shift;
    my $query = Unit::Request::Rest->new( { action => ['rest'] } );
    $query->path_info('/WorkflowPlugin/changeState');
    $query->method('post');

    # Make sure login is checked
    $this->createNewFoswikiSession( undef, $query );
    my $text;
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::EngineException with {
        my $e = shift;
        $this->assert_equals( 401, $e->{status}, $e );
        $this->assert_matches( qr/\(401\)/, $e->{reason}, $e );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    # Make sure CT is checked
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::OopsException with {
        $this->assert_equals( 'workflow:wrongparams', $@->{def} );
        $this->assert_equals( 'topic',                $@->{params}->[0] );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    # Make sure CT is checked
    $query->param( 'topic', $this->{test_web} . '.TestControlled' );
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::EngineException with {
        $this->assert( 0, "Bad engine exception" );
    }
    catch Foswiki::OopsException with {
        $this->assert_equals( 'workflow:wrongparams', $@->{def} );
        $this->assert_equals( 'WORKFLOWACTION',       $@->{params}->[0] );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    $query->param( 'WORKFLOWACTION', 'to S1' );
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::OopsException with {
        $this->assert_equals( 'workflow:wrongparams', $@->{def} );
        $this->assert_equals( 'WORKFLOWSTATE !=S3',   $@->{params}->[0] );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    $query->param( 'WORKFLOWSTATE', 'S4' );
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::OopsException with {
        $this->assert_equals( 'workflow:wrongparams', $@->{def} );
        $this->assert_equals( 'WORKFLOWSTATE S4!=S3', $@->{params}->[0] );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    $query->param( 'WORKFLOWSTATE',   'S3' );
    $query->param( 'WORKFLOWCOMMENT', 'spider crab' );

    # Transition with no new form. Should 302 to view the topic
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    otherwise {
        $this->assert( 0, @_ );
    };
    $this->assert_matches( qr/^Status: 302\r?$/m, $text );
    $this->assert_matches(
        qr/^Location: .*\/view\/$this->{test_web}\/TestControlled\r?$/m,
        $text );

    # Make sure the state change actually happened!
    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );
    my $hr = $controlledTopic->getLast("S1");
    $this->assert_equals( 2,    $hr->{name} );
    $this->assert_equals( "S1", $hr->{state} );
    $this->assert( time - $hr->{date} < 10000, $hr->{date} );
    $this->assert_equals( "spider crab", $hr->{comment} );
    $this->assert( !$controlledTopic->canTransition("toS2") );
    $this->assert( $controlledTopic->canTransition("toS3") );

    # Transition with a form 'TestForm'
    $query->param( 'WORKFLOWSTATE',   'S1' );
    $query->param( 'WORKFLOWACTION',  'toS3' );
    $query->param( 'WORKFLOWCOMMENT', 'lobster' );
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    otherwise {
        $this->assert( 0, @_ );
    };
    $text =~ s/\r//gs;
    $this->assert_matches( qr/^Status: 302$/m, $text );
    $this->assert(
        $text =~
          /^Location: .*\/edit\/$this->{test_web}\/TestControlled\?(.*)$/m,
        $text
    );
    my %ps = map { /^(.*)=(.*)$/; $1 => $2 } split( /;/, $1 );
    $this->assert_equals( 'toS3',         $ps{WORKFLOWINTRANSITION} );
    $this->assert_equals( '0',            $ps{breaklock} );
    $this->assert_equals( 'TestForm',     $ps{formtemplate} );
    $this->assert_equals( 'workflowedit', $ps{template} );
    $this->assert_matches( qr/^\d+$/, $ps{t} );

    # Reload to check
    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'TestControlled' );
    $hr = $controlledTopic->getLast("S3");
    $this->assert_equals( 3,    $hr->{name} );
    $this->assert_equals( "S3", $hr->{state} );
    $this->assert( time - $hr->{date} < 10000, $hr->{date} );
    $this->assert_equals( "lobster", $hr->{comment} );
}

sub test_fork {
    my $this = shift;

    Foswiki::Func::saveTopic( $this->{test_web}, 'ForkHandles', undef, <<TOPIC);
%META:WORKFLOW{name="S3"}%
%META:WORKFLOWHISTORY{name="1" state="S1" author="Author1" date="1498867200" }%
%META:WORKFLOWHISTORY{name="4" state="S1" author="Author4" date="1499126400" }%
%META:WORKFLOWHISTORY{name="2" state="S1" author="Author2" date="1498953600" }%
%META:WORKFLOWHISTORY{name="3" state="S1" author="Author3" date="1499040000" }%
%META:FORM{name="TestForm"}%
%META:PREFERENCE{name="WORKFLOW" value="$this->{test_workflow}"}%
%META:PREFERENCE{name="WORKFLOWDEBUG" value="on"}%
TOPIC
    my $query = Unit::Request::Rest->new( { action => ['rest'] } );
    $query->path_info('/WorkflowPlugin/fork');
    $query->method('post');

    # Make sure login is checked
    $this->createNewFoswikiSession( undef, $query );
    my $text;
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    catch Foswiki::EngineException with {
        my $e = shift;
        $this->assert_equals( 401, $e->{status}, $e );
        $this->assert_matches( qr/\(401\)/, $e->{reason}, $e );
    }
    otherwise {
        $this->assert( 0, @_ );
    };

    $query->param( 'newnames',
        "$this->{test_web}.CloneTopic1,$this->{test_web}.CloneTopic2" );
    $query->param( 'lockdown', 1 );
    $query->param( 'topic',    $this->{test_web} . '.ForkHandles' );
    $this->createNewFoswikiSession( 'WikiGuest', $query );
    try {
        ($text) = $this->capture( $UI_FN, $this->{session} );
    }
    otherwise {
        $this->assert( 0, Data::Dumper->Dump( [shift] ) );
    };

    $this->assert_matches( qr/^Status: 302\r?$/m, $text );
    $this->assert_matches(
        qr/^Location: .*\/view\/$this->{test_web}\/ForkHandles\r?$/m, $text );

    #print `cat $Foswiki::cfg{DataDir}/$this->{test_web}/ForkHandles.txt`;

    my $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'ForkHandles' );
    my $meta = $controlledTopic->{meta};
    $this->assert_equals( 'TestForm', $meta->get('FORM')->{name} );
    $this->assert_equals( 'S3',       $meta->get('WORKFLOW')->{name} );
    $this->assert_equals(
        Foswiki::Plugins::WorkflowPlugin::getString(
            'forkedto',
            "$this->{test_web}.CloneTopic1, $this->{test_web}.CloneTopic2"
        ),
        $meta->get( 'WORKFLOWHISTORY', '2' )->{comment}
    );

    $controlledTopic =
      Foswiki::Plugins::WorkflowPlugin::ControlledTopic->load(
        $this->{test_web}, 'CloneTopic1' );
    $meta = $controlledTopic->{meta};
    $this->assert_equals( 'TestForm', $meta->get('FORM')->{name} );
    $this->assert_equals( 'S3',       $meta->get('WORKFLOW')->{name} );
    $this->assert_equals(
        Foswiki::Plugins::WorkflowPlugin::getString(
            'forkedfrom', "$this->{test_web}.ForkHandles"
        ),
        $meta->get( 'WORKFLOWHISTORY', '1' )->{comment}
    );
}

1;
