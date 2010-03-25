package WorkflowPluginSuite;

use Unit::TestSuite;
our @ISA = qw( Unit::TestSuite );

sub name { 'WorkflowPluginSuite' }

sub include_tests { qw(WorkflowPluginTests) }

1;
