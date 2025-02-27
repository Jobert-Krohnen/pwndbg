# This dockerfile was created for development & testing purposes, for APT-based distro.
#
# Build as:             docker build -t pwndbg .
#
# For testing use:      docker run --rm -it --cap-add=SYS_PTRACE --security-opt seccomp=unconfined pwndbg bash
#
# For development, mount the directory so the host changes are reflected into container:
#   docker run -it --cap-add=SYS_PTRACE --security-opt seccomp=unconfined -v `pwd`:/pwndbg pwndbg bash
#

ARG image=ubuntu:20.04
FROM $image

WORKDIR /pwndbg

ENV LANG en_US.utf8
ENV TZ=America/New_York
ENV ZIGPATH=/opt/zig
ENV PWNDBG_VENV_PATH=/venv

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get update && \
    apt-get install -y locales && \
    rm -rf /var/lib/apt/lists/* && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    apt-get update && \
    apt-get install -y vim

ADD ./setup.sh /pwndbg/
ADD ./poetry.lock /pwndbg/
ADD ./pyproject.toml /pwndbg/
ADD ./dev-requirements.txt /pwndbg/

# pyproject.toml requires these files, pip install would fail
RUN touch README.md && mkdir pwndbg && touch pwndbg/empty.py && mkdir gdb-pt-dump && touch gdb-pt-dump/empty.py

# The `git submodule` is commented because it refreshes all the sub-modules in the project
# but at this time we only need the essentials for the set up. It will execute at the end.
RUN sed -i "s/^git submodule/#git submodule/" ./setup.sh && \
    DEBIAN_FRONTEND=noninteractive ./setup.sh

# Cleanup dummy files
RUN rm README.md && rm -rf pwndbg && rm -rf gdb-pt-dump

# Comment these lines if you won't run the tests.
ADD ./setup-dev.sh /pwndbg/
RUN ./setup-dev.sh

RUN echo "source /pwndbg/gdbinit.py" >> ~/.gdbinit.py

ADD . /pwndbg/

RUN git submodule update --init --recursive
