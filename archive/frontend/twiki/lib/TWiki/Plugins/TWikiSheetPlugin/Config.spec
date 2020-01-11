# ---+ Extensions
# ---++ TWikiSheetPlugin

# **SELECT classic,toggle,edit**
# Select default mode of operation:
# <ul><li> In "classic" mode you see a regular TWiki table and an edit
# button; once pressed, the table switches into spreadsheet edit mode.
# </li><li> In "toggle" mode you see a spreadsheet in read-only mode and an edit
# button; once pressed, the table switches into spreadsheet edit mode.
# </li><li> In "edit" mode, the table is always in spreadsheet edit mode.
# </li></ul>
$TWiki::cfg{Plugins}{TWikiSheetPlugin}{Mode} = 'classic';

# **BOOLEAN**
# Default for concurrent edit. Set to 0 to disable, or 1 to enable. Users can
# override this with a concurrent="1" or "0" TWIKISHEET parameter.
$TWiki::cfg{Plugins}{TWikiSheetPlugin}{ConcurrentEdit} = 0;

# **NUMBER**
# Refresh rate for concurrent editing in seconds. All participating topics with
# TWiki Sheets will poll the server for changes at the specified rate. Keep in
# mind that a refresh rate of less than 5 seconds may put a high load on the
# server if there are many users who view TWiki Sheets at the sam time. Set to
# 0 to disable concurrent editing.
$TWiki::cfg{Plugins}{TWikiSheetPlugin}{ConcurrentEditRefresh} = 10;

# **BOOLEAN**
# Debug plugin. See output in data/debug.txt
$TWiki::cfg{Plugins}{TWikiSheetPlugin}{Debug} = 0;

1;
