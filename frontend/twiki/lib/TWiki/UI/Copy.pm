# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
# Based on parts of Ward Cunninghams original Wiki and JosWiki.
# Copyright (C) 1998 Markus Peter - SPiN GmbH (warpi@spin.de)
# Some changes by Dave Harris (drh@bhresearch.co.uk) incorporated
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

=pod

---+ package TWiki::UI::Copy

UI delegate for copy function

=cut

package TWiki::UI::Copy;

use strict;
use Error qw( :try );
use Assert;

require TWiki;
require TWiki::UI;
require TWiki::Meta;
require TWiki::OopsException;

# based on move() in TWiki::UI::Manage
sub doCopy {
    my ($session, $oldWeb, $oldTopic, $newWeb, $newTopic, $disableFixLinks) =
        @_;
    my $store = $session->{store};

    try {
        $store->copyTopic( $session->{user}, $oldWeb, $oldTopic,
			   $newWeb, $newTopic );
    } catch Error::Simple with {
        throw TWiki::OopsException( 'attention',
                                    web => $oldWeb,
                                    topic => $oldTopic,
                                    def => 'copy_error',
                                    params => [ shift->{-text},
                                                $newWeb,
                                                $newTopic ] );
    };

    return if ( $disableFixLinks );

    my( $meta, $text ) = $store->readTopic( undef, $newWeb, $newTopic );

    if( $oldWeb ne $newWeb ) {
        # If the web changed, replace local refs to the topics
        # in $oldWeb with full $oldWeb.topic references so that
        # they still work.
        $session->renderer()->replaceWebInternalReferences(
            \$text, $meta,
            $oldWeb, $oldTopic, $newWeb, $newTopic );
    }
    # Ok, now let's replace all self-referential links:
    my $options =
      {
       oldWeb => $newWeb,
       oldTopic => $oldTopic,
       newTopic => $newTopic,
       newWeb => $newWeb,
       inWeb => $newWeb,
       fullPaths => 0,
       spacedTopic => TWiki::spaceOutWikiWord( $oldTopic )
      };
    $options->{spacedTopic} =~ s/ / */g;
    $text = $session->renderer()->forEachLine(
        $text, \&TWiki::Render::replaceTopicReferences, $options );

    $store->saveTopic( $session->{user}, $newWeb, $newTopic, $text, $meta,
                       { minor => 1 } );

}

# Display screen so user can decide on new web and topic.
sub _newTopicScreen {
    my( $session, $oldWeb, $oldTopic, $newWeb, $newTopic, $doAllowNonWikiWord )
        = @_;

    my $query = $session->{request};
    my $tmplname = $query->param( 'template' ) || '';
    my $skin = $session->getSkin();

    $newTopic = $oldTopic unless ( $newTopic );
    $newWeb = $oldWeb unless ( $newWeb );
    my $nonWikiWordFlag = '';
    $nonWikiWordFlag = 'checked="checked"' if( $doAllowNonWikiWord );

    my $trashWebName = $session->trashWebName(web => $oldWeb);
    my $tmpl = $session->templates->readTemplate( 'copy', $skin );

    $tmpl =~ s/%NEW_WEB%/$newWeb/go;
    $tmpl =~ s/%NEW_TOPIC%/$newTopic/go;
    $tmpl =~ s/%NONWIKIWORDFLAG%/$nonWikiWordFlag/go;

    $tmpl = $session->handleCommonTags( $tmpl, $oldWeb, $oldTopic );
    $tmpl = $session->renderer()->getRenderedVersion($tmpl, $oldWeb, $oldTopic);
    $session->writeCompletePage( $tmpl );
}

=pod

---++ StaticMethod copy($session)

=copy= command handler.
This method is designed to be
invoked via the =UI::run= method.
Copy the given topic in its entirety including its history and attachments.

See TWiki.TWikiScripts for details of parameters.

=cut

