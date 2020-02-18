from pathlib import Path
import os
import schedule
import subprocess
import sys
import time

RSYNC = 'rsync', '--archive', '-v', '--exclude=.git'
GIT_STATUS = 'git', 'status', '--porcelain'
GIT_COMMIT = 'git', 'commit', '-am'


def call(*args):
    print('$', *args)
    return subprocess.call(args)


def execute(*args):
    return subprocess.check_output(args, encoding='utf-8')


def changed_words(lines):
    for line in lines:
        is_version_control = ',' in line
        if line.endswith('.txt') and not is_version_control:
            action, filename = line.split(maxsplit=1)
            yield Path(filename).stem


def commit_all():
    subprocess.call(('git', 'add', '.'))

    out = execute(*GIT_STATUS)
    lines = [i.strip() for i in out.splitlines() if i.strip()]
    if lines:
        first = ', '.join(changed_words(lines))
        if len(first) > 50:
            first = first[:47] + '...'
        lines.insert(0, first)
        message = '\n'.join(lines or ['(None)']) + '\n'
        call(*GIT_COMMIT, message)


def main(source, target):
    def rsync(period):
        t = os.path.join(target, period)
        call(*RSYNC, source, t)

    schedule.every().second.do(commit_all)
    schedule.every().wednesday.at('05:32').do(rsync, 'weekly')
    schedule.every().day.at('04:32').do(rsync, 'daily')

    os.chdir(source)

    while True:
        schedule.run_pending()
        time.sleep(1)


if __name__ == '__main__':
    main(*sys.argv[1:])
