# See bottom of file for license and copyright information

=begin TML

---+ package WorkflowException

Exceptions specific to workflows

=cut

package WorkflowException;

use Assert;
use Error ();
our @ISA = ('Error');

use Foswiki::Plugins::WorkflowPlugin ();

=begin TML

---++ ClassMethod new($object, $def, @params)

Construct a new exception object.
   * =$object= either a ControlledTopic or a Workflow object, or undef
   * =$def= def name from workflowstrings.tmpl (sans workflow: prefix)
   * @params - any number of params for populating the template

=cut

sub new {
    my ( $class, $object, $def, @params ) = @_;
    my $this = $class->SUPER::new();

    $this->{def}    = $def;
    $this->{params} = \@params;
    $this->{object} = $object;

    return $this;
}

sub stringify {
    my $this = shift;
}

=begin TML

---++ ObjectMethod debug([$always]) -> $string

If there is an object associated with the exception and debug is
set in that object, or $always is true, stringify the exception.

If global debug is set in =configure=, write the string to
the debug log. Return the generated string.

=cut

sub debug {
    my ( $this, $always ) = @_;
    my $str = '';

    if ( $always || $this->{object} && $this->{object}->{debug} ) {

        $str = Foswiki::Func::expandCommonVariables(
            Foswiki::Plugins::WorkflowPlugin::getString(
                $this->{def}, @{ $this->{params} }
            )
        );
    }
    if ( $str && $Foswiki::cfg{Plugins}{WorkflowPlugin}{Debug} ) {
        Foswiki::Func::writeDebug( __PACKAGE__ . $str );
    }
    return $str;
}

1;
__END__
Copyright (C) 2017 Crawford Currie http://c-dot.co.uk

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details, published at
http://www.gnu.org/copyleft/gpl.html

