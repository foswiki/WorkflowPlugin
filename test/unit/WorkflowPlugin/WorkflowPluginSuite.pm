package WorkflowPluginSuite;

use Unit::TestSuite;
our @ISA = qw( Unit::TestSuite );

sub name { 'WorkflowPluginSuite' }

sub include_tests { qw(ClassTests TagTests RESTHandlerTests) }

1;
