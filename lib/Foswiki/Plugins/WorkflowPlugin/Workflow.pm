# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Plugins::WorkflowPlugin::Workflow

This object represents a workflow definition.

=cut

package Foswiki::Plugins::WorkflowPlugin::Workflow;

use strict;
use Error ':try';

use Foswiki::Func           ();
use Foswiki::Plugins        ();
use Foswiki::Tables::Parser ();

use Foswiki::Plugins::WorkflowPlugin::WorkflowException;

# Cache of workflows.
our %cache;

=begin TML

---++ ClassMethod getWorkflow($web, $topic) -> $workflow

Get the workflow object for the workflow described in the given topic.

=cut

sub getWorkflow {
    my ( $class, $web, $topic ) = @_;

    if ( $cache{"$web.$topic"} ) {
        return $cache{"$web.$topic"};
    }

    if ( defined &Foswiki::Sandbox::untaint ) {
        $web = Foswiki::Sandbox::untaint( $web,
            \&Foswiki::Sandbox::validateWebName );
        $topic = Foswiki::Sandbox::untaint( $topic,
            \&Foswiki::Sandbox::validateTopicName );
    }

    return undef unless ( $web && $topic );

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    unless (
        Foswiki::Func::checkAccessPermission(
            'VIEW', $Foswiki::Plugins::SESSION->{user},
            $text, $topic, $web, $meta
        )
      )
    {
        throw WorkflowException( undef, 'badwf', "$web.$topic" );
    }

    my $this = bless(
        {
            name        => "$web.$topic",
            states      => {},
            transitions => [],
            tags        => '',
            debug       => $meta->getPreference('WORKFLOWDEBUG')
        },
        $class
    );

    my @expectTables = ( 'STATE', 'TRANSITION' );
    my $inTable;
    my @fields;

    my $field_index = 0;
    my $data        = {};

    my $handler = sub {
        my $event = shift;

        return 0 if ( !$inTable && !scalar(@expectTables) );

        if ( $event eq 'th' ) {
            my $th = lc( $_[1] || '' );
            $th =~ s/[^\w.]//gi;
            if ( !$inTable && $th eq 'state' ) {
                $inTable = shift @expectTables;
                @fields  = ();
                ##print STDERR "Open table $inTable\n";
            }
            if ($inTable) {
                ##print STDERR "Add field $th\n";
                $th =~ s/edit$/change/;    # compatibility
                push( @fields, $th );
            }
        }

        elsif ($inTable) {
            if ( $event eq 'td' ) {
                ##print STDERR "TD $fields[$field_index] = '$_[1]'\n";
                $data->{ $fields[ $field_index++ ] } = $_[1];
            }

            elsif ( $event eq 'close_tr' && $data->{state} ) {

                #print STDERR "/TR ";

                if ( $inTable eq 'TRANSITION' ) {

#print STDERR "Add transition $data->{state}..$data->{action}..$data->{nextstate}\n";
                    push( @{ $this->{transitions} }, $data );
                }

                elsif ( $inTable eq 'STATE' ) {

                    #print STDERR "Add state '$data->{state}'\n";
                    $this->{states}->{ $data->{state} } = $data;
                    unless ( $this->{defaultState} ) {
                        $this->{defaultState} = $data->{state};

                        #print STDERR "Default state '$this->{defaultState}'\n";
                    }
                }
                $data        = {};
                $field_index = 0;
            }

            elsif ( $event eq 'close_table' ) {
                $inTable = undef;
            }
        }
        return 0;
    };
    Foswiki::Tables::Parser::parse( $text, $handler );
    throw WorkflowException( $this, 'badwf', "$web.$topic" )
      if !$this->{defaultState} || scalar(@expectTables);

    $cache{"$web.$topic"} = $this;

    # Extract tag settings from *Set and META:PREFERENCE and
    # set session preferences
    my @broke = split( /^$Foswiki::regex{setVarRegex}/m, $text );
    while ( my $pref = shift @broke ) {
        next unless ( $pref // '' ) eq 'Set';
        $pref = shift @broke;
        next unless ( $pref // '' ) =~ /^WORKFLOW[a-zA-Z0-9_]+$/;
        Foswiki::Func::setPreferencesValue( $pref, shift @broke // '' );
    }

    foreach my $pref ( $meta->find('PREFERENCE') ) {
        if ( $pref->{name} =~ /^WORKFLOW/ ) {
            Foswiki::Func::setPreferencesValue( $pref->{name}, $pref->{value} );
        }
    }

    return $this;
}

=begin TML

---++ ObjectMethod getTransitions($statename) -> \@transitions

Get all the transitions (transition table rows) from the given given state.

=cut

sub getTransitions {
    my ( $this, $state ) = @_;
    my @transitions;
    foreach my $t ( @{ $this->{transitions} } ) {
        push( @transitions, $t ) if ( $t->{state} eq $state );
    }
    return @transitions;
}

=begin TML

---++ ObjectMethod getTransition($statename, $action) -> \%transition

Get the transition (tranbsition table row) matching the given current
state and action

=cut

sub getTransition {
    my ( $this, $state, $action ) = @_;
    foreach my $t ( $this->getTransitions($state) ) {
        return $t if $t->{action} eq $action;
    }
    return undef;
}

=begin TML

---++ ObjectMethod getState($name) -> \%state

Get the hash (state table row) that describes the named state

=cut

sub getState {
    my ( $this, $name ) = @_;
    return $this->{states}->{$name};
}

=begin TML

---++ ObjectMethod getDefaultState() -> $stateName

Get the name of the default state

=cut

sub getDefaultState {
    my $this = shift;
    return $this->{defaultState};
}

# Dump a workflow topic for debugging
sub stringify {
    my $this = shift;

    my @lines = ();

    sub _mkarr {
        my $obj = shift;
        return [ map { $obj->{$_} // "ud$_" } @_ ];
    }

    push( @lines, '', '---++ States' );
    my %allows;
    foreach my $st ( values %{ $this->{states} } ) {
        foreach my $col ( keys %$st ) {
            $allows{$col} = 1 if $col =~ /^allow/;
        }
    }
    my @allowcols = sort keys %allows;

    my @ac = map { /^allow(.*)$/; '*Allow ' . uc($1) . '*' } @allowcols;
    push( @lines, [ '*State*', @ac, '*Message*' ] );
    foreach my $st ( values %{ $this->{states} } ) {
        push( @lines, _mkarr( $st, 'state', @allowcols, 'message' ) );
    }

    push( @lines, '', '---++ Transitions' );
    push( @lines,
        [ '*State*', '*Action*', '*Next State*', '*Allowed*', '*Form*' ] );
    foreach my $tx ( @{ $this->{transitions} } ) {
        push( @lines, _mkarr( $tx, qw/state action nextstate allowed form/ ) );
    }
    return join( "\n", map { ref($_) ? join( '|', '', @$_, '' ) : $_ } @lines );
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
