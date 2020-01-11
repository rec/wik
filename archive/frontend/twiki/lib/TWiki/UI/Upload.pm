# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
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
# As per the GPL, removal of this notice is prohibited.
# The multiple File Upload support added in April 2010.
# The feature was sponsored by Twiki, Inc (sales@twiki.net)
#

=pod

---+ package TWiki::UI::Upload

UI delegate for attachment management functions

=cut

package TWiki::UI::Upload;

use strict;
use Assert;
use Error qw( :try );

require TWiki;
require TWiki::UI;
require TWiki::Sandbox;
require TWiki::OopsException;

=pod

---++ StaticMethod attach( $session )

=attach= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generates a prompt page for adding an attachment.

=cut

sub attach {
    my $session = shift;

    my $query   = $session->{request};
    my $webName = $session->{webName};
    my $topic   = $session->{topicName};

    my $fileName = $query->param('filename') || '';
    my $skin = $session->getSkin();

    TWiki::UI::checkWebExists( $session, $webName, $topic, 'attach' );

    my $tmpl          = '';
    my $text          = '';
    my $meta          = '';
    my $atext         = '';
    my $fileUser      = '';
    my $isHideChecked = '';
    my $users         = $session->{users};

    TWiki::UI::checkWebWritable( $session );

    TWiki::UI::checkAccess( $session, $webName, $topic, 'CHANGE',
        $session->{user} );
    TWiki::UI::checkTopicExists( $session, $webName, $topic,
        'upload files to' );

    ( $meta, $text ) =
      $session->{store}->readTopic( $session->{user}, $webName, $topic, undef );
    my $args = $meta->get( 'FILEATTACHMENT', $fileName );
    $args = {
        name    => $fileName,
        attr    => '',
        path    => '',
        comment => ''
      }
      unless ($args);

    if ( $args->{attr} =~ /h/o ) {
        $isHideChecked = 'checked';
    }

    # SMELL: why log attach before post is called?
    # FIXME: Move down, log only if successful (or with error msg?)
    # Attach is a read function, only has potential for a change
    if ( $TWiki::cfg{Log}{attach} ) {

        # write log entry
        $session->writeLog( 'attach', $webName . '.' . $topic, $fileName );
    }

    my $fileWikiUser = '';
    if ($fileName) {
        $tmpl = $session->templates->readTemplate( 'attachagain', $skin );
        my $u = $args->{user};
        $fileWikiUser = $users->webDotWikiName($u) if $u;
    }
    else {
        $tmpl = $session->templates->readTemplate( 'attachnew', $skin );
    }
    if ($fileName) {

        # must come after templates have been read
        $atext .= $session->attach->formatVersions( $webName, $topic, %$args );
    }
    $tmpl =~ s/%ATTACHTABLE%/$atext/g;
    $tmpl =~ s/%FILEUSER%/$fileWikiUser/g;
    $tmpl =~ s/%FILENAME%/$fileName/g;
    $session->enterContext( 'can_render_meta', $meta );
    $tmpl = $session->handleCommonTags( $tmpl, $webName, $topic );
    $tmpl = $session->renderer->getRenderedVersion( $tmpl, $webName, $topic );
    $tmpl =~ s/%HIDEFILE%/$isHideChecked/g;
    $tmpl =~ s/%FILEPATH%/$args->{path}/g;
    $args->{comment} = TWiki::entityEncode( $args->{comment} );
    $tmpl =~ s/%FILECOMMENT%/$args->{comment}/g;
    my $redirectTo = $query->param( 'redirectto' ) || '';
    $tmpl =~ s/%REDIRECTTO%/$redirectTo/g;

    $session->writeCompletePage($tmpl);
}

=pod

---++ StaticMethod upload( $session )

=upload= command handler.
This method is designed to be
invoked via the =UI::run= method.
CGI parameters, passed in $query:

| =hidefile= | if defined, will not show file in attachment table |
| =filepath= | |
| =filepath1= | |
| =filepath2= | | upto
| =filepath9= | | upto
| =filename= | |
| =filecomment= | comment to associate with file in attachment table |
| =createlink= | if defined, will create a link to file at end of topic |
| =changeproperties= | |
| =redirectto= | URL to redirect to after upload. ={AllowRedirectUrl}= must be enabled in =configure=. The parameter value can be a =TopicName=, a =Web.TopicName=, or a URL. Redirect to a URL only works if it is enabled in =configure=. |

