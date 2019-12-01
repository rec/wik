# ---+ Extensions
# ---++ DatePickerPlugin

# See also documentation at
# <a href="http://twiki.org/cgi-bin/view/Plugins/DatePickerPlugin">TWiki:Plugins/DatePickerPlugin</a>
# and <a href="http://www.dynarch.com/projects/calendar/">Mishoo's JS Calendar home</a>.

# **STRING 20**
# <b>Date format</b>. Default: %Y-%m-%d. Available date specifiers:
# <table><tr><td valign="top">
# %a - abbreviated weekday name <br />
# %A - full weekday name <br />
# %b - abbreviated month name <br />
# %B - full month name <br />
# %C - century number <br />
# %d - the day of the month ( 00 .. 31 ) <br />
# %e - the day of the month ( 0 .. 31 ) <br />
# %H - hour ( 00 .. 23 ) <br />
# %I - hour ( 01 .. 12 )
# </td><td valign="top">
# %j - day of the year ( 000 .. 366 ) <br />
# %k - hour ( 0 .. 23 ) <br />
# %l - hour ( 1 .. 12 ) <br />
# %m - month ( 01 .. 12 ) <br />
# %M - minute ( 00 .. 59 ) <br />
# %n - a newline character <br />
# %p - "PM" or "AM" <br />
# %P - "pm" or "am" <br />
# %S - second ( 00 .. 59 )
# </td><td valign="top"> 
# %s - number of seconds since Epoch <br />
# %t - a tab character <br />
# %U, %W, %V - the week number <br />
# %u - the day of the week ( 1 .. 7, 1 = MON ) <br />
# %w - the day of the week ( 0 .. 6, 0 = SUN ) <br />
# %y - year without the century ( 00 .. 99 ) <br />
# %Y - year including the century ( ex. 1979 ) <br />
# %% - a literal % character <br />
# &nbsp;
# </td></tr></table>
$TWiki::cfg{Plugins}{DatePickerPlugin}{Format} = '%Y-%m-%d';

# **STRING 10**
# <b>Interface language</b>. Default: en. Available: af, al, bg, big5, big5-utf8, br, ca, 
# cn_utf8, cs-utf8, cs-win, da, de, du, el, en, es, fi, fr, he-utf8, hr, hr-utf8, hu, 
# it, jp, ko, ko-utf8, lt, lt-utf8, lv, nl, no, pl, pl-utf8, pt, ro, ru, ru_win_, 
# si, sk, sp, sv, tr, zh.
$TWiki::cfg{Plugins}{DatePickerPlugin}{Lang} = 'en';

# **STRING 10**
# <b>Style</b>. Default: twiki. Available: blue, blue2, brown, green, system, tas, twiki, 
# win2k-1, win2k-2, win2k-cold-1, win2k-cold-2.
$TWiki::cfg{Plugins}{DatePickerPlugin}{Style} = 'twiki';

