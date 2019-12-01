Build instructions for new jquery, jquery-ui and jquery plugin releases releases:

1. jQuery root directory: This JQueryPlugin's attachment directory, e.g.

   $JQUERY_ROOT =  $TWIKIROOT/pub/TWiki/JQueryPlugin/

2. Download the latest jquery library from http://docs.jquery.com/Downloading_jQuery
into $JQUERY_ROOT, e.g.:

   wget http://code.jquery.com/jquery-1.10.2.min.js
   wget http://code.jquery.com/jquery-1.10.2.js

3. Download the latest migrate plugin from https://github.com/jquery/jquery-migrate/#readme
into $JQUERY_ROOT, use the minified production version e.g.:

   wget http://code.jquery.com/jquery-migrate-1.2.1.min.js

4. Copy the minified jquery library and migrate plugin to generic name:

   cp -p jquery-1.10.2.min.js jquery.js
   cp -p jquery-migrate-1.2.1.min.js jquery-migrate.js

5. Download the themes shipped with JQueryPlugin from http://jqueryui.com/download
into temporary directory $JQUERY_ROOT/tmp/. Currently used themes:

   black-tie, cupertino, redmond, smoothness (see note below), ui-lightness.

Download with all features. The downloaded theme package has always the same name, 
regardless of the theme name. Unzip the packages in the tmp directory, selected 
[A]ll to overwrite duplicate names.

Note: Do not download the smoothness theme, rather download a TWiki specific 
customization. View this modified this theme at:
    http://jqueryui.com/themeroller/?ffDefault=Verdana,Arial,sans-serif&fwDefault=normal&fsDefault=1.1em&cornerRadius=4px&bgColorHeader=c7c9d1&bgTextureHeader=03_highlight_soft.png&bgImgOpacityHeader=75&borderColorHeader=999dad&fcHeader=222222&iconColorHeader=222222&bgColorContent=ffffff&bgTextureContent=01_flat.png&bgImgOpacityContent=75&borderColorContent=aaaaaa&fcContent=222222&iconColorContent=222222&bgColorDefault=e6e6e6&bgTextureDefault=02_glass.png&bgImgOpacityDefault=75&borderColorDefault=d3d3d3&fcDefault=555555&iconColorDefault=888888&bgColorHover=dadada&bgTextureHover=02_glass.png&bgImgOpacityHover=75&borderColorHover=999999&fcHover=212121&iconColorHover=454545&bgColorActive=ffffff&bgTextureActive=02_glass.png&bgImgOpacityActive=65&borderColorActive=aaaaaa&fcActive=212121&iconColorActive=454545&bgColorHighlight=fbf9ee&bgTextureHighlight=02_glass.png&bgImgOpacityHighlight=55&borderColorHighlight=fcefa1&fcHighlight=363636&iconColorHighlight=2e83ff&bgColorError=fef1ec&bgTextureError=02_glass.png&bgImgOpacityError=95&borderColorError=cd0a0a&fcError=cd0a0a&iconColorError=cd0a0a&bgColorOverlay=666666&bgTextureOverlay=01_flat.png&bgImgOpacityOverlay=0&opacityOverlay=50&bgColorShadow=aaaaaa&bgTextureShadow=01_flat.png&bgImgOpacityShadow=0&opacityShadow=30&thicknessShadow=8px&offsetTopShadow=-8px&offsetLeftShadow=-8px&cornerRadiusShadow=8px

Then save it with custom theme name "smoothness".

6. Move jquery-ui js library from tmp to jQuery root:

   mv tmp/jquery-ui-1.10.3.custom/js/jquery-ui-1.10.3.custom.min.js .

7. Copy the minified jquery-ui library to generic name:

   cp -p jquery-ui-1.10.3.custom.min.js jquery-ui.js

8. Move jquery-ui themes from tmp to themes directory (after removing old themes):

   mv tmp/jquery-ui-1.10.3.custom/css/* themes/

9. Copy the theme css files with version to generic name:

   mv themes/black-tie/jquery-ui-1.10.3.custom.min.css themes/black-tie/jquery-ui.black-tie.css
   mv themes/cupertino/jquery-ui-1.10.3.custom.min.css themes/cupertino/jquery-ui.cupertino.css
   # etc...

10. Move i18n files from tmp to i18n directory (after removing old files):

   mv tmp/jquery-ui-1.10.3.custom/development-bundle/ui/i18n/* i18n/

11. To update jquery plugins: Copy plugin to tmp directory and unpack, example: jquery.foobar.zip

   mv tmp/jquery.foobar.css .
   mv tmp/jquery.foobar.js jquery.foobar.uncompressed.js
   /var/www/tools/minifyjs jquery.foobar.uncompressed.js > jquery.foobar.js

12. Make jquery-all.css and jquery-all.js

   make clean
   make
   # this will create the targets based on Makefile rule

13. Create gz files

   tar -zcvf jquery-1.10.2.js.gz jquery-1.10.2.min.js
   tar -zcvf jquery-all.js.gz jquery-all.js

14. Update the manifest with the proper file list