Does the work of uploading a file to a topic. Designed to be useable for
a crude RPC (it will redirect to the 'view' script unless the
'noredirect' parameter is specified, in which case it will print a message to
STDOUT, starting with 'OK' on success and 'ERROR' on failure.

Your form should be defined similar to following: 
<form  enctype="multipart/form-data" action="%SCRIPTURLPATH{upload}%/%WEB%/%TOPIC% method="post">
<input  type="file" name="filepath" value="" size="70" />
<input  type="file" name="filepath1" value="" size="70" />
<input  type="file" name="filepath2" value="" size="70" />
<input type="file" name="filepath3" value="" size="70" />
....
<input type="submit" value='Upload file' /> 
</form>

=cut

sub upload {
    my $session = shift;

    my $query   = $session->{request};
    my $webName = $session->{webName};
    my $topic   = $session->{topicName};
    my $user    = $session->{user};

    if ( $query->request_method() !~ /^POST$/i ) {

        # upload script can only be called via POST method
        throw TWiki::OopsException(
            'attention',
            def    => 'post_method_only',
            web    => $webName,
            topic  => $topic,
            status => '405 Method Not Allowed',
            params => ['upload']
        );
    }

    #$action in this block/subroutine is used only for verification
    #of crypttoken
    my $cryptaction = 'upload';
    my %secureActions;
    map { $secureActions{ lc($_) } = 1; }
      split( /[\s,]+/, $TWiki::cfg{CryptToken}{SecureActions} );

    #If Crypt Token is requred for save action, one should not be able
    #go beyond following step without valid crypttokens.

    if (   $TWiki::cfg{CryptToken}{Enable}
        && $secureActions{ lc($cryptaction) } )
    {

        TWiki::UI::verifyCryptToken( $session, $query->param('crypttoken') );
    }

    TWiki::UI::checkWebExists( $session, $webName, $topic, 'attach files to' );
    TWiki::UI::checkTopicExists( $session, $webName, $topic,
        'attach files to' );
    TWiki::UI::checkWebWritable( $session );
    TWiki::UI::checkAccess( $session, $webName, $topic, 'CHANGE', $user );

    my $hideFile    = $query->param('hidefile')    || '';
    my $fileComment = $query->param('filecomment') || '';
    my $createLink  = $query->param('createlink')  || '';
    my $doPropsOnly = $query->param('changeproperties');
    my $updateField = $query->param('updatefield') || '';
    my $updateFormat = $query->param('updateformat') || '';

    $fileComment =~ s/[<>]//gos; # Item7833: Filter out < and > to block XSS 
    $fileComment =~ s/\s+/ /go;
    $fileComment =~ s/^\s*//o;
    $fileComment =~ s/\s*$//o;

    # below - @fileNames is array of files being uploaded
    # below - @upload_objs are array of TWiki::Request::Upload objects

    my @fileNames = grep { defined $query->{uploads}{$_} }
      map { $query->param("filepath$_") } ( '', 1 .. 9 );
    my @upload_objs = @{ $query->{uploads} }{@fileNames};

    my @origNames = ();    # If filenames are changed after uploading to
                           # topic, those should be shown to the user
                           # when upload is complete

    my @fileSizes   = ();
    my @fileDates   = ();
    my @tmpFilePath = ();

    unless ($doPropsOnly) {

        # Item6887: Configurable attachment behavior if file name differs
        my $existingFileName = $query->param('filename') || '';
        if( $existingFileName && $TWiki::cfg{AttachWithSameName} ) {
            if( $existingFileName =~ /(\.[^\.\/\\]+)$/ ) {
                my $existingType = lc( $1 );
                if( $fileNames[0] =~ /(\.[^\.\/\\]+)$/ ) {
                    my $newType = lc( $1 );
                    if( $newType ne $existingType ) {
                        throw TWiki::OopsException(
                            'attention',
                            def    => 'file_type_differs_upload',
                            web    => $webName,
                            topic  => $topic,
                            params => [ $newType, $existingType ]
                        );
                    }
                }
            }
            $fileNames[0] = $existingFileName;
        }

        my $i = 0;
        my $j = 0;

        # Following loop just makes sure we have at least some non-empty file
        # available to upload  to topic

        foreach my $fh (@upload_objs) {
            if ( defined $fh ) {

                try {
                    $tmpFilePath[$j] = $fh->tmpFileName();
                }
                catch Error::Simple with {

                    throw TWiki::OopsException(
                        'attention',
                        def    => 'zero_size_upload',
                        web    => $webName,
                        topic  => $topic,
                        params => [ ( $fileNames[$j] || '""' ) ]
                    );
                };
                $j++;
            }
        }

# Creating Array of original names for files, need to inform users about filename changes

        $j = 0;
        foreach my $f (@fileNames) {

            ( $fileNames[$j], $origNames[$j] ) =
              TWiki::Sandbox::sanitizeAttachmentName( $fileNames[$j] );
            $j++;
        }

        my $maxSize =
          $session->{prefs}->getPreferencesValue('ATTACHFILESIZELIMIT');
        $maxSize = 0 unless ( $maxSize =~ /([0-9]+)/o );

        $j = 0;
        my @stream_fhs = grep { defined $_ } map { $_->handle() } @upload_objs;

        foreach my $stream (@stream_fhs) {

            if ($stream) {
                my @stats = stat $stream;
                $fileSizes[$j] = $stats[7];    ## Local Variables
                $fileDates[$j] = $stats[9];    ## Local Variables

                unless ( $fileSizes[$j] && $fileNames[$j] ) {
                    throw TWiki::OopsException(
                        'attention',
                        def    => 'zero_size_upload',
                        web    => $webName,
                        topic  => $topic,
                        params => [ ( $fileNames[$j] || '""' ) ]
                    );
                }

                if ( $maxSize && $fileSizes[$j] > $maxSize * 1024 ) {
                    throw TWiki::OopsException(
                        'attention',
                        def    => 'oversized_upload',
                        web    => $webName,
                        topic  => $topic,
                        params => [ $fileNames[$j], $maxSize ]
                    );
                }

            }
            $j++;
        }

        $i = 0;
        foreach my $stream (@stream_fhs) {

            try {
                $session->{store}->saveAttachment(
                    $webName, $topic,
                    $fileNames[$i],
                    $user,
                    {
                        dontlog     => !$TWiki::cfg{Log}{upload},
                        comment     => $fileComment,
                        hide        => $hideFile,
                        createlink  => $createLink,
                        stream      => $stream,
                        filepath    => $fileNames[$i],
                        filesize    => $fileSizes[$i],
                        filedate    => $fileDates[$i],
                        tmpFilename => $tmpFilePath[$i],
                        updatefield => $updateField,
                        updateformat => $updateFormat,
                    }
                );
            }
            catch Error::Simple with {
                throw TWiki::OopsException(
                    'attention',
                    def    => 'save_error',
                    web    => $webName,
                    topic  => $topic,
                    params => [ shift->{-text} ]
                );
            };
            close($stream) if $stream;
            $i++;
        }

        $j = 0;
        my @names_changed = ();

        foreach my $file (@fileNames) {
            if ( $file ne $origNames[$j] ) {
                push @names_changed, $origNames[$j], $file;
            }
            $j++;
        }

        if ( !@names_changed ) {
            $session->redirect(
                $session->getScriptUrl( 1, 'view', $webName, $topic ),
                undef, 1 );

        }
        else {
            throw TWiki::OopsException(
                'attention',
                def    => 'upload_name_changed',
                web    => $webName,
                topic  => $topic,
                params => [@names_changed]
            );
        }

    }
    else {  # only properties change

        my $filePath = $query->param('filepath') || '';
        my $fileName = $query->param('filename') || '';
        if ( $filePath && !$fileName ) {
            $filePath =~ m|([^/\\]*$)|;
            $fileName = $1;
        }

        try {
            $session->{store}->saveAttachment(
                $webName, $topic,
                $fileName,
                $user,
                {
                    dontlog     => !$TWiki::cfg{Log}{upload},
                    comment     => $fileComment,
                    hide        => $hideFile,
                    createlink  => $createLink,
                    stream      => undef,
                    filepath    => $filePath,
                    filesize    => '',
                    filedate    => '',
                    tmpFilename => '',
                }
            );
        }
        catch Error::Simple with {
            throw TWiki::OopsException(
                'attention',
                def    => 'save_error',
                web    => $webName,
                topic  => $topic,
                params => [ shift->{-text} ]
            );
        };

        $session->redirect(
            $session->getScriptUrl( 1, 'view', $webName, $topic ),
            undef, 1 );

    }

 # generate a message useful for those calling this script from the command line
    my $message =
      ($doPropsOnly) ? 'properties changed' : "$fileNames[0] uploaded";

    print 'OK ', $message, "\n" if $session->inContext('command_line');
}

1;
