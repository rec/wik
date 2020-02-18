FROM ubuntu:18.04

COPY . .

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        python3.7 \
		git \
    --no-install-recommends && \
    rm -r /var/lib/apt/lists/*
    # && \
    # pip3 install -r requirements.txt

CMD /bin/bash start.sh
