# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2005-2018 Peter Thoeny, peter[at]thoeny.org and
# TWiki Contributors. All Rights Reserved. TWiki Contributors are
# listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the TWiki root.

# Still do to:
# Handle continuation lines (see Prefs::parseText). These should always
# go into a text area.

package TWiki::Plugins::PreferencesPlugin;

use strict;

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version
use Error qw(:try);

our $VERSION = '$Rev: 30528 (2018-07-16) $';
our $RELEASE = '2018-07-05';

my @shelter;
my $MARKER = "\007"; # James Bond!

# Markers used during form generation
my $START_MARKER  = $MARKER.'STARTPREF'.$MARKER;
my $END_MARKER    = $MARKER.'ENDPREF'.$MARKER;

my $SET_REGEX     =
    qr{^((?:\t|   )+\*\s+\#?(?:Set|Local)\s+)(\w+)\s*\=(.*$(\n(   |\t)+ *[^\s*].*$)*)}m;


sub initPlugin {
    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning( 'Version mismatch between PreferencesPlugin and Plugins.pm' );
        return 0;
    }
    @shelter = ();

    return 1;
}

# Item7008
my $TO_ADDTOHEAD_WHEN_EDIT = <<'END';
<style type='text/css'>
.twikiPrefFieldTable {display: inline-table; vertical-align: top;}
.twikiPrefFieldDiv {display: inline}
.twikiPrefFieldLabelDisabled {color: #888;}
.twikiPrefFieldHash {visibility: hidden;}
.twikiPrefFieldLabelDisabled .twikiPrefFieldHash {visibility: visible;}
</style>
<!--[if IE]>
<style type='text/css'>
.twikiPrefFieldTable {display: inline; vertical-align: top;}
</style>
<![endif]-->
<script type='text/javascript'>
if( window.jQuery ) {
    $( function () {
        var disabledClass = 'twikiPrefFieldLabelDisabled';
        $( '.twikiPrefEnableCheckbox' ).each( function () {
            var $checkbox = $(this);
            if( $checkbox.attr( 'name' ).match( /(.*?)!/ ) ) {
                var name = RegExp.$1;
                var $label = $( '#twikiPrefFieldLabel-' + name );
                if( !$checkbox.attr( 'checked' ) ) {
                    $label.addClass( disabledClass );
                }
                $checkbox.change( function () {
                    if( $checkbox.attr( 'checked' ) ) {
                        $label.removeClass( disabledClass );
                    } else {
                        $label.addClass( disabledClass );
                    }
                } );
            }
        } );
    } );
}
</script>
END

sub beforeCommonTagsHandler {
    ### my ( $text, $topic, $web ) = @_;
    my $topic = $_[1];
    my $web = $_[2];
    return unless ( $_[0] =~ m/%EDITPREFERENCES(?:{(.*?)})?%/ );
    my $varParams = $1 || '';

    require CGI;
    require TWiki::Attrs;
    my $formDef;
    my $attrs = new TWiki::Attrs( $varParams );
    if( defined( $attrs->{_DEFAULT} )) {
        my( $formWeb, $form ) = TWiki::Func::normalizeWebTopicName(
            $web, $attrs->{_DEFAULT} );

        # SMELL: Unpublished API. No choice, though :-(
        require TWiki::Form;    # SMELL
        $formDef =
          new TWiki::Form( $TWiki::Plugins::SESSION, $formWeb, $form );
    }
    my $editButton = $attrs->{editbutton} || 'Edit Preferences';

    my $query = TWiki::Func::getCgiQuery();

    my $action = lc( $query->param( 'prefsaction' ) || '' );
    $query->Delete( 'prefsaction' ) if( $query );
    $action =~ s/\s.*$//;

    if ( $action eq 'edit' ) {
        # Item7009
        unless ( TWiki::Func::checkAccessPermission('CHANGE',
                     TWiki::Func::getWikiName(), undef, $topic, $web )
        ) {
            throw TWiki::OopsException(
                'accessdenied',
                def => 'topic_access',
                web => $web,
                topic => $topic,
                params => [ 'CHANGE',
                            $TWiki::Plugins::SESSION->security->getReason() ]
            );
        }

        TWiki::Func::setTopicEditLock( $web, $topic, 1 );
        
        # Item7272
        $_[0] =~ s/%(INCLUDE\{[\w%\/.]+WebPreferencesHelp)/%<nop>$1/g;

        # Item7008
        TWiki::Func::addToHEAD('PreferencesPlugin', $TO_ADDTOHEAD_WHEN_EDIT);

        # Replace setting values by form fields but not inside comments Item4816
        my $outtext = '';
        my $insidecomment = 0;
        foreach my $token ( split/(<!--|-->)/, $_[0] ) {
            if ( $token =~ /<!--/ ) {
                $insidecomment++;
            } elsif ( $token =~ /-->/ ) {
                $insidecomment-- if ( $insidecomment > 0 );
            } elsif ( !$insidecomment ) {
                $token =~ s{$SET_REGEX}
                    {_generateEditField($query, $web, $topic, $2, $3, $formDef, $1)}ge;
            }
            $outtext .= $token;
        }
        $_[0] = $outtext;

        $_[0] =~ s/%EDITPREFERENCES(\{.*?\})?%/
          _generateControlButtons($web, $topic)/ge;
        my $script = TWiki::Func::getContext()->{authenticated} ?
            'view' : 'viewauth';
        my $viewUrl = TWiki::Func::getScriptUrl( $web, $topic, $script );
        my $startForm = CGI::start_form(
            -name => 'editpreferences',
            -method => 'post',
            -action => $viewUrl );
        $startForm =~ s/\s+$//s;
        my $endForm = CGI::end_form();
        $endForm =~ s/\s+$//s;
        $_[0] =~ s/^(.*?)$START_MARKER(.*)$END_MARKER(.*?)$/$1$startForm$2$endForm$3/s;
        $_[0] =~ s/$START_MARKER|$END_MARKER//gs;
        $_[0] =~ s/<(\/?)verbatim>/<pre>&lt;$1verbatim&gt;<\/pre>/g;
    }

    if( $action eq 'cancel' ) {
        TWiki::Func::setTopicEditLock( $web, $topic, 0 );

    } elsif( $action eq 'save' ) {

        # save can only be used with POST method, not GET
        unless( $query && $query->request_method() !~ /^POST$/i ) {
            my( $meta, $text ) = TWiki::Func::readTopic( $web, $topic );
            $text =~ s{$SET_REGEX}
                {_saveSet($query, $web, $topic, $2, $3, $formDef, $1)}ge;
            TWiki::Func::saveTopic( $web, $topic, $meta, $text );
        }
        TWiki::Func::setTopicEditLock( $web, $topic, 0 );
        # Finish with a redirect so that the *new* values are seen
        my $viewUrl = TWiki::Func::getScriptUrl( $web, $topic, 'view' );
        TWiki::Func::redirectCgiQuery( undef, $viewUrl );
        return;
    }
    # implicit action="view", or drop through from "save" or "cancel"
    $_[0] =~ s/%EDITPREFERENCES(\{.*?\})?%/_generateEditButton($web, $topic, $editButton)/ge;
}

# Use the post-rendering handler to plug our formatted editor units
# into the text
sub postRenderingHandler {
    ### my ( $text ) = @_;

    $_[0] =~ s/SHELTER$MARKER(\d+)/$shelter[$1]/g;
}

# Pluck the default value of a named field from a form definition
sub _getField {
    my( $formDef, $name ) = @_;
    foreach my $f ( @{$formDef->{fields}} ) {
        if( $f->{name} eq $name ) {
            return $f;
        }
    }
    return undef;
}

# Item7008
sub _prefFieldClass {
    return "class='" .
        ($_[0] =~ /table/ ? 'twikiPrefFieldTable' : 'twikiPrefFieldDiv') .
        "'";
}

# Generate a field suitable for editing this type. Use of the core
# function 'renderFieldForEdit' ensures that we will pick up
# extra edit types defined in other plugins.
sub _generateEditField {
    my( $query, $web, $topic, $name, $value, $formDef, $prefix ) = @_;
    $value =~ s/^\s*(.*?)\s*$/$1/gs;
    $value =~ s/\n[ \t]+/\n/g;

    my ($extras, $html);

    if( $formDef ) {
        my $fieldDef;
        if (defined(&TWiki::Form::getField)) {
            # TWiki 4.2 and later
            $fieldDef = $formDef->getField( $name );
        } else {
            # TWiki < 4.2
            $fieldDef = _getField( $formDef, $name );
        }
        if ( $fieldDef ) {
            if ( $fieldDef->{type} && $fieldDef->{type} eq 'label' ) {
                return "$prefix$name = $value";
            }
            if( defined(&TWiki::Form::renderFieldForEdit)) {
                # TWiki < 4.2 SMELL: use of unpublished core function
                ( $extras, $html ) =
                  $formDef->renderFieldForEdit( $fieldDef, $web, $topic, $value);
            } else {
                # TWiki 4.2 and later SMELL: use of unpublished core function
                ( $extras, $html ) =
                  $fieldDef->renderForEdit( $web, $topic, $value );
            }
        }
    }
    if ( $html ) {
        # Item7008
        $html =~ s/(<(table|div))\b/"$1 " . _prefFieldClass($1)/ieg;
    }
    else {
        # No form definition, default to text field.
        $html = CGI::textfield( -class=>'twikiEditFormError twikiInputField',
                                -name => $name,
                                -size => 80, -value => $value );
    }

    my $localPrefix = ( $prefix =~ /Local/ ) ? 'Local' : '';
    if ( $localPrefix ) {
        $html =~ s/\b(name=([\"\']))($name\2)/$1$localPrefix$3/g;
    }
    push( @shelter, $html );

    $prefix =~ s/(\#?)\b(Set|Local)\b(.*)/_generateEnableCheckbox( $localPrefix.$name, $1 )/e;
    my $hash = CGI::span( {class=>'twikiPrefFieldHash'}, '#' );
    my $scope = $2;
    my $space = $3;

    return $START_MARKER . $prefix
      . CGI::span( { class=>'twikiAlert',
                     id=>'twikiPrefFieldLabel-'.$localPrefix.$name,
                     style=>'font-weight:bold;' },
                   $hash . $scope . $space . $name . ' = ' )
      . 'SHELTER' . $MARKER . $#shelter . $END_MARKER;
}

sub _generateEnableCheckbox {
    my( $name, $hash ) = @_;
    return CGI::checkbox(
        -name => "$name!enable",
        -checked => !$hash,
        -class => 'twikiPrefEnableCheckbox',
        -label => '',
    );
}

# Generate the button that replaces the EDITPREFERENCES tag in view mode
sub _generateEditButton {
    my( $web, $topic, $buttonLabel ) = @_;

    my $script = TWiki::Func::getContext()->{authenticated} ?
        'view' : 'viewauth';
    my $viewUrl = TWiki::Func::getScriptUrl( $web, $topic, $script );
    my $text = CGI::start_form(
        -name => 'editpreferences',
        -method => 'post',
        -action => $viewUrl . '#EditPreferences' );
    $text .= CGI::input({
        type => 'hidden',
        name => 'prefsaction',
        value => 'edit'});
    my @submitAttrs = (
	-name => 'edit',
	-value=> $buttonLabel,
	-class=> 'twikiButton',
    );
    my $ctx = TWiki::Func::getContext();
    my $inactive = ref $ctx && ( $ctx->{inactive} || $ctx->{content_slave} );
    push(@submitAttrs, '-disabled' => '')
	if ( $inactive );
    $text .= CGI::submit(@submitAttrs);
    $text .= CGI::end_form();
    $text =~ s/\n//sg;
    return $text;
}

# Generate the buttons that replace the EDITPREFERENCES tag in edit mode
sub _generateControlButtons {
    my( $web, $topic ) = @_;

    my $text = "#EditPreferences\n";
    $text .= $START_MARKER.CGI::submit( -name=>'prefsaction',
                                        -value=>'Save new settings',
                                        -class=>'twikiSubmit',
                                        -accesskey=>'s' );
    $text .= '&nbsp;';
    $text .= CGI::submit(-name=>'prefsaction', -value=>'Cancel',
                         -class=>'twikiButton',
                         -accesskey=>'c').$END_MARKER;
    return $text;
}

# Given a Set in the topic being saved, look in the query to see
# if there is a new value for the Set and generate a new
# Set statement.
sub _saveSet {
    my( $query, $web, $topic, $name, $value, $formDef, $prefix ) = @_;

    $prefix =~ /^(\s*)/;
    my $indent = $1;

    my $localPrefix = $prefix =~ /Local/ ? 'Local' : '';
    my $newValue = $query->param( $localPrefix.$name );
    $newValue = $value unless ( defined($newValue) );
    $newValue =~ s/^\s*(.*?)\s*$/$1/s;
    $newValue =~ s/\n/\n$indent/g;
    if( $formDef ) {
        my $fieldDef = _getField( $formDef, $name );
        my $type = $fieldDef->{type} || '';
        if ( $type eq 'label' ) {
            return "$prefix$name =$value";
        }
        if( $type && $type =~ /^(checkbox|select.*\+multi)/ ) {
            my @values = $query->param( $name );
            my %vset = ();
            foreach my $val ( @values ) {
                $val =~ s/^\s*//o;
                $val =~ s/\s*$//o;
                # skip empty values
                $vset{$val} = (defined $val && $val =~ /\S/);
            }
            my $isValues = ( $fieldDef->{type} =~ /\+values/ );
            $newValue = '';
            foreach my $option ( @{$fieldDef->getOptions()} ) {
                $option =~ s/^.*?[^\\]=(.*)$/$1/ if $isValues;
                # Maintain order of definition
                if( $vset{$option} ) {
                    $newValue .= ', ' if( $newValue && length( $value ) );
                    $newValue .= $option;
                }
            }
        }
    }
    # if no form def, it's just treated as text

    $prefix =~ s/\#?\b(Set|Local)\b/_determineHash( $query, $localPrefix.$name ).$1/e;

    return $prefix.$name.' = '.$newValue;
}

sub _determineHash {
    my( $query, $name ) = @_;
    my $checked = $query->param( "$name!enable" );
    return TWiki::Func::isTrue( $checked ) ? '' : '#';
}

1;