sub copy {
    my $session = shift;

    my $oldTopic = $session->{topicName};
    my $oldWeb = $session->{webName};
    my $query = $session->{request};
    my $disableFixLinks = TWiki::isTrue($query->param( 'disablefixlinks' ));
    my $overwrite = TWiki::isTrue($query->param( 'overwrite' ));

    my $newTopic = $query->param( 'newtopic' ) || '';
    $newTopic = TWiki::Sandbox::untaintUnchecked( $newTopic );

    my $newWeb = $query->param( 'newweb' ) || $oldWeb;
    unless( !$newWeb || TWiki::isValidWebName( $newWeb, 1 )) {
        throw TWiki::OopsException
          ( 'attention', def =>'invalid_web_name', params => $newWeb );
    }
    $newWeb = TWiki::Sandbox::untaintUnchecked( $newWeb );

    my $doAllowNonWikiWord = $query->param( 'nonwikiword' ) || '';

    $newTopic =~ s/\s//go;
    $newTopic =~ s/$TWiki::cfg{NameFilter}//go;
    $newTopic = ucfirst $newTopic;   # Item3270

    TWiki::UI::checkWebExists( $session, $oldWeb, $oldTopic, 'copy' );

    if( $newTopic && !TWiki::isValidWikiWord( $newTopic ) ) {
        unless( $doAllowNonWikiWord ) {
            throw TWiki::OopsException( 'attention',
                                        web => $oldWeb,
                                        topic => $oldTopic,
                                        def => 'not_wikiword',
                                        params => [ $newTopic ] );
        }
        # Filter out dangerous characters (. and / may cause
        # issues with pathnames
        $newTopic =~ s![./]!_!g;
        $newTopic =~ s/($TWiki::cfg{NameFilter})//go;
    }

    # Must be able to view the source to copy it
    TWiki::UI::checkAccess( $session, $oldWeb, $oldTopic,
                            'view', $session->{user} );

    if ( $newTopic ) {
        ( $newWeb, $newTopic ) =
          $session->normalizeWebTopicName( $newWeb, $newTopic );
    }

    # Has user selected new name yet?
    if( ! $newTopic ) {
        _newTopicScreen( $session,
                         $oldWeb, $oldTopic,
                         $newWeb, $newTopic,
                         $doAllowNonWikiWord );
        return;
    }

    if( $oldWeb eq $newWeb && $oldTopic eq $newTopic ) {
	throw TWiki::OopsException( 'attention',
				    web => $oldWeb,
				    topic => $oldTopic,
				    def => 'copy_to_same_topic',
				    params => [] );
    }

    my $store = $session->{store};
    if ( $store->topicExists( $newWeb, $newTopic ) ) {
        if ( $overwrite ) {
            my $trashWeb = $session->trashWebName(web => $newWeb);
            my $trashTopic = $newWeb . $newTopic;
            my $suffix = 0;
            while ( $store->topicExists($trashWeb, $trashTopic) ) {
                $suffix++;
                $trashTopic = $newWeb . $newTopic . $suffix;
            }
            try {
                $store->moveTopic($newWeb, $newTopic, $trashWeb, $trashTopic,
                                  $session->{user});
            }
            catch Error::Simple with {
                throw TWiki::OopsException( 'attention',
                                            web => $oldWeb,
                                            topic => $oldTopic,
                                            def => 'copy_dest_delete_error',
                                            params => [ shift->{-text},
                                                        $newWeb,
                                                        $newTopic,
                                                        $trashWeb,
                                                        $trashTopic ] );
            }
        }
        else {
            throw TWiki::OopsException( 'attention',
                                        web => $oldWeb,
                                        topic => $oldTopic,
                                        def => 'copy_dest_exists',
                                        params => [ $newWeb, $newTopic ] );
        }
    }

    TWiki::UI::checkAccess( $session, $newWeb, $newTopic,
                            'change', $session->{user} );

    TWiki::UI::checkWebWritable( $session, $newWeb );
    doCopy($session, $oldWeb, $oldTopic, $newWeb, $newTopic, $disableFixLinks);
    $session->redirect(
	$session->getScriptUrl( 1, 'view', $newWeb, $newTopic ), undef, 1 );
}

1;
