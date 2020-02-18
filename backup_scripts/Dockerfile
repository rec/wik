FROM python:3.8

VOLUME /root/.ssh

VOLUME /source
VOLUME /target

RUN pip3 install schedule

COPY backup.py .

CMD ["python", "backup.py", "/source", "/target"]
