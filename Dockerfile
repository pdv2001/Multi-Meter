#FROM mpercival/resin-rtl-sdr
FROM balenalib/raspberrypi3-node:10.10

MAINTAINER Pierre de Villiers

RUN sudo apt-get update && apt-get install -y curl python && \
    apt-get clean

WORKDIR /usr/local

RUN curl -O https://storage.googleapis.com/golang/go1.7.4.linux-armv6l.tar.gz && \
    tar xvf go1.7.4.linux-armv6l.tar.gz

WORKDIR /tmp/

ENV UDEV=1

#
# Install software packages needed to compile rtl_433 
#
RUN apt-get update && apt-get install -y \
	rtl-sdr \
	librtlsdr-dev \
	librtlsdr0 \
	git \
	automake \
	libtool \
	cmake \
        make

RUN mkdir /go
ENV GOPATH /go
ENV PATH /usr/local/go/bin:/go/bin:$PATH


#
# Pull RTL_433 source code from GIT, compile it and install it
#
RUN git clone https://github.com/merbanan/rtl_433.git \
	&& cd rtl_433/ \
	&& mkdir build \
	&& cd build \
	&& cmake ../ -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON \
	&& make \
	&& make install 
    
RUN go get github.com/bemasher/rtlamr

WORKDIR /etc/modprobe.d
COPY rtl-sdr-blacklist.conf .

RUN mkdir /app
WORKDIR /app

COPY daemon.sh .
COPY watchdog.sh .
RUN chmod +x *.sh
COPY rtl_433.conf .

CMD ./daemon.sh

