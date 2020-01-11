# ---+ Extensions
# ---++ BackupRestorePlugin

# **PATH M**
# Path to backup destination directory. Can be a volume mounted to the file system.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{BackupDir} = '/tmp';

# **STRING 3**
# Keep number of backups (e.g. delete old backups), 0 to keep all.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{KeepNumberOfBackups} = '7';

# **PATH M**
# Path to temp directory, used by BackupRestorePlugin daemon for temporary data.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{TempDir} = '/tmp';

# **STRING 50**
# Path to zip command with options to recursively archive files and directory.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{createZipCmd} = '/usr/bin/zip -r';

# **STRING 50**
# Path to unzip command with options to list all files.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{listZipCmd} = '/usr/bin/unzip -l';

# **STRING 50**
# Path to unzip command with options to unzip all files with option to overwrite existing files.
$TWiki::cfg{Plugins}{BackupRestorePlugin}{unZipCmd} = '/usr/bin/unzip -o';

# **BOOLEAN**
# Debug plugin. See output in data/debug.txt
$TWiki::cfg{Plugins}{BackupRestorePlugin}{Debug} = 0;

1;
