import os
from  queue import Empty, Queue
import schedule
import subprocess
import time


def main(source, target):
    queue = Queue()

    def call(*cmd):
        return subprocess.call(cmd)

    def rsync(period):
        t = os.path.join(target, period)
        call('rsync', '--archive', source, t)

    def git():
        # Check if anything has changed
        if call('git', 'diff-index', '--quiet', 'HEAD'):
            queue.put(None)

    def service_queue():
        while True:
            try:
                queue.get(timeout=2)
            except Empty:
                continue
            # Allow the wiki server time to write the RCS pages
            time.sleep(0.1)


    os.chdir(source)

    schedule.every().second.do(git)
    schedule.every().wednesday.at('5:32').do(rsync, 'weekly')
    schedule.every().day.at('4:32').do(rsync, 'daily')

    while True:
        schedule.run_pending()
        time.sleep(1)


if __name__ == '__main__':
    main(*sys.argv[1:])
